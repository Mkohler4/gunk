import type { CallToolResult, Tool } from "@modelcontextprotocol/sdk/types.js";

import { readBundleFiles, readManifest } from "../lib/bundle.js";
import { readReadme } from "../lib/readme.js";
import { getGunk } from "../store/index.js";
import { summary } from "./list_gunks.js";
import { openDefaultStore, type StoreOpener } from "./list_gunks.js";

export const GET_GUNK_TOOL = {
  name: "get_gunk",
  description:
    "Get an extracted module bundle with manifest and file contents.",
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

      if (!gunk || !gunk.bundlePath) {
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
              ...summary(gunk),
              manifest: readManifest(gunk.bundlePath),
              readme: readReadme(gunk.bundlePath),
              files: readBundleFiles(gunk.bundlePath, gunk.files),
            }),
          },
        ],
      };
    } finally {
      db.close();
    }
  };
}
