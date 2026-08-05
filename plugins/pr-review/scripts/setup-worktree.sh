#!/usr/bin/env bash
#
# PR 브랜치를 격리된 detached worktree 로 체크아웃하고 테스트 러너를 부트스트랩한다.
#
#   setup-worktree.sh <repo-root> <work-dir> <pr-number>
#
# 원본 워킹트리는 절대 건드리지 않는다. 브랜치도 만들지 않는다(detached).
# 결과는 <work-dir>/bootstrap.md 에 기록되고, 러너를 못 세워도 exit 0 이다 —
# "테스트를 못 돌렸다" 는 파이프라인이 계속 진행하며 보고해야 할 상태이지
# 스크립트의 실패가 아니다.

set -uo pipefail

REPO_ROOT="${1:?repo-root required}"
WORK_DIR="${2:?work-dir required}"
PR_NUMBER="${3:?pr-number required}"

WT="$WORK_DIR/wt"
REPORT="$WORK_DIR/bootstrap.md"
TEST_DIR_NAME=".pr-review-tests"

mkdir -p "$WORK_DIR"
: > "$REPORT"

say() { printf '%s\n' "$*" | tee -a "$REPORT" >&2; }
fail() { say ""; say "## 결과: 실패"; say ""; say "$*"; say ""; say "테스트는 작성하되 **미실행** 으로 표시한다."; exit 0; }

say "# 부트스트랩 — PR #$PR_NUMBER"
say ""

# ---------------------------------------------------------------- worktree

if [ -e "$WT" ]; then
    say "- 기존 워크트리 발견 → 제거 후 재생성"
    git -C "$REPO_ROOT" worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"
    git -C "$REPO_ROOT" worktree prune
fi

say "- PR head fetch"
if ! git -C "$REPO_ROOT" fetch --quiet origin "pull/$PR_NUMBER/head" 2>>"$REPORT"; then
    fail "\`git fetch origin pull/$PR_NUMBER/head\` 실패. PR 번호나 remote 를 확인하라."
fi

HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse FETCH_HEAD)"
say "- head SHA: \`$HEAD_SHA\`"

# detached 로 만든다. 브랜치를 만들면 원본 저장소에 이름이 남고 정리 대상이 늘어난다.
if ! git -C "$REPO_ROOT" worktree add --detach --quiet "$WT" "$HEAD_SHA" 2>>"$REPORT"; then
    fail "\`git worktree add\` 실패."
fi
say "- 워크트리: \`$WT\` (detached)"

# ------------------------------------------------------- 패키지 매니저 감지

cd "$WT" || fail "워크트리로 이동 실패"

if [ -f pnpm-lock.yaml ]; then
    PM=pnpm; INSTALL="pnpm install --ignore-scripts"; ADD="pnpm add -D --ignore-scripts"
elif [ -f yarn.lock ]; then
    PM=yarn; INSTALL="yarn install --ignore-scripts"; ADD="yarn add -D --ignore-scripts"
elif [ -f package-lock.json ]; then
    PM=npm; INSTALL="npm install --ignore-scripts"; ADD="npm install -D --ignore-scripts"
elif [ -f package.json ]; then
    PM=npm; INSTALL="npm install --ignore-scripts"; ADD="npm install -D --ignore-scripts"
else
    fail "\`package.json\` 이 없다. Node 프로젝트가 아니면 이 경로를 쓸 수 없다."
fi

command -v "$PM" >/dev/null 2>&1 || fail "\`$PM\` 을 PATH 에서 찾을 수 없다."
say "- 패키지 매니저: \`$PM\`"

# postinstall 이 husky 설치나 저장소 쓰기를 시도하는 경우가 있어 --ignore-scripts 를 쓴다.
# 테스트 실행에는 대개 무해하고, 원본 오염 위험을 하나 줄인다.

say "- 의존성 설치 중 (전체, 수 분 소요)"
if ! $INSTALL >>"$REPORT" 2>&1; then
    fail "의존성 설치 실패. 위 로그 참조."
fi
say "- 의존성 설치 완료"

# --------------------------------------------------------------- 러너 감지

RUNNER=""
if [ -f vitest.config.ts ] || [ -f vitest.config.js ] || [ -f vitest.config.mts ]; then
    RUNNER=vitest
elif [ -f jest.config.ts ] || [ -f jest.config.js ] || [ -f jest.config.mjs ]; then
    RUNNER=jest
elif node -e "const p=require('./package.json');process.exit((p.devDependencies?.vitest||p.dependencies?.vitest)?0:1)" 2>/dev/null; then
    RUNNER=vitest
elif node -e "const p=require('./package.json');process.exit((p.devDependencies?.jest||p.dependencies?.jest)?0:1)" 2>/dev/null; then
    RUNNER=jest
fi

mkdir -p "$TEST_DIR_NAME"

if [ -n "$RUNNER" ]; then
    say "- 기존 러너 감지: \`$RUNNER\`"
else
    # vitest 메이저는 프로젝트의 vite 메이저에 묶여 있다. 최신을 고정으로 박으면
    # peer 불일치로 러너가 아예 서지 않는다 (vitest 4 + vite 5 → module-runner
    # subpath 부재로 startup error, 2026-08-05 실측).
    VITE_MAJOR="$(node -e "try{console.log(require('vite/package.json').version.split('.')[0])}catch(e){}" 2>/dev/null)"

    case "$VITE_MAJOR" in
        5) VITEST_RANGE="^3" ;;   # vitest 3 peer: vite ^5 || ^6
        6|7|8) VITEST_RANGE="^4" ;;
        *) VITEST_RANGE="^3" ;;   # vite 미설치·판정 불가 → 호환 범위가 넓은 쪽
    esac
    say "- 러너 없음 → vitest\`$VITEST_RANGE\` 임시 설치 (감지된 vite major: \`${VITE_MAJOR:-없음}\`)"

    if ! $ADD "vitest@$VITEST_RANGE" "@vitest/coverage-v8@$VITEST_RANGE" jsdom \
        @testing-library/react@^16 @testing-library/jest-dom@^6 @testing-library/user-event \
        >>"$REPORT" 2>&1; then
        fail "vitest 설치 실패. 위 로그 참조."
    fi
    RUNNER=vitest
    say "- vitest 설치 완료"
fi

# ------------------------------------------------------------ vitest 설정
#
# 프로젝트 설정을 재사용하지 않고 전용 config 를 쓴다. 프로젝트의 vite.config 는
# 빌드용이라 test 블록이 없는 경우가 많고, 있더라도 include 범위가 우리 테스트
# 디렉터리를 덮지 않는다. 파일명을 분리해 기존 설정과 충돌하지 않게 한다.

if [ "$RUNNER" = vitest ]; then
    if [ -d src ]; then
        ALIAS_BLOCK="{ '@': r('./src') }"
    else
        ALIAS_BLOCK="{}"
    fi

    cat > vitest.pr-review.config.mts <<EOF
import { defineConfig } from 'vitest/config';
import { fileURLToPath } from 'node:url';

const r = (p: string) => fileURLToPath(new URL(p, import.meta.url));

export default defineConfig({
    resolve: {
        alias: $ALIAS_BLOCK,
    },
    test: {
        include: ['$TEST_DIR_NAME/**/*.test.{ts,tsx}'],
        environment: 'jsdom',
        globals: true,
        css: false,
        setupFiles: ['./$TEST_DIR_NAME/setup.ts'],
    },
});
EOF

    cat > "$TEST_DIR_NAME/setup.ts" <<'EOF'
import '@testing-library/jest-dom/vitest';
EOF

    say "- 설정 생성: \`vitest.pr-review.config.mts\`, \`$TEST_DIR_NAME/setup.ts\`"
fi

# --------------------------------------------------------------- 스모크 테스트

cat > "$TEST_DIR_NAME/smoke.test.ts" <<'EOF'
import { describe, it, expect } from 'vitest';

describe('부트스트랩 스모크', () => {
    it('러너가 동작한다', () => {
        expect(1 + 1).toBe(2);
    });
});
EOF

say "- 스모크 테스트 실행"
if [ "$RUNNER" = vitest ]; then
    SMOKE_CMD="npx vitest run --config vitest.pr-review.config.mts $TEST_DIR_NAME/smoke.test.ts"
else
    SMOKE_CMD="npx jest $TEST_DIR_NAME/smoke.test.ts"
fi

if ! $SMOKE_CMD >>"$REPORT" 2>&1; then
    fail "스모크 테스트 실패 — 러너가 서지 않았다. 위 로그 참조."
fi

rm -f "$TEST_DIR_NAME/smoke.test.ts"

say ""
say "## 결과: 성공"
say ""
say "- 워크트리: \`$WT\`"
say "- 러너: \`$RUNNER\`"
say "- 테스트 디렉터리: \`$WT/$TEST_DIR_NAME/\`"
if [ "$RUNNER" = vitest ]; then
    say "- 실행 명령: \`npx vitest run --config vitest.pr-review.config.mts --reporter=json\`"
else
    say "- 실행 명령: \`npx jest --json\`"
fi
exit 0
