---
name: wp-stage6-ticket-create
description: "workflow-parallel Stage 6. Jira 티켓 병렬 생성. Trigger on: /wp:stage6-ticket-create, jira ticket 만들기, 병렬 티켓 생성. Stage 5 의 task 목록을 받아 mcp__atlassian__createJiraIssue 를 병렬 호출. 본문은 templates/ticket-body.md 표준. 부모 epic 자동 link."
---

# Stage 6 — Jira Ticket 병렬 생성

`workflow-parallel` 9-stage 흐름의 6번째 단계. Stage 5 의 task 목록을 받아 Jira 티켓을 병렬 생성하고 Stage 7 worktree 구성에 필요한 ticket key ↔ task 매핑 테이블을 산출.

## 입력

- Stage 5 산출물의 task 목록 (title + scope + 의존 + 테스트 전략 후보)
- 부모 Epic key (Stage 1 에서 사용자에게 수집한 값)
- Jira project key (사용자 입력 or 메인 세션 컨텍스트)
- Jira cloudId (mcp__atlassian 의 search 또는 사용자 명시)

## 실행 순서

### Step 1 — 사전 검증

- atlassian MCP 가 인증되어 있는지 `mcp__atlassian__authenticate` 또는 dry call 로 확인
- 부모 Epic 이 실제 존재하는지 `mcp__atlassian__getJiraIssue` 로 검증
- project key + cloudId 가 올바른지 사용자 confirm

### Step 2 — 본문 템플릿 채우기

각 task 에 대해 `templates/ticket-body.md` 의 placeholder 를 채움:

- 배경: plan §X 발췌 + 작업 동기
- 작업 범위: 신규/변경/삭제 파일 목록
- 기존 코드베이스와의 관계: explore dossier 의 재사용/충돌/회귀 항목
- 테스트 전략: CDC / DU path / BVA / Edge pair / 단위 vs 통합
- 완료 조건: AC 체크리스트 + `pnpm build && pnpm test` + PR + CI
- 의존: 선행/후속 ticket key (Wave 정보 기반, 같은 Wave 는 "없음 (Wave N)")
- 브랜치 / 워크트리: `{TICKET-KEY}-<slug>` / `~/Desktop/<repo>-{TICKET-KEY}/`
- 참조: plan path + TODO.md section

### Step 3 — 병렬 createJiraIssue 호출

task 가 K 개라면 **K 개의 `mcp__atlassian__createJiraIssue` 도구 호출을 한 메시지에 묶어 병렬 실행**.

각 호출 파라미터:

- `cloudId`: 검증된 cloudId
- `projectKey`: 사용자 입력 project key
- `issueTypeName`: "Task" (기본) 또는 사용자 지정
- `summary`: task title
- `description`: Step 2 에서 채운 본문 (ADF 또는 markdown — atlassian MCP 시그니처에 맞춤)
- `additional_fields`: 부모 Epic link (`customfield_xxxx` 또는 `parent: { key: <EPIC> }` — Jira 사이트에 따라 다름)

### Step 4 — 매핑 테이블 산출

호출 결과를 모아 다음 테이블을 출력:

| Plan # | Task Title | Jira Key | Wave | 의존 |
|---|---|---|---|---|
| 1 | ... | MCP-1234 | 1 | 없음 |

이 테이블은 Stage 5 산출 TODO.md 의 §2 "실제 Jira 티켓 매핑" 섹션에 반영. `Edit` 으로 placeholder 를 실제 값으로 치환.

### Step 5 — 부모 Epic 보정

Step 3 에서 epic link 가 누락된 ticket 이 있으면 `mcp__atlassian__editJiraIssue` 로 보정. 일부 Jira 사이트는 create 시점에 parent link 가 안 박힘.

### Step 6 — 사용자 보고

- 생성된 ticket 수
- 부모 Epic 에 모두 link 되었는지 확인 결과
- 다음 단계(Stage 7 — worktree setup)로 진행할지 confirm

## 종료 조건

- 모든 task 에 대응되는 Jira ticket 이 생성됨
- 부모 Epic 에 link 됨
- TODO.md §2 가 실제 ticket key 로 갱신됨
- 매핑 테이블이 Stage 7 입력으로 사용 가능

## Rules

1. createJiraIssue 호출은 반드시 한 메시지에 병렬로 묶어 호출 (sequential 호출 금지 — 시간 낭비)
2. 본문은 한국어 (이번 세션 톤 유지)
3. 실패한 ticket 은 즉시 사용자에게 보고. 재시도 여부 확인
4. ticket key 를 추측하거나 임의 생성 금지 — 반드시 createJiraIssue 응답값 사용
5. project key / cloudId / Epic key 가 명확하지 않으면 `AskUserQuestion` 으로 묻기
