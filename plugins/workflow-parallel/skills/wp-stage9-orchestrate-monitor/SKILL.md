---
name: wp-stage9-orchestrate-monitor
description: "Stage 9 of /workflow:parallel — orchestrate-monitor. Trigger on: /wp:stage9-orchestrate-monitor, monitor panes, wave progress, PR detection. On-demand monitoring of dispatched cmux panes via read-screen, detects PR creation, advances to next Wave."
---

# Stage 9 — Orchestrate Monitor

> 메인 세션이 dispatch 된 worker pane 들의 진행을 on-demand 로 폴링. PR 생성 감지 / Wave 완료 / 다음 Wave dispatch 결정.
>
> 출처: `parallel-orchestrate-PLAN.md` §2 Stage 9 / §5 #8 (on-demand 우선, auto polling 은 토큰 낭비).

## 사전 조건

- Stage 8 (`wp-stage8-dispatch`) 완료 — pane → ticket 매핑 테이블 보유
- 각 worker pane 에서 claude 가 작업 진행 중

## 실행 흐름

### Step 1 — 폴링 모드 결정

PLAN.md §5 #8 결정: **on-demand 우선**. 사용자가 "상태 보고" / "monitor" 등 트리거할 때만 read-screen.

자동 폴링이 필요하면:

- `ScheduleWakeup` 으로 30분~1시간 단위 wakeup
- 토큰 비용 / 노이즈 위험 사용자에게 사전 고지

### Step 2 — 각 pane read-screen

```
for pane in mapping:
  screen = read-screen(pane)
  status = classify(screen)
  # status ∈ { 진행중, idle, blocked, PR-created, errored }
```

분류 규칙:

- `gh pr create` 출력에 PR URL → **PR-created**
- claude prompt 만 노출 (마지막 tool call 후 응답 없음) → **idle / blocked**
- error / stack trace → **errored**
- thinking spinner / tool call 진행 → **진행중**

### Step 3 — 노이즈 필터링

PLAN.md §2 Stage 9 명시: spawn 된 claude 의 thinking spinner / 단순 status 변화는 보고하지 않음. **본문 변화만** 사용자에게 노출.

이전 read-screen 과 비교 → diff 가 의미 있을 때만 사용자에게 보고.

### Step 4 — 사용자 보고

```
## Wave 1 진행 상태

| pane | ticket | 상태 | 마지막 변화 |
|------|--------|------|------------|
| 1 | MCP-XXXX | ✅ PR-created | https://github.com/.../pull/123 |
| 2 | MCP-YYYY | 🔄 진행중 | (테스트 작성 중) |
| 3 | MCP-ZZZZ | ⚠️ blocked | (확인 필요) |
```

PR 생성된 ticket 은 diff 링크 + 1 줄 요약 (gh 명령으로 추가 fetch).

### Step 5 — Wave 진행 결정

Wave 1 의 모든 ticket 이 **PR-created** 면:

> "Wave 1 완료. Wave 2 ticket 들을 dispatch 할까요?"

응답:

- OK → Stage 7 (`wp-stage7-worktree-setup`) 부터 Wave 2 ticket 들로 재호출
- Wait → 사용자가 PR review / merge 후 트리거할 때까지 대기

## 사용자 트리거 패턴

- `/wp:stage9-orchestrate-monitor` — 1 회 폴링
- `/wp:stage9-orchestrate-monitor watch` — `ScheduleWakeup` 등록 (옵션, 사용자 명시 시만)
- `/wp:stage9-orchestrate-monitor stop` — 등록된 wakeup 취소

## Confirm Gate

Wave 완료 감지 시 다음 Wave dispatch 전 반드시 사용자 confirm. PLAN.md §5 #8 + IMPL.md Q3 (dogfood 단계) 정책.

## 실패 처리

- read-screen 권한 / pane 사라짐 → 해당 pane "lost" 표기 + 사용자에게 수동 확인 요청
- worker 가 자율 진행 중 정지 (idle 30 분+) → 사용자에게 push 알림 후 재개 요청
- PR 감지 false positive (URL 만 있고 실제 push 안 됨) → 다음 폴링에서 재검증

## Rules

1. 자동 폴링은 사용자 명시 트리거 시에만 (`watch` 인자)
2. 노이즈 필터링 강제 — 본문 무변화 폴링은 silent
3. Wave 자동 진행 금지 (v1) — 항상 사용자 confirm
4. PR-created 보고 시 diff 링크 + 1-2 줄 요약 의무
5. blocked / errored pane 발견 시 즉시 보고, 다음 폴링까지 미루지 않음
