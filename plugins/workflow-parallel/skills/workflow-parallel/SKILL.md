---
name: workflow-parallel
description: "9-stage parallel orchestration master skill. Trigger on: /workflow:parallel, parallel orchestrate, multi-ticket parallel, wave dispatch, parallel implementation. Drives plan-intake → plannotator → critic-verify → codebase-explore → DAG/Wave breakdown → Jira ticket create → git worktree setup → cmux pane dispatch → orchestrate-monitor by invoking each wp-stage<N>-* sub-skill in sequence with confirm gates."
---

# /workflow:parallel — 9-Stage Parallel Orchestration

> 사용자의 rough plan 또는 plan 파일을 받아 9 단계로 정제 / 검증 / 분할 / 병렬 dispatch / 모니터링하는 마스터 워크플로우. 각 stage 는 sub-skill 로 분리되어 partial restart 가능.
>
> 출처: `parallel-orchestrate-PLAN.md` §2 (stage 명세) / `parallel-orchestrate-IMPL.md` Build 5 (orchestrator 본체).

## 호출 방식

```
/workflow:parallel <plan-file-or-rough-idea>
```

인자가 path 면 plan 파일로, 아니면 inline rough idea 로 처리.

## 9 Stage 흐름

각 stage 는 **반드시 순차 invoke** 하고, stage 종료 시 사용자 confirm 후 다음 stage 진행. 사용자가 reject 시 해당 stage 만 재실행 / skip / 종료 중 선택.

### Stage 1 — plan-intake

```
Skill(skill="wp-stage1-plan-intake", args=<user input>)
```

PLAN.md §2 Stage 1 발췌:
> 입력에서 ambiguity / unknown 후보 추출 → `clarify-vague` + `clarify-unknown` + `AskUserQuestion` inline 호출 → 답변 반영 → plan rev N 산출. **종료 조건**: 사용자 "OK plan rev N".

산출: `<repo>/docs/plans/<feature>.md`

### Stage 2 — plannotator-loop

```
Skill(skill="wp-stage2-plannotator-loop")
```

PLAN.md §2 Stage 2 발췌:
> `plannotator-annotate` skill 호출 (UI 띄움) → 사용자 annotate 받기 → 메인 세션이 반영. **3회 이상 반복 또는 사용자 종료 신호**까지 loop. 산출: plan rev N+k (annotated).

### Stage 3 — critic-verify

```
Skill(skill="wp-stage3-critic-verify")
```

Stage 2 annotated plan 을 OMC `critic` subagent 로 다관점 검증 (범위/분할, 의존/순서, 가정 위험, 미해결 질문 심각도, 테스트/완료 조건, 종합 등급).
검증 결과는 plan 파일 끝에 `## Critic 검토 (rev N+k)` 섹션으로 **report-only append** (자동 patch 금지). frontmatter `critic-verdict: pass|revise|block` 갱신.
사용자가 `proceed` / `retry` (Stage 2 재진입) / `stop` 중 선택.

### Stage 4 — codebase-explore (병렬)

```
Skill(skill="wp-stage4-codebase-explore")
```

PLAN.md §2 Stage 4 발췌:
> plan 의 작업 후보 K 개 각각에 대해 **Explore subagent 1개씩 병렬 dispatch**: 재사용 가능 패턴 / plan 가정 vs 실제 코드 차이점 / 회귀 위험 영역. 산출: `<repo>/docs/plans/explore/wp-explore-<task-slug>.md` + `INDEX.md`.

### Stage 5 — task-breakdown + DAG/Wave

```
Skill(skill="wp-stage5-task-breakdown")
```

PLAN.md §2 Stage 5 발췌:
> 작업 목록 ↔ 의존성 mapping → topological sort → Wave (level) 분할. 의존 그래프 ASCII / mermaid. 같은 Wave = 의존 없음 → 동시 실행 가능. 산출: TODO.md.

### Stage 6 — ticket-create (병렬)

```
Skill(skill="wp-stage6-ticket-create")
```

PLAN.md §2 Stage 6 발췌:
> 작업 K 개에 대해 `mcp__atlassian__createJiraIssue` 병렬 호출. 본문 = `templates/ticket-body.md` (배경 / 작업 범위 / 코드 관계 / 테스트 전략 / 완료 조건 / 의존 / 브랜치). 부모 epic 자동 link. 산출: Jira key ↔ 작업 매핑.

### Stage 7 — worktree-setup

```
Skill(skill="wp-stage7-worktree-setup")
```

PLAN.md §2 Stage 7 발췌:
> `git log` 분석 → branch naming convention 자동 추론 → `git fetch origin <main>` → Wave 1 크기만큼 sequential `git worktree add` → pnpm 모노레포 감지 시 sequential `pnpm install` → untracked 보정 (TODO.md / plan cp). 산출: N worktree + 브랜치 + node_modules.

### Stage 8 — dispatch

```
Skill(skill="wp-stage8-dispatch")
```

PLAN.md §2 Stage 8 발췌:
> cmux `list-panes` 로 가용 pane 검출 → 각 pane: `/exit` → `cd <worktree> && claude --dangerously-skip-permissions` → 표준 boot prompt send + Enter → read-screen 으로 작업 시작 확인. 산출: pane→ticket 매핑.

### Stage 9 — orchestrate-monitor

```
Skill(skill="wp-stage9-orchestrate-monitor")
```

PLAN.md §2 Stage 9 발췌:
> 메인 세션이 주기적 read-screen 폴링 (또는 ScheduleWakeup) → PR 생성 감지 → 사용자 보고 → Wave 완료 → 다음 Wave 자동 dispatch (또는 사용자 confirm). **노이즈 필터링** 강제.

## Confirm Gate (모든 stage 공통)

각 stage sub-skill 종료 직후 메인 SKILL 은 다음 형식으로 사용자에게 묻는다:

```
## Stage <N> (<name>) 완료

[산출 요약 1-3 줄]

다음 Stage <N+1> (<next-name>) 로 진행할까요?
- ✅ OK — 다음 stage 호출
- 🔁 retry — 같은 stage 재실행 (사용자 추가 입력 받기)
- ⏭ skip — 다음 stage 로 이동 (산출 불완전 risk 사용자 책임)
- 🛑 stop — 워크플로우 종료
```

`AskUserQuestion` 으로 4 옵션 제공.

## Partial Restart

사용자가 특정 stage 만 재실행하려면 sub-skill slash 직접 호출:

```
/wp:stage3-critic-verify   # critic 검증만 다시
/wp:stage6-ticket-create   # ticket 생성만 다시
/wp:stage8-dispatch         # dispatch 만 다시
```

메인 SKILL 을 거치지 않으므로 confirm gate 도 없음 (사용자가 흐름 통제).

## 산출물 위치

| Stage | 산출물 | 경로 |
|-------|--------|------|
| 1 | 정제된 plan | `<repo>/docs/plans/<feature>.md` |
| 2 | annotated plan | 동일 파일 (rev N+k) |
| 3 | critic 검토 섹션 + verdict | 동일 plan 파일 (`## Critic 검토` append) |
| 4 | explore dossier | `<repo>/docs/plans/explore/wp-explore-<task-slug>.md` (+ `INDEX.md`) |
| 5 | TODO.md | `<repo>/TODO.md` |
| 6 | Jira keys | inline 매핑 테이블 |
| 7 | worktree | `<repo>/../<repo>-<TICKET-KEY>/` |
| 8 | pane 매핑 | inline 매핑 테이블 |
| 9 | PR 링크 / Wave 상태 | inline 보고 |

## Stage 의존 그래프

```
Stage 1 (plan-intake)
   ↓
Stage 2 (plannotator-loop)  ← optional 3 round loop
   ↓
Stage 3 (critic-verify)     ← OMC critic subagent, report-only
   ↺ revise → Stage 2 재진입 (사용자 선택)
   ↓ proceed
Stage 4 (codebase-explore)  ← 병렬 (작업당 1 Explore)
   ↓
Stage 5 (task-breakdown)
   ↓
Stage 6 (ticket-create)     ← 병렬 (Jira API)
   ↓
Stage 7 (worktree-setup)    ← sequential (lockfile / pnpm store)
   ↓
Stage 8 (dispatch)          ← sequential (cmux state race 방지)
   ↓
Stage 9 (orchestrate-monitor)  ← on-demand polling
   ↺ Wave 2 → Stage 7 부터 다시
```

## 핵심 결정 (PLAN.md §5 / IMPL.md 반영)

- plugin slash: `/workflow:parallel` (메인) + `/wp:stage<N>-<name>` (sub)
- Stage 3 critic 결과: **report-only** (plan 본문 자동 patch 금지, 사용자 retry/proceed/stop 결정)
- Stage 6 ticket 본문 언어: **한국어**
- Stage 7 worktree 위치: `<repo>/../<repo>-<TICKET-KEY>/` (디스크상 형제)
- Stage 8 cmux pane 부족 시: **사용자 수동 split** (자동 split 금지)
- Stage 9 모니터링: **on-demand** (auto polling 금지, 사용자 명시 시만)
- Wave 자동 진행: **금지 (v1)** — 항상 사용자 confirm
- Jira project / 부모 epic: **사용자 입력** (Stage 1 에서 묻기)
- branch convention: **git log 자동 추론 + 사용자 confirm**

## Rules

1. stage 순서 절대 변경 금지 (의존 깨짐)
2. 각 stage 종료 시 confirm gate 우회 금지 (사용자 명시 "skip-confirm" 인자 시만 예외)
3. sub-skill 미존재 stage 만나면 즉시 정지 + 사용자에게 미구현 보고 (Build 단계 진행도에 따라 일부 sub-skill 미구현 가능)
4. 모든 stage 산출물은 **파일로 영구 저장** (인라인 conversation memory 만으로는 partial restart 불가)
5. Wave 2+ 진행은 Wave 1 의 모든 PR 머지 후로 미루는 것을 default 권장
