import { NewsArticle } from "../types.js";

const HN_TOP_STORIES_URL = "https://hacker-news.firebaseio.com/v0/topstories.json";
const HN_ITEM_URL = "https://hacker-news.firebaseio.com/v0/item";
const GEEKNEWS_RSS_URL = "https://news.hada.io/rss";

async function fetchHackerNews(count: number = 5): Promise<NewsArticle[]> {
  const response = await fetch(HN_TOP_STORIES_URL);
  if (!response.ok) throw new Error(`HN API 오류: ${response.status}`);

  const storyIds = (await response.json()) as number[];
  const topIds = storyIds.slice(0, count);

  const stories = await Promise.all(
    topIds.map(async (id) => {
      const res = await fetch(`${HN_ITEM_URL}/${id}.json`);
      return res.json() as Promise<{
        title: string;
        url?: string;
        score: number;
        descendants?: number;
        id: number;
      }>;
    })
  );

  return stories.map((story) => ({
    title: story.title,
    url: story.url || `https://news.ycombinator.com/item?id=${story.id}`,
    source: "hackernews" as const,
    points: story.score,
    comments: story.descendants ?? 0,
  }));
}

async function fetchGeekNews(count: number = 5): Promise<NewsArticle[]> {
  const response = await fetch(GEEKNEWS_RSS_URL);
  if (!response.ok) throw new Error(`GeekNews RSS 오류: ${response.status}`);

  const xml = await response.text();

  const articles: NewsArticle[] = [];
  const itemRegex = /<item>([\s\S]*?)<\/item>/g;
  const titleRegex = /<title><!\[CDATA\[(.*?)\]\]><\/title>/;
  const linkRegex = /<link>(.*?)<\/link>/;
  const descRegex = /<description><!\[CDATA\[(.*?)\]\]><\/description>/;

  let match;
  while ((match = itemRegex.exec(xml)) !== null && articles.length < count) {
    const item = match[1];
    const title = titleRegex.exec(item)?.[1] ?? "";
    const url = linkRegex.exec(item)?.[1] ?? "";
    const desc = descRegex.exec(item)?.[1] ?? "";

    const summary = desc.replace(/<[^>]*>/g, "").slice(0, 100);

    articles.push({
      title,
      url,
      source: "geeknews",
      summary: summary || undefined,
    });
  }

  return articles;
}

export async function getTechNews(
  count: number = 5
): Promise<{ hackernews: NewsArticle[]; geeknews: NewsArticle[] }> {
  const [hackernews, geeknews] = await Promise.all([
    fetchHackerNews(count).catch((e) => {
      console.error("HN fetch failed:", e);
      return [] as NewsArticle[];
    }),
    fetchGeekNews(count).catch((e) => {
      console.error("GeekNews fetch failed:", e);
      return [] as NewsArticle[];
    }),
  ]);

  return { hackernews, geeknews };
}
