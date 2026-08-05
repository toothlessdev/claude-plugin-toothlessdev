#!/usr/bin/env bash
#
# 임시 워크트리를 제거하고 원본 저장소가 오염되지 않았는지 검증한다.
#
#   teardown-worktree.sh <repo-root> <work-dir> [status-baseline-file]
#
# baseline 파일을 주면 실행 전 `git status --porcelain` 스냅샷과 비교한다.
# 오염이 감지되면 exit 1 — 호출자는 이것을 리포트보다 먼저 사용자에게 알려야 한다.

set -uo pipefail

REPO_ROOT="${1:?repo-root required}"
WORK_DIR="${2:?work-dir required}"
BASELINE="${3:-}"

WT="$WORK_DIR/wt"
VIOLATION=0

# 테스트 산출물은 워크트리를 지우기 전에 회수한다. 순서가 바뀌면 같이 사라진다.
if [ -d "$WT/.pr-review-tests" ]; then
    mkdir -p "$WORK_DIR/tests"
    cp -R "$WT/.pr-review-tests/." "$WORK_DIR/tests/" 2>/dev/null || true
    echo "테스트 산출물 회수: $WORK_DIR/tests/"
fi

if [ -e "$WT" ]; then
    git -C "$REPO_ROOT" worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"
fi
git -C "$REPO_ROOT" worktree prune

echo "=== 원본 저장소 불변식 검증 ==="

# AC-5: 임시 워크트리 잔여 없음
if git -C "$REPO_ROOT" worktree list --porcelain | grep -q "^worktree $WT$"; then
    echo "위반: 워크트리가 남아 있다 — $WT"
    VIOLATION=1
else
    echo "OK  워크트리 정리됨"
fi

# AC-4: status 동일
CURRENT="$(git -C "$REPO_ROOT" status --porcelain)"
if [ -n "$BASELINE" ] && [ -f "$BASELINE" ]; then
    if ! printf '%s\n' "$CURRENT" | diff -q - "$BASELINE" >/dev/null 2>&1; then
        echo "위반: git status 가 실행 전과 다르다"
        printf '%s\n' "$CURRENT" | diff - "$BASELINE" | head -20
        VIOLATION=1
    else
        echo "OK  git status 실행 전과 동일"
    fi
else
    echo "SKIP git status 비교 — baseline 파일이 없다"
fi

# AC-6: 의존성 파일 무변경
DEP_CHANGES="$(git -C "$REPO_ROOT" status --porcelain -- package.json pnpm-lock.yaml yarn.lock package-lock.json)"
if [ -n "$DEP_CHANGES" ]; then
    echo "위반: 의존성 파일이 변경됐다"
    printf '%s\n' "$DEP_CHANGES"
    VIOLATION=1
else
    echo "OK  package.json / lockfile 무변경"
fi

# AC-7: 테스트 파일 유출 없음
LEAKED="$(git -C "$REPO_ROOT" status --porcelain --ignored 2>/dev/null | grep -c '\.pr-review-tests\|vitest\.pr-review\.config' || true)"
if [ "$LEAKED" -gt 0 ]; then
    echo "위반: 테스트 산출물이 원본 저장소에 남았다 ($LEAKED 건)"
    VIOLATION=1
else
    echo "OK  테스트 산출물 유출 없음"
fi

exit "$VIOLATION"
