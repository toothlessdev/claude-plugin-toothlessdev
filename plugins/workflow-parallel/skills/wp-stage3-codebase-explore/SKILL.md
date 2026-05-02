---
name: wp-stage3-codebase-explore
description: "Stage 3 of workflow-parallel — parallel codebase exploration. Trigger on: /wp:stage3-codebase-explore, codebase explore, 코드베이스 탐색, parallel explore, plan vs code, dispatch explore agents. Dispatches K Explore subagents in parallel — one per task candidate from the plan — to extract reusable patterns, plan-vs-actual diffs, and regression risk areas. Produces per-task analysis dossiers."
---

# Stage 3 — Codebase Explore (병렬)

Stage 2 에서 확정된 plan 의 작업 후보 K 개에 대해, **각 작업당 1개씩 Explore subagent 병렬 dispatch** → 코드베이스 분석 dossier 산출. 메인 컨텍스트 보호 + 작업별 정밀 분석.

이 skill은 `workflow-parallel` plugin의 8-stage 흐름 중 3단계입니다. 이전 단계: `/wp:stage2-plannotator-loop`. 다음 단계: `/wp:stage4-task-breakdown`.

## 입력

- Stage 2 의 plan 파일 (frontmatter `rev: N+k`, `## 작업 목록` 섹션에 K 개 후보)
- 대상 repo 경로 (frontmatter 또는 사용자 입력)

## 산출물

- 작업당 1개 dossier: `<repo>/docs/plans/explore/wp-explore-{{task-slug}}.md`
- 각 dossier 의 표준 구조:
  - `## 재사용 가능 패턴` — 기존 service / hook / component / utility (파일 경로 + 한 줄 설명)
  - `## 계획 vs 실제` — plan 가정 ↔ 실제 코드 차이 (table)
  - `## 회귀 위험 영역` — core / shared utility / 광범위 import 영향
  - `## 충돌 가능 영역` — 다른 작업과 같은 파일/모듈 건드릴 가능성
- index 파일: `<repo>/docs/plans/explore/INDEX.md` (전체 dossier 링크 + 작업↔파일 매트릭스)

## 실행 흐름

### Step 1 — 작업 후보 추출

`Read` 로 plan 본문 → `## 작업 목록` 파싱:
```
1. {{task-name-1}} — {{한 줄 설명}}
2. {{task-name-2}} — ...
...
K. {{task-name-K}} — ...
```

각 작업 항목을 `{slug, title, description}` 으로 정규화. slug 는 kebab-case.

### Step 2 — Explore subagent 병렬 dispatch

K 개 Explore subagent 를 **단일 메시지의 multiple tool calls 로 병렬 호출** (청사진 §5 항목 4 결정 — 작업당 1 subagent).

각 agent 에 전달할 prompt 표준 형식:
```
대상 repo: {{repo-path}}
plan 파일: {{plan-path}} ({{rev}})
이 작업: {{task-title}} — {{description}}

다음을 조사하여 marker '<<<DOSSIER>>>' 뒤에 markdown 으로 보고:

1. **재사용 가능 패턴**
   - 이 작업의 의도를 이미 부분 구현한 service / hook / component / utility
   - 각 항목: 파일 경로 + 한 줄 설명 (왜 재사용 가능한지)

2. **계획 vs 실제**
   - plan 본문이 가정한 모듈 / 함수 / 데이터 흐름 ↔ 실제 코드의 차이
   - table: | plan 가정 | 실제 | 갭 |

3. **회귀 위험 영역**
   - 이 작업이 변경할 가능성 있는 파일이 다른 모듈에서 import 되는 범위
   - core / shared utility / public API 표면

4. **충돌 가능 영역**
   - 이 작업과 다른 작업 (목록: {{other-tasks}}) 가 같은 파일을 동시에 건드릴 가능성

200~400 단어, 마크다운 형식. 코드 발췌는 핵심만 (파일 경로 + 라인 번호 우선).
```

`Agent` tool, `subagent_type="Explore"`, `description="Explore: {{task-title}}"`.

### Step 3 — Dossier 파일 생성

각 subagent 응답에서 `<<<DOSSIER>>>` 뒤 본문 추출 → 파일로 저장:
```
<repo>/docs/plans/explore/wp-explore-{{task-slug}}.md
```

frontmatter:
```yaml
---
task: {{task-title}}
slug: {{task-slug}}
plan-rev: {{N+k}}
created: {{YYYY-MM-DD}}
---
```

`Write` tool. 디렉토리 없으면 `Bash` 로 mkdir 선행.

### Step 4 — INDEX 생성

`<repo>/docs/plans/explore/INDEX.md` 작성:
```markdown
# Codebase Explore Index — {{feature}}

> plan: {{plan-path}} ({{rev}})
> 생성: {{YYYY-MM-DD}}

## Dossier 목록

| # | 작업 | 파일 |
|---|------|------|
| 1 | {{task-1-title}} | [wp-explore-{{slug-1}}.md](wp-explore-{{slug-1}}.md) |
| ... | ... | ... |

## 작업 ↔ 파일 매트릭스

(각 dossier 의 "재사용 패턴" + "회귀 위험" 의 파일 경로를 합산하여 작업별 영향 파일 매트릭스)

| 파일 | T1 | T2 | ... | TK |
|------|----|----|-----|----|
| ...  | ✓  |    | ... | ✓  |

→ 같은 행에 ✓가 2개 이상이면 Stage 4 의 의존 그래프 후보.

## 회귀 위험 hotspot

- {{file-path}} : {{영향받는 작업 수}} 작업
- ...
```

### Step 5 — 사용자 보고

```
Stage 3 완료 — {{K}}개 dossier 작성
- 위치: {{repo}}/docs/plans/explore/
- INDEX: {{repo}}/docs/plans/explore/INDEX.md
- 핵심 hotspot: {{top-3-files}}

다음 단계: /wp:stage4-task-breakdown
```

## Rules

1. **반드시 병렬 dispatch** — K 개 subagent 호출을 단일 응답의 multiple tool calls 로 (sequential 호출 금지, 청사진 §5 항목 4 결정)
2. 작업당 1 subagent — 그룹별 묶음 금지 (메인 컨텍스트 보호)
3. 각 dossier 는 200~400 단어 — 너무 길면 메인 세션이 Stage 4 에서 종합하기 어려움
4. dossier 의 파일 경로는 항상 repo root 기준 상대 경로 (절대 경로 금지 — diff 가능성)
5. INDEX 의 매트릭스는 Stage 4 의 DAG 작성 입력으로 활용 — 형식 일관성 유지
6. 한국어로 작성
