import type { CallToolResult, Tool } from "@modelcontextprotocol/sdk/types.js";

import { readReadme } from "../lib/readme.js";
import { shallowTree } from "../lib/tree.js";
import { getGunk } from "../store/index.js";
import { openDefaultStore, type StoreOpener } from "./list_gunks.js";

export const GET_GUNK_TOOL = {
  name: "get_gunk",
  description: "Get a module gunk's metadata, README, and shallow file tree.",
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

      if (!gunk || gunk.removedAt !== null || !gunk.bundlePath) {
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
              sourceId: gunk.sourceId,
              name: gunk.name,
              purpose: gunk.purpose,
              language: gunk.language,
              confidence: gunk.confidence,
              bundlePath: gunk.bundlePath,
              manifestPath: gunk.manifestPath,
              extractedAt: gunk.extractedAt,
              approvedAt: gunk.approvedAt,
              readme: readReadme(gunk.bundlePath),
              tree: shallowTree(gunk.bundlePath),
            }),
          },
        ],
      };
    } finally {
      db.close();
    }
  };
}
