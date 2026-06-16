import { spawn } from "node:child_process";
import type { CallToolResult, Tool } from "@modelcontextprotocol/sdk/types.js";

import { readManifest } from "../lib/bundle.js";
import {
  parseEntrypoints,
  parseRequirementPackages,
  type ManifestEntrypoint,
} from "../lib/manifest.js";
import { getGunk } from "../store/index.js";
import { openDefaultStore, type StoreOpener } from "./list_gunks.js";

export const RUN_GUNK_TOOL = {
  name: "run_gunk",
  description:
    "Run an extracted module's entrypoint in gunk's sandbox (no network, " +
    "writes confined to a throwaway run dir, time-boxed) and return a pass/fail " +
    "receipt. Use this to verify a module actually works before relying on it. " +
    "Non-terminal modules (need network/secrets, UI, long-running, or " +
    "indeterminate) return a typed 'not runnable here' result, not a failure.",
  inputSchema: {
    type: "object",
    properties: {
      gunkId: { type: "integer" },
      input: {
        type: "array",
        items: { type: "string" },
        description:
          "Optional extra command-line arguments passed to the module (its own argv, confined by the sandbox).",
      },
    },
    required: ["gunkId"],
    additionalProperties: false,
  },
} satisfies Tool;

/** The resolved request handed to the app-side `gunk run` verb (ADR-0017). */
export interface RunRequest {
  gunkId: number;
  bundlePath: string;
  language: string;
  entrypoints: ManifestEntrypoint[];
  dependencies: string[];
  arguments: string[];
}

/** The verb's response: a `SmokeRunResult` projection, or a typed error. */
export interface RunnerResponse {
  gunkId?: number;
  runnability?: string;
  isolation?: string;
  origin?: string;
  command?: string | null;
  exitCode?: number | null;
  stdout?: string;
  stderr?: string;
  durationMs?: number;
  timedOut?: boolean;
  passed?: boolean;
  outputArtifacts?: string[];
  startedAt?: string;
  error?: string;
}

export type RunnerInvoker = (request: RunRequest) => Promise<RunnerResponse>;

/**
 * Default invoker: spawns the app-side `gunk run` verb, which executes the
 * module through the **one** sandbox runner (ADR-0016/0017) and prints a JSON
 * receipt. The binary is resolved from `GUNK_RUN_BIN` (the gunk app executable);
 * when it is not configured the tool reports an honest "runner not available"
 * receipt rather than spawning or guessing.
 */
export const defaultRunnerInvoker: RunnerInvoker = async (request) => {
  const binary = process.env.GUNK_RUN_BIN;
  if (!binary || binary.length === 0) {
    return {
      error:
        "The gunk run binary is not configured. Set GUNK_RUN_BIN to the gunk app executable to enable run_gunk.",
    };
  }

  return spawnRunner(binary, request);
};

/** Hard ceiling on the spawned verb, above the runner's own timeout cap. */
const SPAWN_TIMEOUT_MS = 180_000;

/** Cap captured output so a runaway module can't exhaust the MCP process. */
const MAX_OUTPUT_BYTES = 8 * 1024 * 1024;

function spawnRunner(
  binary: string,
  request: RunRequest,
): Promise<RunnerResponse> {
  return new Promise((resolve) => {
    const child = spawn(binary, ["run"], {
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";
    let bytes = 0;
    let settled = false;

    const finish = (response: RunnerResponse): void => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(killTimer);
      resolve(response);
    };

    const killTimer = setTimeout(() => {
      child.kill("SIGKILL");
      finish({ error: "The gunk run verb exceeded its time limit." });
    }, SPAWN_TIMEOUT_MS);

    const overBudget = (chunk: Buffer): boolean => {
      bytes += chunk.byteLength;
      if (bytes > MAX_OUTPUT_BYTES) {
        child.kill("SIGKILL");
        finish({ error: "The gunk run verb produced too much output." });
        return true;
      }
      return false;
    };

    child.stdout.on("data", (chunk: Buffer) => {
      if (!overBudget(chunk)) {
        stdout += chunk.toString("utf8");
      }
    });
    child.stderr.on("data", (chunk: Buffer) => {
      if (!overBudget(chunk)) {
        stderr += chunk.toString("utf8");
      }
    });

    child.on("error", (error: Error) => {
      finish({ error: `Could not start the gunk run verb: ${error.message}` });
    });

    child.on("close", () => {
      try {
        finish(JSON.parse(stdout) as RunnerResponse);
      } catch {
        const detail = stderr.trim() || stdout.trim() || "no output";
        finish({
          error: `The gunk run verb returned no valid receipt: ${detail}`,
        });
      }
    });

    child.stdin.end(JSON.stringify(request));
  });
}

export function createRunGunkHandler(
  openDatabase: StoreOpener = openDefaultStore,
  invokeRunner: RunnerInvoker = defaultRunnerInvoker,
): (gunkId: number, input?: string[]) => Promise<CallToolResult> {
  return async (gunkId, input) => {
    const db = openDatabase();

    let request: RunRequest;
    try {
      const gunk = getGunk(db, gunkId);

      if (!gunk || !gunk.bundlePath) {
        return toolError(`Gunk not found: ${gunkId}`);
      }

      const manifest = readManifest(gunk.bundlePath) ?? "";
      request = {
        gunkId,
        bundlePath: gunk.bundlePath,
        language: gunk.language ?? "",
        entrypoints: parseEntrypoints(manifest),
        dependencies: parseRequirementPackages(manifest),
        arguments: input ?? [],
      };
    } finally {
      db.close();
    }

    const response = await invokeRunner(request);

    if (response.error) {
      return toolError(response.error);
    }

    // Defense in depth (ADR-0017): an agent run must never execute under the
    // weaker reduced-isolation fallback. If a receipt claims it did, refuse it
    // rather than presenting evidence earned outside the promised sandbox.
    if (response.isolation === "reduced-fallback") {
      return toolError(
        "Refusing the receipt: an agent run must not execute under reduced isolation.",
      );
    }

    return {
      content: [
        {
          type: "text",
          text: JSON.stringify(receipt(response)),
        },
      ],
    };
  };
}

/** The agent-facing receipt — the buffered pass/fail evidence (ADR-0017 §3). */
function receipt(response: RunnerResponse): Record<string, unknown> {
  const stdout = response.stdout ?? "";
  const stderr = response.stderr ?? "";
  return {
    gunkId: response.gunkId ?? null,
    passed: response.passed ?? false,
    runnability: response.runnability ?? "cannot-determine",
    isolation: response.isolation ?? "not-run",
    exitCode: response.exitCode ?? null,
    durationMs: response.durationMs ?? 0,
    timedOut: response.timedOut ?? false,
    command: response.command ?? null,
    stdout,
    stderr,
    output: [stdout, stderr].filter((part) => part.length > 0).join("\n"),
  };
}

function toolError(message: string): CallToolResult {
  return {
    isError: true,
    content: [{ type: "text", text: message }],
  };
}
