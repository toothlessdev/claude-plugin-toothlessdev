import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";
import { SessionSummary } from "../types.js";

const DATA_DIR = join(homedir(), ".claude-daily-briefing");
const SESSIONS_DIR = join(DATA_DIR, "sessions");

async function ensureDir(dir: string): Promise<void> {
  await mkdir(dir, { recursive: true });
}

function getDateStr(date?: Date): string {
  const d = date ?? new Date();
  return d.toISOString().split("T")[0];
}

function getSessionPath(date: string): string {
  return join(SESSIONS_DIR, `${date}.json`);
}

export async function saveSessionSummary(
  summary: Omit<SessionSummary, "date"> & { date?: string }
): Promise<string> {
  await ensureDir(SESSIONS_DIR);

  const date = summary.date ?? getDateStr();
  const sessionData: SessionSummary = { ...summary, date };
  const filePath = getSessionPath(date);

  await writeFile(filePath, JSON.stringify(sessionData, null, 2), "utf-8");

  return `세션 요약이 저장되었습니다: ${filePath}`;
}

export async function getSessionSummary(
  date?: string
): Promise<SessionSummary | null> {
  const targetDate = date ?? getYesterdayStr();
  const filePath = getSessionPath(targetDate);

  try {
    const content = await readFile(filePath, "utf-8");
    return JSON.parse(content) as SessionSummary;
  } catch {
    return null;
  }
}

export async function listRecentSessions(
  days: number = 7
): Promise<SessionSummary[]> {
  await ensureDir(SESSIONS_DIR);

  const sessions: SessionSummary[] = [];
  const today = new Date();

  for (let i = 0; i < days; i++) {
    const d = new Date(today);
    d.setDate(d.getDate() - i);
    const session = await getSessionSummary(getDateStr(d));
    if (session) sessions.push(session);
  }

  return sessions;
}

function getYesterdayStr(): string {
  const d = new Date();
  d.setDate(d.getDate() - 1);
  return getDateStr(d);
}
