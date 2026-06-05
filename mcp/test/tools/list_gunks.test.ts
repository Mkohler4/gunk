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
  sourceId?: number;
  purpose?: string | null;
  language?: string | null;
  confidence?: number | null;
  bundlePath?: string | null;
  manifestPath?: string | null;
  extractedAt?: number | null;
  approvedAt?: number | null;
  removedAt?: number | null;
}

function createMemoryStore(gunks: SeedGunk[] = []): Database {
  const db = new Database(":memory:");
  runMigrations(db);

  db.query(
    "INSERT INTO sources (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
  ).run(1, "source", "/code/source", 100, null);

  const insert = db.query(
    "INSERT INTO gunks (id, source_id, name, purpose, language, confidence, bundle_path, manifest_path, extracted_at, approved_at, removed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
  );

  for (const gunk of gunks) {
    insert.run(
      gunk.id,
      gunk.sourceId ?? 1,
      gunk.name,
      gunk.purpose ?? null,
      gunk.language ?? null,
      gunk.confidence ?? null,
      gunk.bundlePath ?? `/tmp/modules/${gunk.id}`,
      gunk.manifestPath ?? `/tmp/modules/${gunk.id}/gunk.yml`,
      gunk.extractedAt ?? 100 + gunk.id,
      gunk.approvedAt ?? null,
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

  test("returns seeded module gunks in id desc order", async () => {
    const handleListGunks = createListGunksHandler(() =>
      createMemoryStore([
        { id: 1, name: "oldest", confidence: 0.6 },
        { id: 2, name: "newest", confidence: 0.9 },
        { id: 3, name: "middle", confidence: 0.7 },
      ]),
    );

    expect(parseGunks(await handleListGunks())).toEqual([
      {
        id: 3,
        sourceId: 1,
        name: "middle",
        purpose: null,
        language: null,
        confidence: 0.7,
        bundlePath: "/tmp/modules/3",
        manifestPath: "/tmp/modules/3/gunk.yml",
        extractedAt: 103,
        approvedAt: null,
        removedAt: null,
        tags: [],
      },
      {
        id: 2,
        sourceId: 1,
        name: "newest",
        purpose: null,
        language: null,
        confidence: 0.9,
        bundlePath: "/tmp/modules/2",
        manifestPath: "/tmp/modules/2/gunk.yml",
        extractedAt: 102,
        approvedAt: null,
        removedAt: null,
        tags: [],
      },
      {
        id: 1,
        sourceId: 1,
        name: "oldest",
        purpose: null,
        language: null,
        confidence: 0.6,
        bundlePath: "/tmp/modules/1",
        manifestPath: "/tmp/modules/1/gunk.yml",
        extractedAt: 101,
        approvedAt: null,
        removedAt: null,
        tags: [],
      },
    ]);
  });

  test("excludes removed gunks", async () => {
    const handleListGunks = createListGunksHandler(() =>
      createMemoryStore([
        { id: 1, name: "active" },
        {
          id: 2,
          name: "removed",
          removedAt: 300,
        },
      ]),
    );

    expect(parseGunks(await handleListGunks())).toEqual([
      {
        id: 1,
        sourceId: 1,
        name: "active",
        purpose: null,
        language: null,
        confidence: null,
        bundlePath: "/tmp/modules/1",
        manifestPath: "/tmp/modules/1/gunk.yml",
        extractedAt: 101,
        approvedAt: null,
        removedAt: null,
        tags: [],
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
        { id: 1, name: "older", confidence: 0.5 },
        { id: 2, name: "newer", confidence: 0.8 },
      ]),
    );

    const result = await client?.callTool(
      {
        name: "list_gunks",
        arguments: {},
      },
      CallToolResultSchema,
    );

    expect(result && parseGunks(result)).toMatchObject([
      {
        id: 2,
        name: "newer",
        confidence: 0.8,
      },
      {
        id: 1,
        name: "older",
        confidence: 0.5,
      },
    ]);
  });
});
