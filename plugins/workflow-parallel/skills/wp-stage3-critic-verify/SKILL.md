---
name: wp-stage3-critic-verify
description: "Stage 3 of workflow-parallel — critic verification. Trigger on: /wp:stage3-critic-verify, critic verify, plan 검증, plan critic, 비평 검토, work plan review. Stage 2 의 annotated plan 을 OMC critic subagent 로 다관점 검증. 결과를 plan 파일의 `## Critic 검토` 섹션에 report-only 로 append 하고 사용자에게 retry / proceed / stop 선택을 요청. plan 본문 자동 patch 금지."
---

# Stage 3 — Critic Verify

> Stage 2 plannotator-loop 가 산출한 plan rev 를 OMC `critic` subagent 로 다관점 검증. 검증 결과는 plan 본문에 **report-only** 로 append (자동 patch 금지). 사용자가 retry / proceed / stop 결정.
>
> 출처: `oh-my-claudecode` `critic` agent 명세 — "Work plan and code review expert — thorough, structured, multi-perspective (Opus)".

이 skill은 `workflow-parallel` plugin의 9-stage 흐름 중 3단계입니다. 이전 단계: `/wp:stage2-plannotator-loop`. 다음 단계: `/wp:stage4-codebase-explore`.

## 입력

- Stage 2 의 annotated plan 파일 (frontmatter `rev: N+k`, `## 작업 목록` / `## 가정 / 결정 사항` / `## 미해결 질문` 포함)
- 대상 repo 경로 (frontmatter 또는 사용자 입력)

## 산출물

- plan 파일에 `## Critic 검토 (rev {{N+k}})` 섹션 append — critic 보고 본문 + 권고 등급
- frontmatter 의 `critic-verdict: pass | revise | block` 추가 (사용자가 retry/proceed/stop 결정에 활용)
- 사용자 결정에 따른 분기:
  - **proceed** → Stage 4 (`/wp:stage4-codebase-explore`) 로 자연 진행
  - **retry** → Stage 2 (`/wp:stage2-plannotator-loop`) 재호출 (critic 지적 사항 반영)
  - **stop** → 워크플로우 종료

## 실행 흐름

### Step 1 — Plan 로드 + 사전 검증

`Read` 로 plan 파일 본문 + frontmatter `rev` 확인.

- `rev: 1` (Stage 2 미수행) → 사용자에게 `/wp:stage2-plannotator-loop` 먼저 진행 안내 후 정지
- `## 작업 목록` 섹션 없음 → 검증 불가, 사용자에게 보고 후 정지

### Step 2 — Critic subagent dispatch

`Agent` tool, `subagent_type="oh-my-claudecode:critic"`, `model="opus"` (critic 기본).

전달 prompt 표준 형식 (self-contained, plan 본문을 직접 인용):

````
당신은 workflow-parallel 워크플로우의 Stage 3 검증 단계입니다. 다음 plan rev 를 다관점으로 비평해 주세요.

대상 repo: {{repo-path}}
plan 파일: {{plan-path}} (rev {{N+k}})

--- plan 본문 시작 ---
{{plan 본문 전체 인용}}
--- plan 본문 끝 ---

다음 관점으로 평가하고 marker '<<<CRITIC>>>' 뒤에 markdown 으로 보고:

1. **범위 / 분할 적절성**
   - 작업 단위가 너무 크거나 작은 항목
   - 하나의 ticket 으로 묶기 어려운 작업이 같이 묶여 있는지
   - 누락된 작업 (테스트, 문서, 마이그레이션, 롤백 등)

2. **의존 / 순서**
   - 작업 사이 숨겨진 의존성
   - Wave 분할이 비현실적인 부분 (Stage 5 task-breakdown 사전 점검)

3. **가정 / 결정 사항의 위험**
   - 검증되지 않은 가정 — Stage 4 codebase-explore 전에 깨질 위험
   - 결정 사항이 plan 의 다른 섹션과 모순되는지

4. **미해결 질문의 심각도**
   - blocking decision 인데 미해결로 남은 항목
   - Stage 4 / 5 에서 자연 해소 가능 vs 사용자 결정 필요

5. **테스트 / 완료 조건**
   - 작업별 완료 조건이 측정 가능한가
   - 회귀 위험 영역에 대한 테스트 전략이 있는가

6. **종합 등급**
   - `pass` — 그대로 Stage 4 진행 가능
   - `revise` — Stage 2 로 돌아가 일부 보강 필요 (구체적 보강 항목 나열)
   - `block` — 근본적 재설계 필요 (이유 설명)

700~1200 단어, 마크다운 형식. 코드 인용은 불필요 — plan 본문만 평가. 한국어로 작성.
````

`description="Critic verify plan rev {{N+k}}"`.

### Step 3 — Critic 응답 파싱

subagent 응답에서 `<<<CRITIC>>>` 뒤 본문을 추출. 본문 끝의 "종합 등급" 항목에서 `pass` / `revise` / `block` 키워드를 단일 토큰으로 식별.

키워드 식별 실패 시 (모호한 응답): `revise` 로 안전하게 fallback + 사용자에게 fallback 사실 보고.

### Step 4 — Plan 에 report-only append

`Edit` 으로 plan 본문 끝에 다음 섹션을 추가 (기존 섹션 수정 금지):

```markdown
## Critic 검토 (rev {{N+k}})

> 검토 일시: {{YYYY-MM-DD HH:MM}}
> 종합 등급: **{{pass | revise | block}}**

{{Step 3 에서 추출한 critic 본문}}
```

이미 `## Critic 검토 (rev {{N+k}})` 섹션이 존재 (재실행) 하면 이전 본문을 그대로 두고 **새 섹션을 append** (히스토리 보존). 헤더에 round 번호를 추가:

```markdown
## Critic 검토 (rev {{N+k}}, round 2)
```

frontmatter 에 `critic-verdict: {{pass|revise|block}}` 추가 / 갱신.

### Step 5 — 사용자 결정 (AskUserQuestion)

critic 등급에 따른 권장 분기를 첫 옵션으로 제시:

- `pass` → 첫 옵션: **proceed** (Stage 4 진행)
- `revise` → 첫 옵션: **retry** (Stage 2 재호출, critic 지적 반영)
- `block` → 첫 옵션: **stop** (워크플로우 종료) — 단, 사용자가 무시하고 proceed 선택 가능

`AskUserQuestion` 호출 (3 옵션):

```
question: "Critic 검토 등급: {{verdict}}. 어떻게 진행할까요?"
options:
  - label: "{{권장-옵션-label}} (Recommended)"
    description: "{{verdict 별 권장 설명}}"
  - label: "{{다른-옵션-1}}"
    description: "..."
  - label: "{{다른-옵션-2}}"
    description: "..."
```

옵션 매핑:

- **proceed**: "Stage 4 (codebase-explore) 로 진행. critic 지적은 plan 본문에만 기록되고 별도 반영 없음."
- **retry**: "Stage 2 (plannotator-loop) 로 돌아가 사용자가 critic 지적을 보고 직접 annotate. rev 증가 후 Stage 3 재진입 가능."
- **stop**: "워크플로우 종료. plan 파일은 현재 상태로 보존."

### Step 6 — 분기 실행

사용자 응답에 따라:

- **proceed** → 다음 메시지에서 메인 SKILL 이 `/wp:stage4-codebase-explore` 자연 호출
- **retry** → 다음 메시지에서 메인 SKILL 이 `/wp:stage2-plannotator-loop` 자연 호출 (사용자에게 "critic 지적 보강 후 다시 Stage 3 진행 권장" 안내 동반)
- **stop** → 종료 보고:

  ```
  Stage 3 critic-verify 종료 — 사용자 stop 선택
  - plan 파일: {{path}} (rev {{N+k}}, critic-verdict: {{verdict}})
  - critic 보고 보존됨

  재진입: /wp:stage3-critic-verify
  처음부터: /workflow:parallel {{plan-path}}
  ```

## Rules

1. **report-only 강제** — critic 보고를 받아 plan 본문 (`## 작업 목록` / `## 가정 / 결정 사항` 등) 을 자동 수정 금지. append 만 허용.
2. critic subagent 는 항상 opus 모델 (정확도 우선, 검증 단계 1 회만 호출).
3. `<<<CRITIC>>>` marker 누락 시 fallback: 응답 전체를 본문으로 간주하되 사용자에게 marker 누락 사실 보고.
4. 종합 등급이 `block` 이어도 사용자 proceed 선택은 허용 — 단, plan 본문에 critic-verdict 가 그대로 남으므로 추후 추적 가능.
5. 재실행 시 이전 critic 보고 보존 — 새 round 로 append 만 추가 (rev 동일하면 round 번호로 구분).
6. critic 보고 본문은 한국어로 받기 (메인 워크플로우 톤 유지).
7. critic subagent 가 실패 / 응답 없음 → 사용자에게 보고 후 retry / skip 선택 요청 (자동 skip 금지).
8. Stage 4 자동 진행 금지 — Step 5 사용자 confirm 통과 후에만.

## 사용자 트리거 패턴

- `/wp:stage3-critic-verify` — 현재 plan 에 대해 1 회 검증
- `/wp:stage3-critic-verify <plan-path>` — 특정 plan 파일 지정 검증
- 메인 워크플로우 흐름 (`/workflow:parallel`) 에서는 Stage 2 종료 후 자동 호출

## 산출물 예시

plan 파일 끝에 추가되는 섹션:

```markdown
## Critic 검토 (rev 4)

> 검토 일시: 2026-05-11 14:30
> 종합 등급: **revise**

### 1. 범위 / 분할 적절성

작업 3 "API 인증 + 권한 통합" 은 두 개의 다른 관심사 (인증 / 권한) 가 묶여 있어 ticket 1 개로 처리하기에 과도합니다...

### 2. 의존 / 순서

작업 5 (마이그레이션) 가 작업 2 (스키마 변경) 이전에 실행되면 충돌 가능...

...

### 6. 종합 등급

`revise` — 작업 3 분할 + 작업 5 ↔ 2 순서 명시 후 재진입 권장.
```
