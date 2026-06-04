import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { afterEach, beforeEach, expect, test } from "vitest";

import { createServer } from "../src/server/index.js";

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

test("tools/list returns empty array when no tools registered", async () => {
  await expect(client.listTools()).resolves.toEqual({
    tools: [],
  });
});
