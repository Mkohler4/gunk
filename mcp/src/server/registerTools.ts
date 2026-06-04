import type { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  CallToolRequestSchema,
  ErrorCode,
  ListToolsRequestSchema,
  McpError,
} from "@modelcontextprotocol/sdk/types.js";

import { createGetGunkHandler, GET_GUNK_TOOL } from "../tools/get_gunk.js";
import {
  createListGunksHandler,
  LIST_GUNKS_TOOL,
  openDefaultStore,
  type StoreOpener,
} from "../tools/list_gunks.js";

export interface RegisterToolsOptions {
  openStore?: StoreOpener;
}

export function registerTools(
  server: Server,
  { openStore = openDefaultStore }: RegisterToolsOptions = {},
): void {
  const handleListGunks = createListGunksHandler(openStore);
  const handleGetGunk = createGetGunkHandler(openStore);

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [LIST_GUNKS_TOOL, GET_GUNK_TOOL],
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    if (request.params.name === LIST_GUNKS_TOOL.name) {
      return handleListGunks();
    }

    if (request.params.name === GET_GUNK_TOOL.name) {
      const id = request.params.arguments?.id;

      if (typeof id !== "number" || !Number.isInteger(id)) {
        throw new McpError(
          ErrorCode.InvalidParams,
          "get_gunk requires an integer id",
        );
      }

      return handleGetGunk(id);
    }

    throw new McpError(
      ErrorCode.MethodNotFound,
      `Unknown tool: ${request.params.name}`,
    );
  });
}
