import type { CallToolResult, Tool } from "@modelcontextprotocol/sdk/types.js";

import { searchGunks } from "../store/index.js";
import { openDefaultStore, summary, type StoreOpener } from "./list_gunks.js";

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
): (query: string) => Promise<CallToolResult> {
  return async (query) => {
    const db = openDatabase();

    try {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              gunks: searchGunks(db, query).map(summary),
            }),
          },
        ],
      };
    } finally {
      db.close();
    }
  };
}
