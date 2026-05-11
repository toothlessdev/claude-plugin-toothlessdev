---
name: wp-stage8-dispatch
description: "Stage 8 of /workflow:parallel — cmux pane dispatch. Trigger on: /wp:stage8-dispatch, dispatch panes, cmux dispatch, parallel pane boot. Sends /exit + claude restart + standardized boot prompt to each cmux pane mapped to a Wave 1 ticket, then verifies via read-screen."
---

# Stage 8 — cmux Pane Dispatch

> Wave 1 ticket 수만큼의 cmux pane에 worktree 세션을 부팅. 표준 boot prompt 를 send + Enter 후 read-screen 으로 작업 시작 검증.
>
> 출처: `parallel-orchestrate-PLAN.md` §2 Stage 8 / `parallel-orchestrate-IMPL.md` Build 4 + Build 6.

## 사전 조건

- Stage 7 (`wp-stage7-worktree-setup`) 완료 — N 개 worktree + 브랜치 + node_modules 준비됨
- Stage 7 결과: ticket key ↔ branch ↔ worktree 매핑 테이블 보유
- cmux 호출 방식 결정 (IMPL.md Q1) — MCP / CLI / tmux 호환 중 하나
- `templates/boot-prompt.md` 존재

## 실행 흐름

### Step 1 — cmux pane 가용성 검출

가용 pane 수가 Wave 1 ticket 수보다 적으면 사용자에게 "수동으로 split 후 재호출" 안내 (PLAN.md §5 #7 결정: **자동 split 안 함, layout 깨질 위험**).

```
list-panes → 가용 pane = M
needed = len(Wave 1 tickets) = K
if M < K:
  사용자에게 보고 후 정지 ("cmux 에서 K-M 개 pane 추가로 split 해줘")
```

### Step 2 — pane ↔ ticket 매핑 확정

사용자에게 매핑 테이블 제시 후 confirm.

```
pane-1 → MCP-XXXX (~/Desktop/<repo>-MCP-XXXX/)
pane-2 → MCP-YYYY (~/Desktop/<repo>-MCP-YYYY/)
...
```

`AskUserQuestion` 으로 "이 매핑 OK?" 확인.

### Step 3 — 각 pane 에 dispatch

각 pane 마다 sequential 실행 (병렬 send 는 cmux state race 위험). 실제 동작은 `scripts/cmux-dispatch.sh` 를 그대로 따름:

1. `/exit` send + Enter → 고정 `SETTLE_MS=1500ms` 대기 (기존 claude 종료)
2. `cd <worktree> && claude --dangerously-skip-permissions` send + Enter → 고정 `PROMPT_DELAY_MS=2000ms` 대기 (claude restart)
3. `templates/boot-prompt.md` 의 placeholder 치환 (모두 더블 중괄호 `{{VAR}}` 형식):
   - `{{plan-path}}` `{{TICKET-KEY}}` `{{N}}` `{{BRANCH}}` `{{MAIN}}` `{{DEPS}}` `{{CLOUDID}}` `{{SECTION}}`
4. 치환된 boot prompt send → 500ms 대기 → Enter

> **주의**: 현재 스크립트는 polling-based readiness 검증을 하지 않고 고정 sleep 만 사용. claude restart 가 느린 환경에서는 boot prompt 가 무시될 수 있음. 그 경우 `--skip-exit` 로 재실행하거나 SETTLE_MS/PROMPT_DELAY_MS 를 늘려서 호출.

### Step 4 — 작업 시작 검증

각 pane 에 `read-screen` 1 회 → claude 가 첫 tool call (보통 `mcp__atlassian__getJiraIssue`) 시작했는지 확인. 미시작 pane 은 별도 보고.

### Step 5 — 산출 보고

```
## Stage 8 dispatch 완료

| pane | ticket | branch | worktree | 상태 |
|------|--------|--------|----------|------|
| 1 | MCP-XXXX | MCP-XXXX-foo | ~/Desktop/<repo>-MCP-XXXX/ | ✅ 시작 |
| 2 | MCP-YYYY | MCP-YYYY-bar | ~/Desktop/<repo>-MCP-YYYY/ | ✅ 시작 |
| 3 | MCP-ZZZZ | MCP-ZZZZ-baz | ~/Desktop/<repo>-MCP-ZZZZ/ | ⚠️ 미시작 (수동 확인 필요) |
```

## Confirm Gate

dispatch 완료 + 검증 결과 보고 후 사용자에게:

> "Stage 9 (orchestrate-monitor) 로 넘어갈까요?"

응답 대기. OK 면 메인 SKILL 이 다음 stage 호출.

## 실패 처리

- pane 부족: Step 1 에서 정지, 사용자 수동 split 안내
- `/exit` 미응답: 스크립트는 고정 sleep 만 하므로 자동 감지 불가 — Step 4 read-screen 결과로 사용자 판단 후 해당 pane 만 수동 재실행 (`scripts/cmux-dispatch.sh --skip-exit ...`)
- claude restart 실패 (auth / path 오류): 스크립트는 `set -euo pipefail` 로 즉시 종료 — 재시도 자동화 없음. 사용자 보고 후 수동 재실행
- read-screen 결과 비어있음: 스크립트가 `[warn]` 만 출력하고 진행 — 사용자에게 pane 별 수동 확인 요청
- boot prompt 미치환 placeholder: 메인 SKILL 단계에서 즉시 정지 (스크립트 호출 전에 검증)

## Rules

1. cmux 호출 방식 미확정 시 dispatch 시작 금지 (IMPL.md Q1 해소 필요)
2. pane 매핑은 사용자 confirm 전 절대 send 금지
3. 모든 send 는 sequential (race 방지)
4. boot prompt 의 `{{TICKET-KEY}}` `{{BRANCH}}` `{{CLOUDID}}` 누락 시 송신 금지 (모든 placeholder 는 더블 중괄호 형식)
5. dispatch 후 read-screen 검증 없이 Stage 9 로 넘어가지 않음
