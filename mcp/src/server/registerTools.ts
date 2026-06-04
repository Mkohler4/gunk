import type { Server } from "@modelcontextprotocol/sdk/server/index.js";
import {
  CallToolRequestSchema,
  ErrorCode,
  ListToolsRequestSchema,
  McpError,
} from "@modelcontextprotocol/sdk/types.js";

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

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [LIST_GUNKS_TOOL],
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    if (request.params.name === LIST_GUNKS_TOOL.name) {
      return handleListGunks();
    }

    throw new McpError(
      ErrorCode.MethodNotFound,
      `Unknown tool: ${request.params.name}`,
    );
  });
}
