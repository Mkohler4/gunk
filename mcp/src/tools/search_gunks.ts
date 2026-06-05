import type { CallToolResult, Tool } from "@modelcontextprotocol/sdk/types.js";

import { searchGunks } from "../store/index.js";
import { openDefaultStore, summary, type StoreOpener } from "./list_gunks.js";

export type QueryEmbedder = (query: string) => Promise<number[] | null>;
type Fetcher = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;

export const SEARCH_GUNKS_TOOL = {
  name: "search_gunks",
  description: "Search extracted module gunks by tag, name, or purpose.",
  inputSchema: {
    type: "object",
    properties: {
      query: {
        type: "string",
      },
    },
    required: ["query"],
    additionalProperties: false,
  },
} satisfies Tool;

export function createSearchGunksHandler(
  openDatabase: StoreOpener = openDefaultStore,
  embedQuery: QueryEmbedder = configuredEmbedQuery,
): (query: string) => Promise<CallToolResult> {
  return async (query) => {
    const db = openDatabase();

    try {
      const queryVector = await embedQuery(query).catch(() => null);

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              gunks: searchGunks(db, query, { queryVector }).map(summary),
            }),
          },
        ],
      };
    } finally {
      db.close();
    }
  };
}

export async function configuredEmbedQuery(
  query: string,
): Promise<number[] | null> {
  const openAIEmbedding = await openAIEmbedQuery(query);

  if (openAIEmbedding && openAIEmbedding.length > 0) {
    return openAIEmbedding;
  }

  return ollamaEmbedQuery(query);
}

export async function openAIEmbedQuery(
  query: string,
  options: {
    apiKey?: string;
    model?: string;
    fetcher?: Fetcher;
  } = {},
): Promise<number[] | null> {
  const trimmed = query.trim();
  const apiKey = options.apiKey ?? process.env.OPENAI_API_KEY ?? "";

  if (trimmed.length === 0 || apiKey.length === 0) {
    return null;
  }

  const response = await (options.fetcher ?? fetch)(
    "https://api.openai.com/v1/embeddings",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model:
          options.model ??
          process.env.OPENAI_EMBEDDING_MODEL ??
          "text-embedding-3-small",
        input: trimmed,
      }),
      signal: AbortSignal.timeout(3_000),
    },
  );

  if (!response.ok) {
    return null;
  }

  const body = (await response.json()) as {
    data?: Array<{ embedding?: unknown }>;
  };
  const embedding = body.data?.[0]?.embedding;

  if (Array.isArray(embedding)) {
    return embedding.filter(
      (value): value is number => typeof value === "number",
    );
  }

  return null;
}

async function ollamaEmbedQuery(query: string): Promise<number[] | null> {
  const trimmed = query.trim();
  if (trimmed.length === 0) {
    return null;
  }

  const response = await fetch("http://localhost:11434/api/embeddings", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: "nomic-embed-text",
      prompt: trimmed,
    }),
    signal: AbortSignal.timeout(150),
  });

  if (!response.ok) {
    return null;
  }

  const body = (await response.json()) as {
    embedding?: unknown;
    embeddings?: unknown;
  };

  if (Array.isArray(body.embedding)) {
    return body.embedding.filter(
      (value): value is number => typeof value === "number",
    );
  }

  if (Array.isArray(body.embeddings) && Array.isArray(body.embeddings[0])) {
    return body.embeddings[0].filter(
      (value): value is number => typeof value === "number",
    );
  }

  return null;
}
