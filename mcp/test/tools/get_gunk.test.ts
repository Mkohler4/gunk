import { Database } from "bun:sqlite";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { CallToolResultSchema } from "@modelcontextprotocol/sdk/types.js";
import { afterEach, beforeEach, describe, expect, test } from "vitest";

import { runMigrations } from "../../src/schema/index.js";
import { createServer } from "../../src/server/index.js";
import {
  createGetGunkHandler,
  GET_GUNK_TOOL,
} from "../../src/tools/get_gunk.js";
import { LIST_GUNKS_TOOL } from "../../src/tools/list_gunks.js";

function createMemoryStore(
  path?: string,
  removedAt: number | null = null,
): Database {
  const db = new Database(":memory:");
  runMigrations(db);

  if (path) {
    db.query(
      "INSERT INTO gunks (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
    ).run(7, "fixture", path, 123, removedAt);
  }

  return db;
}

function parseTextResult(result: unknown): unknown {
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
    throw new Error("Expected get_gunk to return text content");
  }

  return JSON.parse(firstContent.text) as unknown;
}

describe("get_gunk handler", () => {
  let folderPath: string;

  beforeEach(() => {
    folderPath = mkdtempSync(join(tmpdir(), "gunk-tool-"));
    mkdirSync(join(folderPath, "src"));
    writeFileSync(join(folderPath, "README.md"), "# Fixture\n");
    writeFileSync(join(folderPath, "package.json"), "{}");
    writeFileSync(join(folderPath, "src", "index.ts"), "nested");
  });

  afterEach(() => {
    rmSync(folderPath, { recursive: true, force: true });
  });

  test("returns error for unknown id", async () => {
    const handleGetGunk = createGetGunkHandler(() => createMemoryStore());

    await expect(handleGetGunk(999)).resolves.toEqual({
      isError: true,
      content: [
        {
          type: "text",
          text: "Gunk not found: 999",
        },
      ],
    });
  });

  test("returns error for removed id", async () => {
    const handleGetGunk = createGetGunkHandler(() =>
      createMemoryStore(folderPath, 456),
    );

    await expect(handleGetGunk(7)).resolves.toMatchObject({
      isError: true,
      content: [{ text: "Gunk not found: 7" }],
    });
  });

  test("returns full payload for known id", async () => {
    const handleGetGunk = createGetGunkHandler(() =>
      createMemoryStore(folderPath),
    );

    expect(parseTextResult(await handleGetGunk(7))).toEqual({
      id: 7,
      name: "fixture",
      path: folderPath,
      droppedAt: 123,
      readme: "# Fixture\n",
      tree: [
        { name: "package.json", type: "file", size: 2 },
        { name: "README.md", type: "file", size: 10 },
        { name: "src", type: "dir" },
      ],
    });
  });
});

describe("get_gunk MCP registration", () => {
  let client: Client | undefined;
  let server: Server | undefined;
  let folderPath: string;

  beforeEach(() => {
    folderPath = mkdtempSync(join(tmpdir(), "gunk-tool-registration-"));
    writeFileSync(join(folderPath, "README.md"), "# Registered\n");
  });

  afterEach(async () => {
    await client?.close();
    await server?.close();
    rmSync(folderPath, { recursive: true, force: true });
  });

  async function connect(): Promise<void> {
    const [clientTransport, serverTransport] =
      InMemoryTransport.createLinkedPair();

    server = createServer({ openStore: () => createMemoryStore(folderPath) });
    client = new Client(
      {
        name: "gunk-mcp-get-gunk-test-client",
        version: "0.0.0",
      },
      {
        capabilities: {},
      },
    );

    await server.connect(serverTransport);
    await client.connect(clientTransport);
  }

  test("tools/list shows get_gunk", async () => {
    await connect();

    await expect(client?.listTools()).resolves.toEqual({
      tools: [LIST_GUNKS_TOOL, GET_GUNK_TOOL],
    });
  });

  test("tools/call returns get_gunk data", async () => {
    await connect();

    const result = await client?.callTool(
      {
        name: "get_gunk",
        arguments: { id: 7 },
      },
      CallToolResultSchema,
    );

    expect(result && parseTextResult(result)).toMatchObject({
      id: 7,
      name: "fixture",
      path: folderPath,
      readme: "# Registered\n",
    });
  });
});
