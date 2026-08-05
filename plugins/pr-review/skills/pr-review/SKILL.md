---
name: pr-review
description: PR 하나를 티켓 스펙·영향 범위·블랙박스 테스트로 검증해 결함을 찾아내는 오케스트레이터. `/pr-review <PR번호|URL>` 로 호출. PR 제목·본문·브랜치명에서 Jira 키를 뽑아 티켓 전문과 연결 문서를 컨텍스트로 주입하고, 변경 심볼의 blast radius(외부 소비 저장소까지)를 추적하고, 격리된 worktree 에서 테스트를 실제로 작성·실행한 뒤, 실패마다 진짜 결함인지 반증해 리포트를 만든다. 작성된 테스트는 원본 트리에 커밋하지 않는다(dry run). "이 PR 리뷰해줘", "PR 1234 검증해줘", "이 PR 테스트 좀 짜서 돌려봐", "이거 머지해도 되나", "이 변경 영향 범위 봐줘", "review this PR" 같은 요청에 사용.
---

# pr-review

PR 을 "읽고 의견을 말하는" 리뷰가 아니라, **티켓이 요구한 동작을 실제로 실행해 확인하는** 리뷰다.

정적으로 코드를 훑는 리뷰는 "이럴 것 같다" 에서 멈춘다. 이 스킬은 격리된 worktree 에서
테스트를 실제로 돌려서 **재현되는 실패**만 결함으로 보고한다. 재현 못 했으면 못 했다고 쓴다.

## 언제 쓰나

- PR 을 머지하기 전 마지막 검증
- 티켓 요구사항(AC)이 실제로 구현됐는지 확인해야 할 때
- 이 변경이 어디까지 파급되는지 모를 때 (특히 라이브러리·공용 패키지)
- 리뷰어가 붙기 전에 결함을 미리 털어내고 싶을 때

## 언제 쓰지 않나

- **코드 스타일·네이밍 지적** — `oh-my-claudecode:code-reviewer` 의 몫이다. 이 스킬은 동작만 본다.
- **보안 취약점 스캔** — `oh-my-claudecode:security-reviewer` 가 낫다.
- **티켓 컨텍스트만 필요할 때** — `/jira-ticket-context` 가 훨씬 싸다.
- **구현 전 설계 검토** — 코드가 있어야 실행할 수 있다.
- **diff 가 순수 문서·설정 변경일 때** — 실행할 동작이 없다. Step 1 에서 감지해 조기 종료한다.

## 입력

아래를 모두 같게 해석한다.

- `1234` / `#1234`
- `https://github.com/<owner>/<repo>/pull/1234`
- 인자 없음 → 현재 브랜치의 열린 PR (`gh pr view --json number`). 없으면 사용자에게 묻고 멈춘다.

(선택) `--quick` — Step 4·5 를 생략하고 스펙 대조와 blast radius 만 낸다. 워크트리를 만들지 않는다.

---

## Step 0 — 사전 점검

```bash
gh auth status
git -C . rev-parse --show-toplevel
gh repo view --json nameWithOwner -q .nameWithOwner
```

`gh auth status` 가 실패하면 **여기서 멈춘다.** 추측으로 진행하지 않는다.

작업 디렉터리는 저장소 **밖**에 둔다. 안에 두면 `git status` 를 오염시키고 실수로 커밋된다.

```
WORK=~/.claude/pr-review/<owner>__<repo>/<PR번호>/
```

**status 기준선을 먼저 박제한다.** 이게 없으면 나중에 오염을 판정할 수 없다.

```bash
mkdir -p "$WORK"
git -C <repo> status --porcelain > "$WORK/status-baseline.txt"
```

`$WORK` 가 이미 있으면 사용자에게 "이전 실행 결과가 있다. 이어서 할지, 새로 할지" 를 묻고,
이어서 할 경우 이미 있는 아티팩트를 만든 Step 은 건너뛴다.

**잔여 워크트리 점검** — 이전 실행이 중간에 끊겼을 수 있다.

```bash
git -C <repo> worktree list
```

`$WORK/wt` 가 남아 있으면 사용자에게 알리고 `${CLAUDE_PLUGIN_ROOT}/scripts/teardown-worktree.sh` 로 정리한 뒤 진행한다.

## Step 1 — PR 수집

```bash
gh pr view <PR> --json number,title,body,headRefName,baseRefName,author,files,additions,deletions,state,url \
  > "$WORK/pr.json"
gh pr diff <PR> > "$WORK/diff.patch"
```

`$WORK/pr.md` 에 사람이 읽을 메타를 정리한다. 그리고 **실행 가능성 판정**:

변경 파일에 **테스트 러너로 호출할 수 있는 소스**(`.ts`/`.tsx`/`.js`/`.jsx`/`.mjs` 중
설정 파일이 아닌 것)가 있는가로 갈린다.

| diff 내용 | 동작 |
|---|---|
| 실행 가능한 소스 있음 | 전체 파이프라인 |
| CI·빌드 설정만 (`.yml`, `.config.*`, `Dockerfile` 등) | ⭐**`--quick` 으로 자동 강등** |
| 문서·락파일만 (`.md`, `*-lock.yaml`) | 조기 종료 |

⭐**설정 변경을 조기 종료로 처리하지 마라.** 워크플로우·빌드 설정 PR 도 "티켓이 요구한 것과
맞는가", "기존 배포 경로에 어떤 영향을 주는가" 는 그대로 유효하다. 실행할 수 없는 것은
테스트 단계뿐이므로 그 단계만 건너뛴다. 강등했다는 사실을 사용자에게 알리고 리포트에 적는다.

diff 가 5000줄을 넘으면 → 사용자에게 범위를 좁힐지 묻는다 (경로 필터 제안).

**Jira 키 추출**: 제목 → 본문 → 브랜치명 순으로 `[A-Z][A-Z0-9]+-\d+`. 여러 개면 모두 수집한다.
하나도 없으면 spec-collector 를 건너뛰고 **"스펙 대조 불가" 를 리포트에 명시한다** — 스펙이
없으면 "AC 미충족" 판정의 근거 자체가 사라지기 때문이다.

**저장소 고유 규칙 수집**: 대상 저장소의 `CLAUDE.md` / `AGENTS.md` 를 읽어 `$WORK/house-rules.md`
로 요약한다. 여기에 "삭제된 CSS 클래스는 safelist 에", "컴포넌트-Storybook-Figma 3자 동기화"
같은 **그 저장소에서만 결함이 되는 규칙**이 들어 있다. 범용 에이전트는 이걸 모르므로 파일로
넘겨야 한다.

## Step 1.5 — MCP 데이터 선수집 ⭐

⭐**서브에이전트는 부모 세션의 MCP 도구를 상속받지 않는다.** 에이전트 안에서 `ToolSearch` 로
`mcp__atlassian__*` 를 찾으면 `No matching deferred tools found` 가 돌아온다(2026-08-05 실측).
`tools` frontmatter 를 지워도 마찬가지다.

따라서 **MCP 호출은 오케스트레이터가 한다.** 에이전트는 그 결과를 파일로 받아 판단만 한다.
이 편이 낫기도 하다 — MCP 호출은 결정적이라 재시도가 쉽고, 에이전트는 정규화·분석에 집중한다.

```
ToolSearch: select:mcp__atlassian__getJiraIssue,mcp__atlassian__getJiraIssueRemoteIssueLinks,mcp__atlassian__getConfluencePage,mcp__semble__search,mcp__musinsa-package-dependency-playground__get_dependents
```

수집해서 `$WORK/raw/` 아래에 원문 그대로 저장한다.

| 파일 | 내용 | 도구 |
|---|---|---|
| `raw/jira-<KEY>.md` | 티켓 전문 (parent·subtasks·issuelinks·comment 포함) | `getJiraIssue` |
| `raw/jira-<KEY>-links.md` | remote link (Confluence·Figma) | `getJiraIssueRemoteIssueLinks` |
| `raw/confluence-<id>.md` | 연결 문서 본문 | `getConfluencePage` |
| `raw/dependents.md` | 외부 소비 저장소 (배포 패키지일 때만) | `get_dependents` |
| `raw/refs-<심볼>.md` | 참조 위치 | `lsp_find_references` |

조회 실패는 **실패한 채로** `raw/` 에 기록한다 (`jira-MCC-59.md` 에 "조회 실패: <이유>").
⭐**키를 바꿔가며 추측하지 마라.** 못 읽었으면 못 읽은 것이고, 그 사실이 리포트에 남아야 한다.

`fields` 는 `["summary","description","status","issuetype","priority","parent","subtasks","issuelinks","labels","comment","attachment","updated"]`,
`responseContentFormat: markdown` 을 쓴다. cloudId 는 `23c14e7d-74ed-40b6-a0bb-fbc1f6351b84`
(musinsa-oneteam.atlassian.net). `jira.team.musinsa.com` 은 사내 레거시 호스트라 cloudId 로
넘기면 실패한다.

MCP 가 아예 없으면 이 단계를 건너뛰고 그 사실을 다음 단계에 알린다. 파이프라인은 계속 간다.

## Step 2 — 컨텍스트 확보 ⟨병렬⟩

두 에이전트를 **한 메시지에서 동시에** 띄운다. 서로 의존하지 않는다.
프롬프트에 `$WORK/raw/` 경로와 **무엇이 수집됐고 무엇이 실패했는지**를 명시한다.

```
Agent({
  subagent_type: "pr-review:spec-collector",
  description: "Jira 스펙 수집",
  prompt: "WORK=<절대경로> / PR=<번호> / Jira 키=<목록>
           house-rules=<경로>. spec.md 를 만들어라."
})
Agent({
  subagent_type: "pr-review:blast-radius-mapper",
  description: "영향 범위 추적",
  prompt: "WORK=<절대경로> / 저장소 루트=<경로> / diff=<경로>
           house-rules=<경로>. impact.md 를 만들어라."
})
```

⭐**에이전트 반환 텍스트는 요약으로만 믿는다. 실제 내용은 파일에서 읽는다.**
빈 응답을 반환하는 경로가 실재한다. 둘 다 끝나면 `spec.md` 와 `impact.md` 를 직접 Read 해서
다음 단계 프롬프트를 짠다. **파일이 없으면 1회만 재시도**하고, 그래도 없으면 그 단계를
건너뛰고 리포트에 명시한다.

## Step 3 — 테스트 전략

```
Agent({
  subagent_type: "pr-review:test-strategist",
  description: "블랙박스 테스트 전략",
  prompt: "WORK=<절대경로> / spec.md·impact.md·diff.patch 경로. strategy.md 를 만들어라."
})
```

페르소나 분할은 **에이전트 내부에서** 한다. 오케스트레이터가 페르소나별로 여러 번 호출하지
않는다 — 케이스 중복 제거를 한 컨텍스트에서 해야 하기 때문이다.

돌아온 `strategy.md` 의 케이스 수를 확인한다. 20개 초과 시 **P0·P1 만** executor 에 넘긴다.
3개 미만이면 전략이 부실한 것이니 무엇이 부족했는지(스펙 없음 / diff 가 얕음)를 리포트에 남긴다.

`--quick` 이면 여기서 Step 6 으로 건너뛴다.

## Step 4 — 실행 (격리 worktree)

부트스트랩은 스크립트가 한다. 명령어를 매번 재구성하지 않는다.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-worktree.sh" <repo-root> "$WORK" <PR번호>
```

수 분이 걸리므로 **`run_in_background: true` 로 돌리고 진행 상황을 알린다.**
끝나면 `$WORK/bootstrap.md` 를 읽어 성공/실패를 판정한다.

성공했으면 executor 를 띄운다.

```
Agent({
  subagent_type: "pr-review:test-executor",
  description: "테스트 작성·실행",
  prompt: "WORK=<절대경로> / 워크트리=<WORK>/wt / strategy.md 경로 /
           bootstrap.md 의 실행 명령. results.jsonl 을 만들어라."
})
```

부트스트랩이 실패했으면 executor 에 **"작성만 하고 실행하지 말라"** 를 명시해서 띄우거나
건너뛴다. 어느 쪽이든 **미실행 테스트를 결함 근거로 쓰지 않는다.**

## Step 5 — 실패 반증

`results.jsonl` 에 실패가 없으면 건너뛴다.

실패 건마다 verifier 를 띄운다. 5건 이하면 한 메시지에서 병렬로, 초과하면 5개씩 나눠서.

```
Agent({ subagent_type: "pr-review:finding-verifier", ... })   // 실패 1건당 1개
```

⭐**verifier 는 서로의 판정을 몰라야 한다.** 한 에이전트에 여러 실패를 몰아주면
"이미 결함 3개를 찾았으니 이것도 결함이겠지" 로 기울어 판정이 오염된다.

## Step 6 — 정리와 불변식 검증

**리포트보다 먼저 한다.** 오염된 저장소를 사용자가 모르는 채로 두는 것이 가장 나쁘다.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/teardown-worktree.sh" \
  <repo-root> "$WORK" "$WORK/status-baseline.txt"
```

스크립트는 테스트 산출물을 `$WORK/tests/` 로 회수한 뒤 워크트리를 제거하고, 네 가지를 검증한다
— 워크트리 잔여 / `git status` 동일 / 의존성 파일 무변경 / 테스트 산출물 유출.

**exit 1 이면 리포트를 쓰기 전에 사용자에게 알리고** 어떻게 할지 묻는다.

## Step 7 — 리포트

`$WORK/report.md` 를 쓰고 요약을 터미널에 출력한다.

```markdown
# PR #<번호> 리뷰 — <제목>

<한 문단: 머지해도 되는가에 대한 직답. 조건이 있으면 조건과 함께.>

## 확인된 결함        ← verifier 가 CONFIRMED_DEFECT 판정한 것만
| # | 심각도 | 위치 | 재현 | 근거 |
## 미충족 요구사항    ← spec.md 의 AC 중 대응 테스트가 없거나 실패한 것 (확신도 표기)
## 영향 범위          ← impact.md 요약. T3(외부 소비 저장소)가 있으면 맨 위로.
## 저장소 규칙 위반   ← house-rules.md 기준. 없으면 섹션 생략.
## 검증하지 못한 것   ← 생략 금지
```

**"검증하지 못한 것" 은 모든 테스트가 통과한 경우에도 쓴다.** 실행 못 한 테스트, 조회 실패한
티켓, 부트스트랩 실패, 커버리지 밖 경로를 여기 적는다. 비어 있으면 리포트가 실제보다 강해
보이고, 읽는 사람이 미검증 영역을 검증된 것으로 오해한다.

심각도는 **재현 가능성 기준**이다. 재현 스텝이 있는 것만 High 이상을 준다.

`$WORK` 는 **지우지 않는다.** 경로를 사용자에게 알려준다. 테스트를 실제로 도입하고 싶다면
그때 `$WORK/tests/` 에서 옮긴다 — **먼저 옮기지 않는다.** dry run 이 이 스킬의 전제다.

---

## 설치 후 확인 (최초 1회)

이 스킬의 에이전트는 플러그인이 함께 제공한다. `subagent_type` 은 `pr-review:` 접두사가
붙은 이름(`pr-review:spec-collector` 등)이다.

⭐**에이전트 등록은 지연된다.** 플러그인을 방금 설치했거나 에이전트 정의를 고친 직후
바로 호출하면 `Agent type '...' not found` 가 뜬다. 세션 재시작이 반드시 필요한 건 아니고 —
실측상 잠시 뒤 자동 등록됐다 — 다만 **직후를 신뢰하지 마라.** `not found` 가 나면
잠시 기다렸다 재시도하고, 그래도 안 되면 새 세션에서 쓴다.

⭐**에이전트 frontmatter 에 `tools:` 를 쓰지 마라.** 화이트리스트를 명시하면 기본 도구까지
골라서 막힌다. 다만 **`tools` 를 생략해도 MCP 는 상속되지 않는다** — 이 둘은 별개 층위다.
서브에이전트에는 부모 세션의 MCP 도구가 아예 전달되지 않으므로, MCP 조회는 **Step 1.5 에서
오케스트레이터가** 수행해 `$WORK/raw/` 로 넘긴다. 접근 제한은 프롬프트로 건다.

## 실패 모드

- **에이전트가 파일을 안 만들었다** → 반환 텍스트만 믿지 말고 파일 부재를 확인한 뒤 1회 재시도.
  두 번째도 실패하면 그 단계를 건너뛰고 리포트에 명시한다.
  ⭐**반환이 비어도 파일은 있을 수 있다.** 실제로 그런 사례를 겪었다 — 반환 텍스트가
  `"(작업 종료 — 추가 응답 없음)"` 인데 `spec.md` 는 정상적으로 쓰여 있었다. 항상 파일을 먼저 봐라.
- **MCP 도구가 안 잡힌다** → `mcp__atlassian__*` 가 없으면 `mcp__claude_ai_Atlassian__*` 폴백.
  그것도 없으면 스펙 수집을 포기하고 진행한다. **도구 이름을 지어내 호출하지 않는다.**
- **중간에 끊겼다** → 다음 실행의 Step 0 가 잔여 워크트리를 감지한다. `$WORK` 는 남아 있으므로
  이어서 할 수 있다.
- **전부 통과했다** → 그대로 보고한다. **결함을 만들어내지 않는다.**
  ⭐통과는 결함 부재의 증거가 아니라 시도의 기록이다.
