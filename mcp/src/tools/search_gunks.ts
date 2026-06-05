import type { CallToolResult, Tool } from "@modelcontextprotocol/sdk/types.js";

import { searchGunks } from "../store/index.js";
import { openDefaultStore, summary, type StoreOpener } from "./list_gunks.js";

export type QueryEmbedder = (query: string) => Promise<number[] | null>;

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
  embedQuery: QueryEmbedder = ollamaEmbedQuery,
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
