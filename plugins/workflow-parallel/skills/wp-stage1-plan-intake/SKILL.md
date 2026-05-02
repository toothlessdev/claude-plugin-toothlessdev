---
name: wp-stage1-plan-intake
description: "Stage 1 of workflow-parallel — plan intake & clarify. Trigger on: /wp:stage1-plan-intake, plan intake, 플랜 인테이크, clarify plan, 플랜 정제, refine plan, intake rough idea. Takes a rough plan / file path / inline idea, extracts ambiguity and unknowns via clarify-vague + clarify-unknown + AskUserQuestion, and produces a refined plan markdown file (rev N)."
---

# Stage 1 — Plan Intake

Refine a rough plan / file path / inline idea into a structured plan markdown file ready for Stage 2 (plannotator-loop).

이 skill은 `workflow-parallel` plugin의 8-stage 흐름 중 1단계입니다. 이전 단계: 없음. 다음 단계: `/wp:stage2-plannotator-loop`.

## 입력

다음 중 하나:

- 거친 plan 텍스트 (인라인)
- plan 파일 path (예: `~/Desktop/<feature>-PLAN.md`)
- 한 문장 idea ("X 기능을 N개 ticket 으로 쪼개고 싶어")

## 산출물

- 정제된 plan markdown: `<repo>/docs/plans/{{feature-slug}}.md` (또는 사용자 지정 위치)
- frontmatter에 `rev: N`, `parent-epic: {{EPIC-KEY}}` (사용자 입력) 기록
- 종료 조건: 사용자가 명시적으로 "OK plan rev N" 응답

## 실행 흐름

### Step 1 — 입력 수집

사용자 입력에서 다음을 식별:

- plan 출처 (인라인 / 파일 / 즉흥)
- feature 이름 (slug 화 후보)
- 부모 Jira epic key (없으면 Stage 1 끝에서 묻기 — `AskUserQuestion`)
- 대상 repo 경로 (현재 working directory 기본)

파일이면 `Read` 로 본문 로드. 인라인이면 그대로.

### Step 2 — Ambiguity 추출 (`clarify-vague`)

`clarify-vague` skill 을 inline 호출 (Skill tool):

```
Skill(skill="clarify-vague", args="{{plan 본문 또는 path}}")
```

- 모호한 요구사항 / 정의되지 않은 용어 / 측정 기준 부재 항목 추출
- 출력 = "vague items" 리스트 (각 항목당 question 후보 포함)

### Step 3 — Unknown 발굴 (`clarify-unknown`)

`clarify-unknown` skill 을 inline 호출:

```
Skill(skill="clarify-unknown", args="{{plan 본문}}")
```

- Known/Unknown 4분면 분석 → 의사결정 분기점 / 숨겨진 가정 발견
- 출력 = "unknown items" 리스트

### Step 4 — 멀티선택 질문 (`AskUserQuestion`)

Step 2/3 결과를 종합하여 질문 묶음 작성:

- 한 번에 최대 5개 질문
- 각 질문당 3~4개 선택지 + "기타 (직접 입력)"
- 우선순위: blocking decision > scope > convention

`AskUserQuestion` tool 호출 → 사용자 응답 수집.

추가로 다음 항목은 항상 Stage 1 에서 확정:

- 부모 Jira epic key
- branch naming convention (자동 추론 + confirm)
- worktree 위치 (디폴트: `<repo>/../<repo>-{{TICKET-KEY}}/`)

### Step 5 — Plan rev N 생성

응답을 plan 본문에 반영하여 markdown 파일 작성:

- 경로: `<repo>/docs/plans/{{feature-slug}}.md` (디렉토리 없으면 생성)
- frontmatter:
  ```yaml
  ---
  feature: { { feature-name } }
  rev: 1
  parent-epic: { { EPIC-KEY } }
  branch-prefix: { { PREFIX } }
  worktree-base: { { path } }
  created: { { YYYY-MM-DD } }
  ---
  ```
- 본문 구조 (최소):
  - `## 배경` — 작업 동기 1-2 문단
  - `## 작업 목록` — 후보 K개 (번호 + 한 줄 설명)
  - `## 가정 / 결정 사항` — Step 4 응답 요약
  - `## 미해결 질문` — 차후 plannotator 에서 다룰 항목

### Step 6 — Confirm

사용자에게 plan 파일 경로 + 핵심 항목 요약 표시:

```
plan rev 1 작성 완료 → {{path}}
- feature: {{name}}
- 작업 후보: {{K}}개
- 부모 epic: {{EPIC-KEY}}
- branch prefix: {{PREFIX}}

다음 단계 진행하려면 "OK plan rev 1" 또는 "/wp:stage2-plannotator-loop"
수정 필요하면 그 항목 알려줘.
```

사용자 "OK" → Stage 2 로 자연 진행.
사용자 수정 요청 → Step 4 부터 반복 (rev N+1 산출).

## Rules

1. plan 파일은 항상 markdown + frontmatter (rev 추적 필수)
2. `clarify-vague` 와 `clarify-unknown` 은 항상 둘 다 호출 (한 쪽만 호출 금지 — 청사진 §5 항목 2 결정)
3. `AskUserQuestion` 는 한 번에 최대 5개 질문 — 초과 시 우선순위순으로 분할 호출
4. 부모 epic key 는 Stage 1 에서 반드시 확정 (Stage 5 ticket-create 에서 link 하려면 필수)
5. 모든 사용자 대화는 한국어 (청사진 §5 항목 5 결정)
6. plan 파일이 이미 존재하면 덮어쓰기 금지 — rev 번호 증가시켜 새 파일 또는 사용자 confirm
