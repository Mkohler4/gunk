import { Database } from "bun:sqlite";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { CallToolResultSchema } from "@modelcontextprotocol/sdk/types.js";
import { afterEach, describe, expect, test } from "vitest";

import { runMigrations } from "../../src/schema/index.js";
import { createServer } from "../../src/server/index.js";
import { GET_GUNK_TOOL } from "../../src/tools/get_gunk.js";
import {
  createListGunksHandler,
  LIST_GUNKS_TOOL,
} from "../../src/tools/list_gunks.js";

interface SeedGunk {
  id: number;
  name: string;
  path: string;
  droppedAt: number;
  removedAt?: number | null;
}

function createMemoryStore(gunks: SeedGunk[] = []): Database {
  const db = new Database(":memory:");
  runMigrations(db);

  const insert = db.query(
    "INSERT INTO gunks (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
  );

  for (const gunk of gunks) {
    insert.run(
      gunk.id,
      gunk.name,
      gunk.path,
      gunk.droppedAt,
      gunk.removedAt ?? null,
    );
  }

  return db;
}

function parseGunks(result: unknown): unknown[] {
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
    throw new Error("Expected list_gunks to return text content");
  }

  return (JSON.parse(firstContent.text) as { gunks: unknown[] }).gunks;
}

describe("list_gunks handler", () => {
  test("returns empty list for empty store", async () => {
    const handleListGunks = createListGunksHandler(() => createMemoryStore());

    expect(parseGunks(await handleListGunks())).toEqual([]);
  });

  test("returns three seeded gunks in dropped_at desc order", async () => {
    const handleListGunks = createListGunksHandler(() =>
      createMemoryStore([
        { id: 1, name: "oldest", path: "/code/oldest", droppedAt: 100 },
        { id: 2, name: "newest", path: "/code/newest", droppedAt: 300 },
        { id: 3, name: "middle", path: "/code/middle", droppedAt: 200 },
      ]),
    );

    expect(parseGunks(await handleListGunks())).toEqual([
      {
        id: 2,
        name: "newest",
        path: "/code/newest",
        droppedAt: 300,
        removedAt: null,
      },
      {
        id: 3,
        name: "middle",
        path: "/code/middle",
        droppedAt: 200,
        removedAt: null,
      },
      {
        id: 1,
        name: "oldest",
        path: "/code/oldest",
        droppedAt: 100,
        removedAt: null,
      },
    ]);
  });

  test("excludes removed gunks", async () => {
    const handleListGunks = createListGunksHandler(() =>
      createMemoryStore([
        { id: 1, name: "active", path: "/code/active", droppedAt: 100 },
        {
          id: 2,
          name: "removed",
          path: "/code/removed",
          droppedAt: 200,
          removedAt: 300,
        },
      ]),
    );

    expect(parseGunks(await handleListGunks())).toEqual([
      {
        id: 1,
        name: "active",
        path: "/code/active",
        droppedAt: 100,
        removedAt: null,
      },
    ]);
  });
});

describe("list_gunks MCP registration", () => {
  let client: Client | undefined;
  let server: Server | undefined;

  afterEach(async () => {
    await client?.close();
    await server?.close();
  });

  async function connect(openStore = () => createMemoryStore()): Promise<void> {
    const [clientTransport, serverTransport] =
      InMemoryTransport.createLinkedPair();

    server = createServer({ openStore });
    client = new Client(
      {
        name: "gunk-mcp-list-gunks-test-client",
        version: "0.0.0",
      },
      {
        capabilities: {},
      },
    );

    await server.connect(serverTransport);
    await client.connect(clientTransport);
  }

  test("tools/list shows list_gunks", async () => {
    await connect();

    await expect(client?.listTools()).resolves.toEqual({
      tools: [LIST_GUNKS_TOOL, GET_GUNK_TOOL],
    });
  });

  test("tools/call returns the expected data", async () => {
    await connect(() =>
      createMemoryStore([
        { id: 1, name: "older", path: "/code/older", droppedAt: 100 },
        { id: 2, name: "newer", path: "/code/newer", droppedAt: 200 },
      ]),
    );

    const result = await client?.callTool(
      {
        name: "list_gunks",
        arguments: {},
      },
      CallToolResultSchema,
    );

    expect(result && parseGunks(result)).toEqual([
      {
        id: 2,
        name: "newer",
        path: "/code/newer",
        droppedAt: 200,
        removedAt: null,
      },
      {
        id: 1,
        name: "older",
        path: "/code/older",
        droppedAt: 100,
        removedAt: null,
      },
    ]);
  });
});
