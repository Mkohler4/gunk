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
  createRunGunkHandler,
  defaultRunnerInvoker,
  type RunRequest,
  type RunnerInvoker,
  type RunnerResponse,
} from "../../src/tools/run_gunk.js";

const MANIFEST = `schema_version: 0
id: 7
name: "parser"
language: "Python"
requirements:
  runtime: "Python >= 3.11"
  packages:
    - "ebooklib"
  env: []
entrypoints:
  - path: "main.py"
    symbol: "parse_epub"
`;

function createMemoryStore(
  bundlePath?: string | null,
  language = "Python",
): Database {
  const db = new Database(":memory:");
  runMigrations(db);

  db.query(
    "INSERT INTO sources (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
  ).run(1, "source", "/code/source", 100, null);

  if (bundlePath !== undefined) {
    db.query(
      "INSERT INTO gunks (id, source_id, name, purpose, language, confidence, bundle_path, manifest_path, extracted_at, approved_at, removed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    ).run(
      7,
      1,
      "parser",
      "Parses EPUB",
      language,
      0.9,
      bundlePath,
      bundlePath === null ? null : join(bundlePath, "gunk.yml"),
      123,
      null,
      null,
    );
  }

  return db;
}

/** Captures the request and returns a canned response. */
function fakeInvoker(
  response: RunnerResponse,
  captured?: { request?: RunRequest },
): RunnerInvoker {
  return async (request) => {
    if (captured) {
      captured.request = request;
    }
    return response;
  };
}

function parseReceipt(result: unknown): Record<string, unknown> {
  if (
    typeof result !== "object" ||
    result === null ||
    !("content" in result) ||
    !Array.isArray(result.content)
  ) {
    throw new Error("Expected tool result content");
  }
  const first = result.content[0] as { type?: string; text?: string };
  if (first?.type !== "text" || typeof first.text !== "string") {
    throw new Error("Expected text content");
  }
  return JSON.parse(first.text) as Record<string, unknown>;
}

describe("run_gunk handler", () => {
  let folderPath: string;

  beforeEach(() => {
    folderPath = mkdtempSync(join(tmpdir(), "gunk-run-"));
    writeFileSync(join(folderPath, "gunk.yml"), MANIFEST);
    writeFileSync(join(folderPath, "main.py"), "print('ok')\n");
  });

  afterEach(() => {
    rmSync(folderPath, { recursive: true, force: true });
  });

  test("returns a passing receipt", async () => {
    const handle = createRunGunkHandler(
      () => createMemoryStore(folderPath),
      fakeInvoker({
        gunkId: 7,
        runnability: "terminal-runnable",
        isolation: "sandbox-exec",
        origin: "agent",
        command: "python3 main.py",
        exitCode: 0,
        stdout: "parsed 1 chapter\n",
        stderr: "",
        durationMs: 1840,
        timedOut: false,
        passed: true,
      }),
    );

    expect(parseReceipt(await handle(7))).toEqual({
      gunkId: 7,
      passed: true,
      runnability: "terminal-runnable",
      isolation: "sandbox-exec",
      exitCode: 0,
      durationMs: 1840,
      timedOut: false,
      command: "python3 main.py",
      stdout: "parsed 1 chapter\n",
      stderr: "",
      output: "parsed 1 chapter\n",
    });
  });

  test("returns a failing receipt", async () => {
    const handle = createRunGunkHandler(
      () => createMemoryStore(folderPath),
      fakeInvoker({
        gunkId: 7,
        runnability: "terminal-runnable",
        isolation: "sandbox-exec",
        command: "python3 main.py",
        exitCode: 3,
        stdout: "",
        stderr: "Traceback...\n",
        durationMs: 90,
        timedOut: false,
        passed: false,
      }),
    );

    const receipt = parseReceipt(await handle(7));
    expect(receipt.passed).toBe(false);
    expect(receipt.exitCode).toBe(3);
    expect(receipt.output).toBe("Traceback...\n");
  });

  test("returns a typed not-runnable result, not an error", async () => {
    const handle = createRunGunkHandler(
      () => createMemoryStore(folderPath),
      fakeInvoker({
        gunkId: 7,
        runnability: "cannot-determine",
        isolation: "not-run",
        passed: false,
        durationMs: 0,
      }),
    );

    const result = await handle(7);
    expect(result.isError).toBeUndefined();
    const receipt = parseReceipt(result);
    expect(receipt.runnability).toBe("cannot-determine");
    expect(receipt.passed).toBe(false);
  });

  test("resolves bundle, language, entrypoints, and packages from the store + manifest", async () => {
    const captured: { request?: RunRequest } = {};
    const handle = createRunGunkHandler(
      () => createMemoryStore(folderPath),
      fakeInvoker({ passed: true, runnability: "terminal-runnable" }, captured),
    );

    await handle(7, ["--in", "demo.epub"]);

    expect(captured.request).toEqual({
      gunkId: 7,
      bundlePath: folderPath,
      language: "Python",
      entrypoints: [{ path: "main.py", symbol: "parse_epub" }],
      dependencies: ["ebooklib"],
      arguments: ["--in", "demo.epub"],
    });
  });

  test("refuses a receipt that ran under reduced isolation", async () => {
    const handle = createRunGunkHandler(
      () => createMemoryStore(folderPath),
      fakeInvoker({
        passed: true,
        runnability: "terminal-runnable",
        isolation: "reduced-fallback",
      }),
    );

    const result = await handle(7);
    expect(result.isError).toBe(true);
    const first = result.content[0] as { text?: string };
    expect(first.text).toContain("reduced isolation");
  });

  test("surfaces a runner error as a tool error", async () => {
    const handle = createRunGunkHandler(
      () => createMemoryStore(folderPath),
      fakeInvoker({ error: "GUNK_RUN_BIN not set" }),
    );

    await expect(handle(7)).resolves.toMatchObject({
      isError: true,
      content: [{ text: "GUNK_RUN_BIN not set" }],
    });
  });

  test("errors for an unknown id without invoking the runner", async () => {
    let invoked = false;
    const handle = createRunGunkHandler(
      () => createMemoryStore(folderPath),
      async () => {
        invoked = true;
        return { passed: true };
      },
    );

    await expect(handle(999)).resolves.toMatchObject({
      isError: true,
      content: [{ text: "Gunk not found: 999" }],
    });
    expect(invoked).toBe(false);
  });

  test("errors when the gunk has no bundle", async () => {
    const handle = createRunGunkHandler(
      () => createMemoryStore(null),
      fakeInvoker({ passed: true }),
    );

    await expect(handle(7)).resolves.toMatchObject({
      isError: true,
      content: [{ text: "Gunk not found: 7" }],
    });
  });
});

describe("defaultRunnerInvoker", () => {
  const original = process.env.GUNK_RUN_BIN;

  afterEach(() => {
    if (original === undefined) {
      delete process.env.GUNK_RUN_BIN;
    } else {
      process.env.GUNK_RUN_BIN = original;
    }
  });

  test("reports an honest error (no spawn) when GUNK_RUN_BIN is unset", async () => {
    delete process.env.GUNK_RUN_BIN;
    const response = await defaultRunnerInvoker({
      gunkId: 7,
      bundlePath: "/tmp/x",
      language: "Python",
      entrypoints: [{ path: "main.py", symbol: null }],
      dependencies: [],
      arguments: [],
    });
    expect(response.error).toContain("GUNK_RUN_BIN");
  });
});

describe("run_gunk MCP registration", () => {
  let client: Client | undefined;
  let server: Server | undefined;
  let folderPath: string;

  beforeEach(() => {
    folderPath = mkdtempSync(join(tmpdir(), "gunk-run-reg-"));
    mkdirSync(join(folderPath, "src"), { recursive: true });
    writeFileSync(join(folderPath, "gunk.yml"), MANIFEST);
    writeFileSync(join(folderPath, "main.py"), "print('ok')\n");
  });

  afterEach(async () => {
    await client?.close();
    await server?.close();
    rmSync(folderPath, { recursive: true, force: true });
  });

  async function connect(invokeRunner: RunnerInvoker): Promise<void> {
    const [clientTransport, serverTransport] =
      InMemoryTransport.createLinkedPair();
    server = createServer({
      openStore: () => createMemoryStore(folderPath),
      invokeRunner,
    });
    client = new Client(
      { name: "gunk-mcp-run-test-client", version: "0.0.0" },
      { capabilities: {} },
    );
    await server.connect(serverTransport);
    await client.connect(clientTransport);
  }

  test("tools/list shows run_gunk", async () => {
    await connect(fakeInvoker({ passed: true }));
    const tools = await client?.listTools();
    expect(tools?.tools.map((tool) => tool.name)).toContain("run_gunk");
  });

  test("tools/call returns a run receipt", async () => {
    await connect(
      fakeInvoker({
        gunkId: 7,
        runnability: "terminal-runnable",
        passed: true,
        exitCode: 0,
        stdout: "ok\n",
        durationMs: 12,
      }),
    );

    const result = await client?.callTool(
      { name: "run_gunk", arguments: { gunkId: 7 } },
      CallToolResultSchema,
    );

    expect(result && parseReceipt(result)).toMatchObject({
      gunkId: 7,
      passed: true,
      runnability: "terminal-runnable",
    });
  });

  test("tools/call rejects a non-integer gunkId", async () => {
    await connect(fakeInvoker({ passed: true }));
    await expect(
      client?.callTool(
        { name: "run_gunk", arguments: { gunkId: "seven" } },
        CallToolResultSchema,
      ),
    ).rejects.toThrow();
  });
});
