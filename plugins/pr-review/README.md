# pr-review

PR 을 "읽고 의견을 말하는" 리뷰가 아니라, **티켓이 요구한 동작을 실제로 실행해 확인하는** 리뷰.

정적으로 코드를 훑는 리뷰는 "이럴 것 같다" 에서 멈춘다. 이 플러그인은 격리된 git worktree 에서
테스트를 실제로 돌려서 **재현되는 실패**만 결함으로 보고한다. 재현 못 했으면 못 했다고 쓴다.

```bash
/pr-review 1234
/pr-review https://github.com/owner/repo/pull/1234
/pr-review 1234 --quick     # 스펙 대조 + 영향 범위만, 테스트 실행 없음
```

## 파이프라인

```
1.   PR 수집          gh pr view/diff · Jira 키 추출 · 대상 저장소 CLAUDE.md → house-rules
1.5  MCP 선수집       ★오케스트레이터가★ Jira·Confluence·get_dependents·LSP → raw/
2.   ⟨병렬⟩ spec-collector      → spec.md    검증 가능한 AC + 확신도
            blast-radius-mapper → impact.md  변경 심볼 → T0~T3
3.   test-strategist  → strategy.md    블랙박스 케이스 (각 케이스에 근거 링크)
4.   test-executor    → results.jsonl  격리 worktree 에서 러너 부트스트랩 후 실제 실행
5.   finding-verifier → findings/      실패 1건당 독립 에이전트 1개, 4값 판정
6.   report.md + 터미널 요약
```

아티팩트는 대상 저장소 **밖** `~/.claude/pr-review/<owner>__<repo>/<PR#>/` 에 파일로 쌓인다.

## dry run 이 전제다

작성된 테스트는 대상 저장소에 커밋되지 않는다. `scripts/teardown-worktree.sh` 가 매 실행 후
네 가지를 검증한다.

- 임시 워크트리 잔여 없음
- `git status` 가 실행 전과 동일
- `package.json` · lockfile 무변경
- 테스트 산출물 유출 없음

하나라도 어긋나면 **리포트보다 먼저** 사용자에게 알린다.

## 무엇이 다른가

**Jira 스펙 주입.** PR 본문은 구현자가 구현 후에 쓴 것이라 구현과 일치할 수밖에 없다.
작성자의 설명으로 작성자의 구현을 검증하는 건 순환이다. 티켓이 그 순환을 끊는다 —
특히 티켓이 "미결정" 이라고 적어둔 것은 PR 본문에서 거의 항상 확정된 것처럼 서술된다.

**blast radius 의 T3.** 라이브러리의 진짜 영향 범위는 저장소 안이 아니라 그 패키지를 쓰는
다른 레포에 있다. 내부 참조만 보면 절반도 못 본다.

**오탐 억제 네 장치.** 리뷰 봇의 실패는 결함을 못 찾는 쪽보다 없는 결함을 확신 있게 보고하는
쪽이 비싸다. `All comments must be resolved` 가 머지 조건인 저장소에서는 전제가 틀린 지적
하나가 머지를 막고, 그 판정은 논증으로 해소되지 않는다.

- AC 확신도 라벨 — 높음(티켓 명시) / 중간(문맥) / 낮음(추론)
- verifier 상호 독립 — 몰아주면 "이미 3개 찾았으니 이것도" 로 판정이 오염된다
- "검증하지 못한 것" 섹션 강제 — 전부 통과해도 쓴다
- 미실행 테스트는 결함 근거가 아니다

## 요구사항

- `gh` CLI (인증 완료)
- 대상이 Node 프로젝트 (`package.json`) — pnpm / yarn / npm 자동 감지
- 테스트 러너가 없으면 워크트리 안에서 임시 설치한다. 프로젝트의 vite 메이저를 감지해
  호환되는 vitest 범위를 고른다 (vite 5 → `^3`, 6+ → `^4`)
- (선택) Atlassian MCP — 없으면 PR 본문만으로 진행하고 **그 사실을 리포트에 명시**한다

## 알려진 제약

**서브에이전트는 부모 세션의 MCP 도구를 상속받지 않는다.** 에이전트 안에서 `ToolSearch` 로
`mcp__*` 를 찾으면 에러가 아니라 "매칭 0건" 이 온다. 그래서 MCP 조회는 Step 1.5 에서
오케스트레이터가 수행해 `raw/` 로 넘긴다. 같은 이유로 에이전트 frontmatter 에 `tools:` 를
쓰지 않는다 — 화이트리스트는 기본 도구까지 막고, 생략해도 MCP 는 어차피 안 온다.

**에이전트 등록은 지연된다.** 설치 직후 `Agent type not found` 가 뜨면 잠시 뒤 재시도한다.

## 라이선스

MIT
