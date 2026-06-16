import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { afterEach, beforeEach, expect, test } from "vitest";

import { createServer } from "../src/server/index.js";
import { GET_GUNK_TOOL } from "../src/tools/get_gunk.js";
import { LIST_GUNKS_TOOL } from "../src/tools/list_gunks.js";
import { LIST_SOURCES_TOOL } from "../src/tools/list_sources.js";
import { RUN_GUNK_TOOL } from "../src/tools/run_gunk.js";
import { SEARCH_GUNKS_TOOL } from "../src/tools/search_gunks.js";

let client: Client;
let server: Server;

beforeEach(async () => {
  const [clientTransport, serverTransport] =
    InMemoryTransport.createLinkedPair();

  server = createServer();
  client = new Client(
    {
      name: "gunk-mcp-test-client",
      version: "0.0.0",
    },
    {
      capabilities: {},
    },
  );

  await server.connect(serverTransport);
  await client.connect(clientTransport);
});

afterEach(async () => {
  await client.close();
  await server.close();
});

test("server starts and advertises tools capability", () => {
  expect(client.getServerVersion()).toEqual({
    name: "gunk-mcp",
    version: "0.0.1",
  });
  expect(client.getServerCapabilities()).toEqual({
    tools: {
      listChanged: false,
    },
  });
});

test("tools/list advertises registered tools", async () => {
  await expect(client.listTools()).resolves.toEqual({
    tools: [
      LIST_GUNKS_TOOL,
      LIST_SOURCES_TOOL,
      SEARCH_GUNKS_TOOL,
      GET_GUNK_TOOL,
      RUN_GUNK_TOOL,
    ],
  });
});
