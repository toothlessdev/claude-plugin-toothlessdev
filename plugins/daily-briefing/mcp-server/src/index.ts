#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { getAssignedTasks } from "./tools/jira.js";
import { getTechNews } from "./tools/news.js";
import {
  getSessionSummary,
  saveSessionSummary,
  listRecentSessions,
} from "./tools/session.js";

const server = new McpServer({
  name: "daily-briefing-mcp",
  version: "1.0.0",
});

// Jira 할당 태스크 조회
server.tool(
  "get_jira_tasks",
  "Jira에서 나에게 할당된 태스크 목록을 조회합니다",
  {},
  async () => {
    try {
      const tasks = await getAssignedTasks();
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(tasks, null, 2),
          },
        ],
      };
    } catch (e) {
      return {
        content: [
          {
            type: "text" as const,
            text: `Jira 조회 실패: ${e instanceof Error ? e.message : String(e)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// 테크 뉴스 조회
server.tool(
  "get_tech_news",
  "Hacker News와 GeekNews에서 최신 기술 뉴스를 가져옵니다",
  {
    count: z
      .number()
      .optional()
      .default(5)
      .describe("각 소스에서 가져올 뉴스 개수 (기본: 5)"),
  },
  async ({ count }) => {
    try {
      const news = await getTechNews(count);
      return {
        content: [
          {
            type: "text" as const,
            text: JSON.stringify(news, null, 2),
          },
        ],
      };
    } catch (e) {
      return {
        content: [
          {
            type: "text" as const,
            text: `뉴스 조회 실패: ${e instanceof Error ? e.message : String(e)}`,
          },
        ],
        isError: true,
      };
    }
  }
);

// 세션 요약 조회
server.tool(
  "get_session_summary",
  "특정 날짜의 작업 세션 요약을 조회합니다 (기본: 어제)",
  {
    date: z
      .string()
      .optional()
      .describe("조회할 날짜 (YYYY-MM-DD 형식, 기본: 어제)"),
  },
  async ({ date }) => {
    const summary = await getSessionSummary(date);
    if (!summary) {
      return {
        content: [
          {
            type: "text" as const,
            text: `${date ?? "어제"} 세션 요약이 없습니다.`,
          },
        ],
      };
    }
    return {
      content: [
        {
          type: "text" as const,
          text: JSON.stringify(summary, null, 2),
        },
      ],
    };
  }
);

// 세션 요약 저장
server.tool(
  "save_session_summary",
  "오늘의 작업 세션 요약을 저장합니다",
  {
    completed: z.array(z.string()).describe("완료한 작업 목록"),
    inProgress: z.array(z.string()).describe("진행 중인 작업 목록"),
    planned: z.array(z.string()).describe("내일 예정 작업 목록"),
    notes: z.string().optional().describe("추가 메모"),
  },
  async ({ completed, inProgress, planned, notes }) => {
    const result = await saveSessionSummary({
      completed,
      inProgress,
      planned,
      notes,
    });
    return {
      content: [
        {
          type: "text" as const,
          text: result,
        },
      ],
    };
  }
);

// 최근 세션 목록
server.tool(
  "list_recent_sessions",
  "최근 N일간의 세션 요약 목록을 조회합니다",
  {
    days: z
      .number()
      .optional()
      .default(7)
      .describe("조회할 일수 (기본: 7)"),
  },
  async ({ days }) => {
    const sessions = await listRecentSessions(days);
    return {
      content: [
        {
          type: "text" as const,
          text:
            sessions.length > 0
              ? JSON.stringify(sessions, null, 2)
              : `최근 ${days}일간 저장된 세션이 없습니다.`,
        },
      ],
    };
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("daily-briefing-mcp server running on stdio");
}

main().catch(console.error);
