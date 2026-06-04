import type { CallToolResult, Tool } from "@modelcontextprotocol/sdk/types.js";

import { readReadme } from "../lib/readme.js";
import { shallowTree } from "../lib/tree.js";
import { getGunk } from "../store/index.js";
import { openDefaultStore, type StoreOpener } from "./list_gunks.js";

export const GET_GUNK_TOOL = {
  name: "get_gunk",
  description: "Get a gunk's metadata, README, and shallow file tree.",
  inputSchema: {
    type: "object",
    properties: {
      id: {
        type: "integer",
      },
    },
    required: ["id"],
    additionalProperties: false,
  },
} satisfies Tool;

export function createGetGunkHandler(
  openDatabase: StoreOpener = openDefaultStore,
): (id: number) => Promise<CallToolResult> {
  return async (id) => {
    const db = openDatabase();

    try {
      const gunk = getGunk(db, id);

      if (!gunk || gunk.removedAt !== null) {
        return {
          isError: true,
          content: [
            {
              type: "text",
              text: `Gunk not found: ${id}`,
            },
          ],
        };
      }

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              id: gunk.id,
              name: gunk.name,
              path: gunk.path,
              droppedAt: gunk.droppedAt,
              readme: readReadme(gunk.path),
              tree: shallowTree(gunk.path),
            }),
          },
        ],
      };
    } finally {
      db.close();
    }
  };
}
