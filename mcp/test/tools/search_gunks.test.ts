import { Database } from "bun:sqlite";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { InMemoryTransport } from "@modelcontextprotocol/sdk/inMemory.js";
import type { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { CallToolResultSchema } from "@modelcontextprotocol/sdk/types.js";
import { afterEach, describe, expect, test } from "vitest";

import { runMigrations } from "../../src/schema/index.js";
import { createServer } from "../../src/server/index.js";
import { GET_GUNK_TOOL } from "../../src/tools/get_gunk.js";
import { LIST_GUNKS_TOOL } from "../../src/tools/list_gunks.js";
import { LIST_SOURCES_TOOL } from "../../src/tools/list_sources.js";
import {
  createSearchGunksHandler,
  openAIEmbedQuery,
  SEARCH_GUNKS_TOOL,
} from "../../src/tools/search_gunks.js";

function createMemoryStore(): Database {
  const db = new Database(":memory:");
  runMigrations(db);

  db.query(
    "INSERT INTO sources (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
  ).run(1, "source", "/code/source", 100, null);

  insertGunk(db, 1, "auth-module", "Google OAuth flow", 0.91);
  insertGunk(db, 2, "cli-module", "Maintenance commands", 0.72);
  insertGunk(db, 3, "auth-removed", "Removed auth flow", 0.99, 300);
  tagGunk(db, 1, "auth", 0.91);
  tagGunk(db, 1, "api", 0.8);
  tagGunk(db, 2, "cli", 0.72);
  tagGunk(db, 3, "auth", 0.99);

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
    throw new Error("Expected search_gunks to return text content");
  }

  return (JSON.parse(firstContent.text) as { gunks: unknown[] }).gunks;
}

describe("search_gunks handler", () => {
  test("returns auth module for auth", async () => {
    const handleSearchGunks = createSearchGunksHandler(
      createMemoryStore,
      async () => null,
    );

    expect(parseGunks(await handleSearchGunks("auth"))).toEqual([
      {
        id: 1,
        name: "auth-module",
        tags: ["auth", "api"],
        language: "TypeScript",
        confidence: 0.91,
        sourceId: 1,
        canonicalGunkId: 1,
        variantCount: 1,
      },
    ]);
  });

  test("semantic match for paraphrase", async () => {
    const handleSearchGunks = createSearchGunksHandler(
      () => {
        const db = createMemoryStore();
        insertEmbedding(db, 1, [1, 0]);
        insertEmbedding(db, 2, [0, 1]);
        return db;
      },
      async () => [1, 0],
    );

    expect(parseGunks(await handleSearchGunks("sign in with google"))).toEqual([
      {
        id: 1,
        name: "auth-module",
        tags: ["auth", "api"],
        language: "TypeScript",
        confidence: 0.91,
        sourceId: 1,
        canonicalGunkId: 1,
        variantCount: 1,
      },
    ]);
  });
});

describe("OpenAI query embeddings", () => {
  test("posts query to the embeddings API", async () => {
    const requests: Request[] = [];
    const fetcher = async (input: RequestInfo | URL, init?: RequestInit) => {
      const request = new Request(input, init);
      requests.push(request);
      return new Response(
        JSON.stringify({
          data: [{ embedding: [0.25, 0.5, 0.75] }],
        }),
        { status: 200 },
      );
    };

    await expect(
      openAIEmbedQuery("sign in with google", {
        apiKey: "sk-test",
        model: "text-embedding-3-small",
        fetcher,
      }),
    ).resolves.toEqual([0.25, 0.5, 0.75]);

    const request = requests[0];
    expect(request.url).toBe("https://api.openai.com/v1/embeddings");
    expect(request.headers.get("Authorization")).toBe("Bearer sk-test");

    await expect(request.json()).resolves.toEqual({
      model: "text-embedding-3-small",
      input: "sign in with google",
    });
  });
});

describe("search_gunks MCP registration", () => {
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
        name: "gunk-mcp-search-gunks-test-client",
        version: "0.0.0",
      },
      {
        capabilities: {},
      },
    );

    await server.connect(serverTransport);
    await client.connect(clientTransport);
  }

  test("tools/list shows search_gunks", async () => {
    await connect();

    await expect(client?.listTools()).resolves.toEqual({
      tools: [
        LIST_GUNKS_TOOL,
        LIST_SOURCES_TOOL,
        SEARCH_GUNKS_TOOL,
        GET_GUNK_TOOL,
      ],
    });
  });

  test("tools/call returns matching module", async () => {
    await connect();

    const result = await client?.callTool(
      {
        name: "search_gunks",
        arguments: { query: "oauth" },
      },
      CallToolResultSchema,
    );

    expect(result && parseGunks(result)).toMatchObject([
      {
        id: 1,
        name: "auth-module",
      },
    ]);
  });
});

function insertGunk(
  db: Database,
  id: number,
  name: string,
  purpose: string,
  confidence: number,
  removedAt: number | null = null,
): void {
  db.query(
    "INSERT INTO gunks (id, source_id, name, purpose, language, confidence, bundle_path, manifest_path, extracted_at, approved_at, removed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
  ).run(
    id,
    1,
    name,
    purpose,
    "TypeScript",
    confidence,
    `/tmp/modules/${id}`,
    `/tmp/modules/${id}/gunk.yml`,
    100 + id,
    null,
    removedAt,
  );
}

function tagGunk(
  db: Database,
  gunkId: number,
  tagName: string,
  confidence: number,
): void {
  const tag = db
    .query<{ id: number }, [string]>("SELECT id FROM tags WHERE name = ?")
    .get(tagName);

  if (!tag) {
    throw new Error(`Unknown test tag: ${tagName}`);
  }

  db.query(
    "INSERT INTO gunk_tags (gunk_id, tag_id, confidence) VALUES (?, ?, ?)",
  ).run(gunkId, tag.id, confidence);
}

function insertEmbedding(db: Database, gunkId: number, vector: number[]): void {
  const buffer = Buffer.alloc(vector.length * Float32Array.BYTES_PER_ELEMENT);
  vector.forEach((value, index) => {
    buffer.writeFloatLE(value, index * Float32Array.BYTES_PER_ELEMENT);
  });

  db.query(
    "INSERT INTO gunk_embeddings (gunk_id, vector, dim, model) VALUES (?, ?, ?, ?)",
  ).run(gunkId, buffer, vector.length, "test-embedding");
}
