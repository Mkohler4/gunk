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
import {
  createListSourcesHandler,
  LIST_SOURCES_TOOL,
} from "../tools/list_sources.js";
import {
  createRunGunkHandler,
  RUN_GUNK_TOOL,
  type RunnerInvoker,
} from "../tools/run_gunk.js";
import {
  createSearchGunksHandler,
  SEARCH_GUNKS_TOOL,
} from "../tools/search_gunks.js";

export interface RegisterToolsOptions {
  openStore?: StoreOpener;
  /** Overrides how `run_gunk` reaches the sandbox runner (tests inject a fake). */
  invokeRunner?: RunnerInvoker;
}

export function registerTools(
  server: Server,
  { openStore = openDefaultStore, invokeRunner }: RegisterToolsOptions = {},
): void {
  const handleListGunks = createListGunksHandler(openStore);
  const handleListSources = createListSourcesHandler(openStore);
  const handleSearchGunks = createSearchGunksHandler(openStore);
  const handleGetGunk = createGetGunkHandler(openStore);
  const handleRunGunk = createRunGunkHandler(openStore, invokeRunner);

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [
      LIST_GUNKS_TOOL,
      LIST_SOURCES_TOOL,
      SEARCH_GUNKS_TOOL,
      GET_GUNK_TOOL,
      RUN_GUNK_TOOL,
    ],
  }));

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    if (request.params.name === LIST_GUNKS_TOOL.name) {
      return handleListGunks();
    }

    if (request.params.name === LIST_SOURCES_TOOL.name) {
      return handleListSources();
    }

    if (request.params.name === SEARCH_GUNKS_TOOL.name) {
      const query = request.params.arguments?.query;

      if (typeof query !== "string") {
        throw new McpError(
          ErrorCode.InvalidParams,
          "search_gunks requires a string query",
        );
      }

      return handleSearchGunks(query);
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

    if (request.params.name === RUN_GUNK_TOOL.name) {
      const gunkId = request.params.arguments?.gunkId;

      if (typeof gunkId !== "number" || !Number.isInteger(gunkId)) {
        throw new McpError(
          ErrorCode.InvalidParams,
          "run_gunk requires an integer gunkId",
        );
      }

      const rawInput = request.params.arguments?.input;
      let input: string[] | undefined;

      if (rawInput !== undefined) {
        if (
          !Array.isArray(rawInput) ||
          !rawInput.every((value) => typeof value === "string")
        ) {
          throw new McpError(
            ErrorCode.InvalidParams,
            "run_gunk input must be an array of strings",
          );
        }
        input = rawInput;
      }

      return handleRunGunk(gunkId, input);
    }

    throw new McpError(
      ErrorCode.MethodNotFound,
      `Unknown tool: ${request.params.name}`,
    );
  });
}
