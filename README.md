# claude-toothlessdev

Claude Code plugins by toothlessdev.

## Plugins

| Plugin | Description |
|--------|-------------|
| [daily-briefing](./plugins/daily-briefing) | Morning briefing & nightly wrap-up |
| [workflow-parallel](./plugins/workflow-parallel) | 9-stage interactive workflow for parallel multi-ticket execution (plan → plannotator → critic-verify → explore → DAG/Wave → Jira → worktree → cmux dispatch → orchestrate) |

## Installation

```bash
/plugin marketplace add toothlessdev/claude-toothlessdev
/plugin install daily-briefing
/plugin install workflow-parallel
```

## Adding more plugins

New plugins go under `plugins/<name>/` following the `.claude-plugin/` convention.

## License

MIT
