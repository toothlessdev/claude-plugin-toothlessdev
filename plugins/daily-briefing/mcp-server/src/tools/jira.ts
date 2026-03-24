import { JiraConfig, JiraTask } from "../types.js";

function getJiraConfig(): JiraConfig {
  const baseUrl = process.env.JIRA_BASE_URL;
  const email = process.env.JIRA_EMAIL;
  const apiToken = process.env.JIRA_API_TOKEN;

  if (!baseUrl || !email || !apiToken) {
    throw new Error(
      "Jira 설정이 필요합니다. 환경변수를 설정해주세요:\n" +
        "  JIRA_BASE_URL: Jira 인스턴스 URL (예: https://your-org.atlassian.net)\n" +
        "  JIRA_EMAIL: Jira 계정 이메일\n" +
        "  JIRA_API_TOKEN: Jira API 토큰 (https://id.atlassian.net/manage-profile/security/api-tokens)"
    );
  }

  return {
    baseUrl: baseUrl.replace(/\/$/, ""),
    email,
    apiToken,
    projectKey: process.env.JIRA_PROJECT_KEY,
  };
}

export async function getAssignedTasks(): Promise<JiraTask[]> {
  const config = getJiraConfig();

  const jql = config.projectKey
    ? `assignee = currentUser() AND project = "${config.projectKey}" AND status != Done ORDER BY priority DESC, updated DESC`
    : `assignee = currentUser() AND status != Done ORDER BY priority DESC, updated DESC`;

  const url = `${config.baseUrl}/rest/api/3/search?jql=${encodeURIComponent(jql)}&maxResults=20&fields=summary,status,priority,assignee,updated`;

  const response = await fetch(url, {
    headers: {
      Authorization: `Basic ${Buffer.from(`${config.email}:${config.apiToken}`).toString("base64")}`,
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Jira API 오류 (${response.status}): ${body}`);
  }

  const data = (await response.json()) as {
    issues: Array<{
      key: string;
      fields: {
        summary: string;
        status: { name: string };
        priority: { name: string };
        assignee: { displayName: string } | null;
        updated: string;
      };
    }>;
  };

  return data.issues.map((issue) => ({
    key: issue.key,
    summary: issue.fields.summary,
    status: issue.fields.status.name,
    priority: issue.fields.priority.name,
    assignee: issue.fields.assignee?.displayName ?? "Unassigned",
    updated: issue.fields.updated,
  }));
}
