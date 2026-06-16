import { Database } from "bun:sqlite";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { CallToolResultSchema } from "@modelcontextprotocol/sdk/types.js";
import { afterEach, describe, expect, test } from "vitest";

import { runMigrations } from "../../src/schema/index.js";
import { createServer } from "../../src/server/index.js";
import { GET_GUNK_TOOL } from "../../src/tools/get_gunk.js";
import { RUN_GUNK_TOOL } from "../../src/tools/run_gunk.js";
import { LIST_GUNKS_TOOL } from "../../src/tools/list_gunks.js";
import {
  createListSourcesHandler,
  LIST_SOURCES_TOOL,
} from "../../src/tools/list_sources.js";
import { SEARCH_GUNKS_TOOL } from "../../src/tools/search_gunks.js";

function createMemoryStore(): Database {
  const db = new Database(":memory:");
  runMigrations(db);

  db.query(
    "INSERT INTO sources (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
  ).run(1, "old-source", "/code/old-source", 100, null);
  db.query(
    "INSERT INTO sources (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
  ).run(2, "new-source", "/code/new-source", 200, null);
  db.query(
    "INSERT INTO sources (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
  ).run(3, "removed-source", "/code/removed-source", 300, 400);

  return db;
}

function parseSources(result: unknown): unknown[] {
  if (
    typeof result !== "object" ||
    result === null ||
    !("content" in result) ||
    !Array.isArray(result.content)
  ) {
    throw new Error("Expected current MCP tool result content");
  }

  const firstContent = result.content[0];

  if (
    typeof firstContent !== "object" ||
    firstContent === null ||
    !("type" in firstContent) ||
    firstContent.type !== "text" ||
    !("text" in firstContent) ||
    typeof firstContent.text !== "string"
  ) {
    throw new Error("Expected list_sources to return text content");
  }

  return (JSON.parse(firstContent.text) as { sources: unknown[] }).sources;
}

describe("list_sources handler", () => {
  test("returns dropped sources", async () => {
    const handleListSources = createListSourcesHandler(createMemoryStore);

    expect(parseSources(await handleListSources())).toEqual([
      {
        id: 2,
        name: "new-source",
        path: "/code/new-source",
        droppedAt: 200,
      },
      {
        id: 1,
        name: "old-source",
        path: "/code/old-source",
        droppedAt: 100,
      },
    ]);
  });
});

describe("list_sources MCP registration", () => {
  let client: Client | undefined;
  let server: Server | undefined;

  afterEach(async () => {
    await client?.close();
    await server?.close();
  });

  async function connect(): Promise<void> {
    const [clientTransport, serverTransport] =
      InMemoryTransport.createLinkedPair();

    server = createServer({ openStore: createMemoryStore });
    client = new Client(
      {
        name: "gunk-mcp-list-sources-test-client",
        version: "0.0.0",
      },
      {
        capabilities: {},
      },
    );

    await server.connect(serverTransport);
    await client.connect(clientTransport);
  }

  test("tools/list shows list_sources", async () => {
    await connect();

    await expect(client?.listTools()).resolves.toEqual({
      tools: [
        LIST_GUNKS_TOOL,
        LIST_SOURCES_TOOL,
        SEARCH_GUNKS_TOOL,
        GET_GUNK_TOOL,
        RUN_GUNK_TOOL,
      ],
    });
  });

  test("tools/call returns dropped sources", async () => {
    await connect();

    const result = await client?.callTool(
      {
        name: "list_sources",
        arguments: {},
      },
      CallToolResultSchema,
    );

    expect(result && parseSources(result)).toHaveLength(2);
  });
});
