export interface JiraConfig {
  baseUrl: string;
  email: string;
  apiToken: string;
  projectKey?: string;
}

export interface JiraTask {
  key: string;
  summary: string;
  status: string;
  priority: string;
  assignee: string;
  updated: string;
}

export interface NewsArticle {
  title: string;
  url: string;
  source: "hackernews" | "geeknews";
  points?: number;
  comments?: number;
  summary?: string;
}

export interface SessionSummary {
  date: string;
  completed: string[];
  inProgress: string[];
  planned: string[];
  notes?: string;
}
