---
name: wp-stage2-plannotator-loop
description: "Stage 2 of workflow-parallel — plannotator annotation loop. Trigger on: /wp:stage2-plannotator-loop, plannotator loop, plan annotate, 플랜 어노테이트, annotate plan, plan rev. Opens plannotator-annotate UI on the Stage 1 plan, ingests user annotations, applies them to the plan, and repeats for at least 3 rounds (or until user signals exit). Produces plan rev N+k."
---

# Stage 2 — Plannotator Loop

Iteratively annotate the Stage 1 plan via the `plannotator-annotate` skill. 사용자가 plan markdown 위에 직접 의견 / 결정 / 보강 사항을 적으면, 메인 세션이 plan 본문에 반영하고 rev 번호를 올림.

이 skill은 `workflow-parallel` plugin의 9-stage 흐름 중 2단계입니다. 이전 단계: `/wp:stage1-plan-intake`. 다음 단계: `/wp:stage3-critic-verify`.

## 입력

- Stage 1 의 plan 파일 path (frontmatter `rev: N` 포함)
- 권장 반복 횟수 (디폴트 3회)
- 최대 반복 횟수 (디폴트 5회 — 무한 루프 방지)

## 산출물

- plan 파일 동일 경로, frontmatter `rev: N+k` 로 업데이트
- 각 round 의 변경 요약은 `## 변경 이력` 섹션에 누적
- 종료: round k 의 사용자 응답 = "끝" / "exit" / "다음 단계" / "OK"

## 실행 흐름

### Step 1 — Plan 로드

`Read` 로 plan 파일 본문 + frontmatter rev 확인. rev 가 1 미만이면 Stage 1 미완료 → 사용자에게 `/wp:stage1-plan-intake` 먼저 진행 안내.

### Step 2 — Round 시작

각 round 진입 전 사용자에게 안내:
```
Round {{k}}/{{max}}: plannotator UI 띄웁니다.
plan rev {{N+k-1}} 위에 자유롭게 annotation 추가 → UI 닫으면 메인 세션이 반영합니다.
("끝" 입력하면 즉시 종료)
```

### Step 3 — Plannotator 호출

`plannotator-annotate` skill invoke (Skill tool):
```
Skill(skill="plannotator-annotate", args="{{plan-path}}")
```

Plannotator 가 UI 를 띄우고 annotation 결과 반환 (annotation 리스트 또는 수정된 markdown).

### Step 4 — Annotation 반영

Plannotator 반환값을 plan 본문에 반영:
- 새 결정 사항 → `## 가정 / 결정 사항` 추가
- 미해결 질문 해소 → `## 미해결 질문` 에서 제거 + `## 결정 사항` 으로 이동
- 작업 후보 변경 → `## 작업 목록` 갱신
- 새 미해결 질문 → `## 미해결 질문` 추가

frontmatter `rev` 를 N+k 로 갱신.

`## 변경 이력` 섹션 (없으면 신설):
```markdown
## 변경 이력

- rev {{N+k}} ({{YYYY-MM-DD}}): {{변경 요약 1줄}}
```

`Edit` tool 로 plan 파일 업데이트.

### Step 5 — Round 종료 / 다음 round 결정

사용자에게 변경 요약 + 다음 round 진행 여부 확인:
```
Round {{k}} 완료 → plan rev {{N+k}}
변경: {{요약}}

다음 round 진행 ("계속" / "round 더") / 종료 ("끝" / "다음 단계")
권장: 최소 3회, 최대 5회.
```

- "계속" → Step 2 로 (k+1)
- "끝" / "다음 단계" → Step 6
- round k 가 max 도달 → 강제 종료 (Step 6)

### Step 6 — Stage 종료

최종 plan 정보 요약:
```
plannotator-loop 완료 → plan rev {{N+k}}
- 총 round: {{k}}
- 미해결 질문: {{count}}개 (Stage 3 critic-verify 에서 점검 후 Stage 4 explore / Stage 5 task-breakdown 에서 해소)

다음 단계: /wp:stage3-critic-verify
```

## Rules

1. plannotator-annotate skill 의 입출력 인터페이스가 미확정이면 (IMPL.md R2) skill 파일을 직접 읽어 검증한 뒤 진행
2. round 마다 plan 파일을 즉시 저장 (중간 종료 시 손실 방지)
3. rev 번호는 round 단위로 증가 (annotation 변경 없는 round 도 rev 증가 — trace 가능성)
4. 최대 round (디폴트 5) 도달 시 강제 종료 — 무한 루프 방지
5. 모든 대화는 한국어
6. plannotator UI 가 실패하면 사용자에게 수동 annotation 입력 요청으로 fallback
