# daily-briefing

Morning briefing & nightly wrap-up plugin for Claude Code.

## Features

- `/good:morning` - 아침 브리핑 (Jira 태스크, 테크 뉴스, 어제 요약)
- `/good:night` - 퇴근 마무리 (오늘 요약, 내일 계획)

## Installation

### Option 1: Plugin (recommended)

```bash
/plugin marketplace add toothlessdev/claude-toothlessdev
/plugin install daily-briefing
```

### Option 2: MCP Server only

```bash
# npm에서 직접 설치
claude mcp add daily-briefing npx @toothlessdev/claude-daily-briefing

# 또는 로컬에서 실행
cd plugins/daily-briefing/mcp-server
npm install && npm run build
claude mcp add daily-briefing node ./dist/index.js
```

## Configuration

### Jira (optional)

환경변수를 설정하세요:

```bash
export JIRA_BASE_URL="https://your-org.atlassian.net"
export JIRA_EMAIL="your-email@example.com"
export JIRA_API_TOKEN="your-api-token"
export JIRA_PROJECT_KEY="PROJ"  # optional - 특정 프로젝트만 필터
```

API 토큰 발급: https://id.atlassian.net/manage-profile/security/api-tokens

### News

별도 설정 없이 동작합니다 (Hacker News API + GeekNews RSS).

## MCP Tools

| Tool | Description |
|------|-------------|
| `get_jira_tasks` | 할당된 Jira 태스크 조회 |
| `get_tech_news` | HN + GeekNews 최신 뉴스 |
| `get_session_summary` | 특정 날짜 세션 요약 조회 |
| `save_session_summary` | 오늘 세션 요약 저장 |
| `list_recent_sessions` | 최근 N일 세션 목록 |

## License

MIT
