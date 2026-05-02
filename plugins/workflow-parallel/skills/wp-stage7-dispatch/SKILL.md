---
name: wp-stage7-dispatch
description: "Stage 7 of /workflow:parallel — cmux pane dispatch. Trigger on: /wp:stage7-dispatch, dispatch panes, cmux dispatch, parallel pane boot. Sends /exit + claude restart + standardized boot prompt to each cmux pane mapped to a Wave 1 ticket, then verifies via read-screen."
---

# Stage 7 — cmux Pane Dispatch

> Wave 1 ticket 수만큼의 cmux pane에 worktree 세션을 부팅. 표준 boot prompt 를 send + Enter 후 read-screen 으로 작업 시작 검증.
>
> 출처: `parallel-orchestrate-PLAN.md` §2 Stage 7 / `parallel-orchestrate-IMPL.md` Build 4 + Build 6.

## 사전 조건

- Stage 6 (`wp-stage6-worktree-setup`) 완료 — N 개 worktree + 브랜치 + node_modules 준비됨
- Stage 5 결과: ticket key ↔ branch ↔ worktree 매핑 테이블 보유
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

각 pane 마다 sequential 실행 (병렬 send 는 cmux state race 위험):

1. `/exit` send + Enter → 기존 claude 종료 대기
2. `cd <worktree> && claude --dangerously-skip-permissions` send + Enter
3. claude prompt 노출 대기 (read-screen polling, 최대 30초)
4. `templates/boot-prompt.md` 의 placeholder 치환:
   - `{plan-path}` `{TICKET-KEY}` `{N}` `{BRANCH}` `{MAIN}` `{DEPS}` `{CLOUDID}` `{SECTION}`
5. 치환된 boot prompt send + Enter

활용 가능: `scripts/cmux-dispatch.sh` (Build 4 산출물).

### Step 4 — 작업 시작 검증

각 pane 에 `read-screen` 1 회 → claude 가 첫 tool call (보통 `mcp__atlassian__getJiraIssue`) 시작했는지 확인. 미시작 pane 은 별도 보고.

### Step 5 — 산출 보고

```
## Stage 7 dispatch 완료

| pane | ticket | branch | worktree | 상태 |
|------|--------|--------|----------|------|
| 1 | MCP-XXXX | MCP-XXXX-foo | ~/Desktop/<repo>-MCP-XXXX/ | ✅ 시작 |
| 2 | MCP-YYYY | MCP-YYYY-bar | ~/Desktop/<repo>-MCP-YYYY/ | ✅ 시작 |
| 3 | MCP-ZZZZ | MCP-ZZZZ-baz | ~/Desktop/<repo>-MCP-ZZZZ/ | ⚠️ 미시작 (수동 확인 필요) |
```

## Confirm Gate

dispatch 완료 + 검증 결과 보고 후 사용자에게:

> "Stage 8 (orchestrate-monitor) 로 넘어갈까요?"

응답 대기. OK 면 메인 SKILL 이 다음 stage 호출.

## 실패 처리

- pane 부족: Step 1 에서 정지, 사용자 수동 split 안내
- `/exit` 미응답: 해당 pane skip 후 보고
- claude restart 실패 (auth / path 오류): pane 단위로 재시도 1회, 그래도 실패면 사용자 보고
- boot prompt 미치환 placeholder: 즉시 정지 (잘못된 prompt 가 worker 를 헷갈리게 함)

## Rules

1. cmux 호출 방식 미확정 시 dispatch 시작 금지 (IMPL.md Q1 해소 필요)
2. pane 매핑은 사용자 confirm 전 절대 send 금지
3. 모든 send 는 sequential (race 방지)
4. boot prompt 의 `{TICKET-KEY}` `{BRANCH}` `{CLOUDID}` 누락 시 송신 금지
5. dispatch 후 read-screen 검증 없이 Stage 8 로 넘어가지 않음
