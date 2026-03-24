---
name: good-night
description: "Nightly wrap-up skill. Trigger on: /good:night, good night, 좋은밤, 퇴근, 마무리, wrap up my day, end of day, 오늘 끝. Summarizes today's work session, logs accomplishments, and prepares tomorrow's context."
---

# Good Night - Daily Wrap-up

Wrap up the user's day with a session summary and tomorrow prep.

## Execution Flow

### Step 1: Greeting

수고하셨습니다 김대건님! 🌙

### Step 2: Collect Today's Work

Gather today's work from multiple sources:

1. **Current session context**: Summarize what was discussed and accomplished in this Claude Code session
2. **Git activity**: Check `git log --since="today" --oneline` for today's commits in the current repo
3. **User input**: Ask the user if there's anything else they worked on today that isn't captured above

Use the `save_session_summary` MCP tool to persist the summary.

### Step 3: Present Daily Summary

```
## 📊 오늘의 요약

### 완료한 작업
- [커밋/세션 기반 완료 항목]

### 진행 중
- [아직 끝나지 않은 작업]

### 기타
- [사용자가 추가로 입력한 항목]
```

### Step 4: Jira Status Update (Optional)

Use the `get_jira_tasks` tool to check current task statuses.

If any tasks were worked on today, suggest status updates:
```
## 🔄 Jira 상태 업데이트 제안
- PROJ-123: To Do → In Progress (오늘 작업 시작함)
- PROJ-456: In Progress → In Review (PR 올림)
```

Ask user for confirmation before suggesting (do not auto-update).

### Step 5: Tomorrow's Preview

Based on today's work and remaining Jira tasks:
```
## 📅 내일 예상 작업
1. [오늘 못 끝낸 작업]
2. [다음 우선순위 태스크]
3. [리뷰 대기 중인 항목]
```

### Step 6: Save & Close

Use the `save_session_summary` tool to save:
- Date
- Completed items
- In-progress items
- Tomorrow's planned items

```
오늘도 고생하셨습니다! 푹 쉬세요 😴
```

## Rules

1. Always ask the user for additional input - don't assume the session captures everything
2. Use git log as a reliable source of today's actual commits
3. Save the summary via MCP tool for tomorrow's morning briefing to reference
4. Present everything in Korean
5. Keep it concise - end-of-day summaries should be quick to review
