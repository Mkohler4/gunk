import type { Database } from "bun:sqlite";
import { homedir } from "node:os";
import { join } from "node:path";
import type { CallToolResult, Tool } from "@modelcontextprotocol/sdk/types.js";

import { openStore } from "../schema/index.js";
import { listGunks } from "../store/index.js";

export const LIST_GUNKS_TOOL = {
  name: "list_gunks",
  description: "List the user's extracted module gunks.",
  inputSchema: {
    type: "object",
    properties: {},
  },
} satisfies Tool;

export type StoreOpener = () => Database;

export const openDefaultStore: StoreOpener = () =>
  openStore(join(homedir(), ".gunk", "store.db"));

export function createListGunksHandler(
  openDatabase: StoreOpener = openDefaultStore,
): () => Promise<CallToolResult> {
  return async () => {
    const db = openDatabase();

    try {
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify({ gunks: listGunks(db) }),
          },
        ],
      };
    } finally {
      db.close();
    }
  };
}
