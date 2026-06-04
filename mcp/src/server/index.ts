import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import type { Transport } from "@modelcontextprotocol/sdk/shared/transport.js";

import packageJson from "../../package.json" with { type: "json" };
import { SERVER_CAPABILITIES } from "./capabilities.js";
import { registerTools, type RegisterToolsOptions } from "./registerTools.js";

export function createServer(options: RegisterToolsOptions = {}): Server {
  const server = new Server(
    {
      name: "gunk-mcp",
      version: packageJson.version,
    },
    {
      capabilities: SERVER_CAPABILITIES,
    },
  );

  registerTools(server, options);

  return server;
}

export async function startServer(
  transport: Transport = new StdioServerTransport(),
  options: RegisterToolsOptions = {},
): Promise<Server> {
  const server = createServer(options);

  await server.connect(transport);

  return server;
}
