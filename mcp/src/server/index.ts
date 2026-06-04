import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import type { Transport } from "@modelcontextprotocol/sdk/shared/transport.js";
import { ListToolsRequestSchema } from "@modelcontextprotocol/sdk/types.js";

import packageJson from "../../package.json" with { type: "json" };
import { SERVER_CAPABILITIES } from "./capabilities.js";

export function createServer(): Server {
  const server = new Server(
    {
      name: "gunk-mcp",
      version: packageJson.version,
    },
    {
      capabilities: SERVER_CAPABILITIES,
    },
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [],
  }));

  return server;
}

export async function startServer(
  transport: Transport = new StdioServerTransport(),
): Promise<Server> {
  const server = createServer();

  await server.connect(transport);

  return server;
}
