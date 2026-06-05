import type { CallToolResult, Tool } from "@modelcontextprotocol/sdk/types.js";

import { listSources } from "../store/index.js";
import { openDefaultStore, type StoreOpener } from "./list_gunks.js";

export const LIST_SOURCES_TOOL = {
  name: "list_sources",
  description: "List source folders dropped into gunk.",
  inputSchema: {
    type: "object",
    properties: {},
  },
} satisfies Tool;

export function createListSourcesHandler(
  openDatabase: StoreOpener = openDefaultStore,
): () => Promise<CallToolResult> {
  return async () => {
    const db = openDatabase();

    try {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              sources: listSources(db).map(({ id, name, path, droppedAt }) => ({
                id,
                name,
                path,
                droppedAt,
              })),
            }),
          },
        ],
      };
    } finally {
      db.close();
    }
  };
}
