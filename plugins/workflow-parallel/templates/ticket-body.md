## 배경

{{plan §X 발췌 + 작업 동기 1-2 문단}}

## 작업 범위

- 신규 파일: {{목록}}
- 변경 파일: {{목록 + 변경 영역}}
- 삭제 파일: {{목록 (있을 때)}}

## 기존 코드베이스와의 관계

- **재사용**: {{explorer 결과의 재사용 가능 패턴 — 파일 경로 + 한 줄 설명}}
- **충돌 가능 영역**: {{병렬 진행 시 다른 ticket 과 겹칠 가능성}}
- **회귀 위험**: {{core / shared utility 등 영향 범위}}

## 테스트 전략

- **CDC (Code-Driven Coverage)**: {{핵심 분기 + 정상/예외 경로}}
- **DU path**: {{definition-use chain 의 critical 경로}}
- **BVA (Boundary Value Analysis)**: {{경계값 — empty / max / off-by-one}}
- **Edge pair**: {{2-입력 조합 직교 페어}}
- **단위 vs 통합**: {{비중 + rationale}}

## 완료 조건

- [ ] {{기능 AC 1}}
- [ ] {{기능 AC 2}}
- [ ] `pnpm build && pnpm test` 통과
- [ ] PR 생성 + CI 통과

## 의존

- 선행: {{ticket keys, 없으면 "없음 (Wave N)"}}
- 후속: {{ticket keys}}

## 브랜치 / 워크트리

- 브랜치: `{{TICKET-KEY}}-{{slug}}`
- 워크트리: `~/Desktop/{{repo}}-{{TICKET-KEY}}/`

## 참조

- plan: `{{repo}}/docs/plans/{{feature}}.md` §{{section}}
- TODO: `{{repo}}/TODO.md` §{{section}}
