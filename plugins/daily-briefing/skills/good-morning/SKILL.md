---
name: good-morning
description: "Morning briefing skill. Trigger on: /good:morning, good morning, 좋은아침, 아침 브리핑, morning briefing, start my day. Greets the user, summarizes yesterday's work, lists Jira assigned tasks, and shows latest tech news from Hacker News and GeekNews."
---

# Good Morning - Daily Briefing

Start the user's day with a comprehensive morning briefing.

## Execution Flow

Follow these steps in order. Use the MCP tools provided by `daily-briefing-mcp` server for data fetching.

### Step 1: Greeting

좋은아침입니다 김대건님! ☀️

Display current date and a brief motivational line.

### Step 2: Yesterday's Work Summary

Use the `get_session_summary` tool to retrieve yesterday's session data.

Present as:
```
## 📋 어제 한 일
- [작업 요약 항목들]
```

If no session data is available, check git log for yesterday's commits in the current repository and summarize them instead.

### Step 3: Jira Assigned Tasks

Use the `get_jira_tasks` tool to fetch tasks assigned to the user.

Present as:
```
## 🎯 할당된 Jira 태스크
| 키 | 제목 | 상태 | 우선순위 |
|----|------|------|----------|
| PROJ-123 | 태스크 제목 | In Progress | High |
```

Group by status: In Progress → To Do → In Review

### Step 4: Tech News

Use the `get_tech_news` tool to fetch latest news from Hacker News and GeekNews.

Present as:
```
## 🔥 오늘의 Tech News

### Hacker News
1. **[제목](실제링크)** - points | comments
2. ...

### GeekNews
1. **[제목](실제링크)** - 요약 한줄
2. ...
```

Show top 5 from each source. Only show articles not previously seen (the tool tracks read history).

### Step 5: Today's Focus

Based on the Jira tasks and yesterday's work, suggest 2-3 focus areas for today.

```
## 🎯 오늘의 포커스
1. [우선순위 높은 태스크 기반 제안]
2. [어제 이어서 할 작업]
3. [리뷰/미팅 등]
```

## Rules

1. Always use the MCP tools for data fetching - do not fabricate data
2. If a tool fails (e.g., Jira not configured), skip that section gracefully with a setup guide
3. Keep news summaries concise - one line per article
4. Always include real, clickable links for news articles
5. Present everything in Korean
