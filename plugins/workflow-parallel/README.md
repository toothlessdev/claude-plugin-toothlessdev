# workflow-parallel

> 9-stage interactive workflow plugin for parallel multi-ticket execution.

`/workflow:parallel <plan-file-or-rough-idea>` 한 번의 진입으로 plan 정제 → annotator 검토 → critic 검증 → codebase 탐색 → DAG/Wave 분할 → Jira ticket 생성 → git worktree 분기 → cmux pane 병렬 dispatch → 진행 모니터링까지 자동화.

## 9 Stage 흐름

| Stage | Slash                            | 역할                                                       |
| ----- | -------------------------------- | ---------------------------------------------------------- |
| 1     | `/wp:stage1-plan-intake`         | rough plan → clarify-vague + clarify-unknown 으로 정제     |
| 2     | `/wp:stage2-plannotator-loop`    | plannotator-annotate 반복 검토                             |
| 3     | `/wp:stage3-critic-verify`       | OMC critic subagent 다관점 검증 → plan 에 report-only      |
| 4     | `/wp:stage4-codebase-explore`    | 작업별 Explore subagent 병렬 dispatch                      |
| 5     | `/wp:stage5-task-breakdown`      | 의존 그래프 → Wave 분할                                    |
| 6     | `/wp:stage6-ticket-create`       | Jira ticket 병렬 생성 (표준 템플릿)                        |
| 7     | `/wp:stage7-worktree-setup`      | N 개 git worktree + 의존 설치                              |
| 8     | `/wp:stage8-dispatch`            | cmux pane 분할 + claude restart + boot prompt 주입         |
| 9     | `/wp:stage9-orchestrate-monitor` | on-demand 진행 모니터링 + Wave 진행                        |

## 설치

```bash
claude plugin install ./plugins/workflow-parallel
```

## 사용

```
/workflow:parallel <plan-file>
```

또는 특정 stage 부터 재시작:

```
/wp:stage7-worktree-setup
```

## 의존

- `cmux` CLI (Mac App)
- `git` 2.x+ (worktree)
- `gh` CLI (PR 생성)
- Atlassian MCP (`mcp__atlassian__*` — Jira ticket 생성)
- `plannotator-annotate` skill (rev2 검토 루프)

## 상태

v0.1.0 — MVP 단계 (Build 1~6). 실험적.
