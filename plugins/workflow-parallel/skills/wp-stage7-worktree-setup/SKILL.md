---
name: wp-stage7-worktree-setup
description: "workflow-parallel Stage 7. git worktree 일괄 생성 + pnpm install + untracked 보정. Trigger on: /wp:stage7-worktree-setup, worktree 생성, 워크트리 셋업, 병렬 worktree. Stage 6 의 ticket 매핑을 받아 N 개 worktree 를 sequential 하게 추가하고 pnpm 모노레포 시 sequential install 까지 수행."
---

# Stage 7 — Worktree Setup

`workflow-parallel` 9-stage 흐름의 7번째 단계. Wave 1 의 ticket 수만큼 git worktree 를 추가하고 의존성 설치 + plan/TODO 보정까지 끝낸 상태로 Stage 8 dispatch 에 넘김.

## 입력

- Stage 6 산출 ticket 매핑 (각 ticket = key + slug + Wave)
- 메인 repo 경로 (메인 세션 cwd)
- main branch 이름 (기본 `main`, 자동 추론)
- 부모 plan 파일 경로 + TODO.md 경로

## 실행 순서

### Step 1 — branch convention 추론 + confirm

`git log --oneline -50` + `git branch -a` 로 prefix 패턴 추론 (예: `MCP-1234-some-slug`). 후보를 사용자에게 보고하고 confirm 받음 (R6 위험 완화).

### Step 2 — main branch 확인 + fetch

```
git rev-parse --abbrev-ref HEAD
git remote show origin | grep "HEAD branch"
git fetch origin <main>
```

main 이름이 모호하면 `AskUserQuestion`.

### Step 3 — worktree base 디렉토리 결정

기본: 메인 repo 의 형제 위치 (`<repo>/../<repo>-<TICKET-KEY>/`). PLAN §5 #6 결정 그대로.

### Step 4 — 스크립트 실행

`scripts/git-worktree-setup.sh` 호출. 인자 형식 (스크립트 명세 참조):

**필수 인자**: `--main`, `--repo`, `--pair` (1개 이상)
**선택 인자**: `--plan`, `--todo` (untracked 보정용 — 생략 시 보정 단계 skip)

```
bash scripts/git-worktree-setup.sh \
  --main <main-branch> \              # 필수
  --repo <main-repo-path> \           # 필수
  --pair <TICKET-KEY>:<slug> \        # 필수, 1개 이상 (반복 가능)
  --pair <TICKET-KEY>:<slug> \
  [--plan <plan-path>] \              # 선택 (untracked 시 worktree로 cp)
  [--todo <todo-path>]                # 선택 (untracked 시 worktree로 cp)
```

스크립트는 다음을 수행:

1. fetch (이미 했어도 idempotent)
2. 각 ticket 에 대해 sequential `git worktree add <path> -b <branch> origin/<main>`
3. `pnpm-workspace.yaml` 또는 `pnpm-lock.yaml` 감지 시 sequential `pnpm install`
4. 메인의 plan / TODO 가 untracked 면 worktree 에 cp

진행 상태는 stdout 으로 보고 (R4 완화 — pnpm install 시간 가시화).

### Step 5 — 검증

각 worktree 에 대해:

- `git -C <path> rev-parse HEAD` 로 브랜치 head 확인
- `node_modules` 존재 여부 (pnpm 모노레포의 경우)
- `<path>/TODO.md` / `<path>/<plan>` 파일 존재

실패한 worktree 는 사용자에게 보고하고 재시도 여부 확인.

### Step 6 — 매핑 테이블 갱신 + 보고

ticket key → worktree path → branch 매핑을 출력. Stage 8 dispatch 의 입력이 됨.

## 종료 조건

- N 개 worktree 가 생성됨
- 각 worktree 에 node_modules + plan + TODO 가 존재
- 매핑 테이블이 Stage 8 에 넘길 수 있는 형태

## Rules

1. worktree add 는 sequential (lockfile / .git/worktrees 동시 쓰기 충돌 회피)
2. pnpm install 은 sequential (pnpm store lock 회피)
3. branch convention 은 자동 추론 후 반드시 사용자 confirm (R6)
4. 메인 repo 는 절대 건드리지 않음 — 모든 작업은 worktree 에서
5. untracked plan / TODO 는 cp 로 보정 (worktree 는 새 브랜치라 git tracked 만 따라옴)
6. 한 worktree 라도 실패하면 즉시 정지하고 보고. 부분 성공으로 다음 단계 진행 금지
