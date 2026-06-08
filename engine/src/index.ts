#!/usr/bin/env bun
// gunk-engine CLI. Headless, UI-agnostic decomposition engine.
//
//   gunk-engine <folder> --provider <openai|anthropic|ollama> --model <m>
//     [--source-id N] [--db <path>] [--gunk-home <path>] [--trace] [--json]
//     [--verify-build]
//
// Durable state -> SQLite at ~/.gunk/store.db. Telemetry -> NDJSON on stdout
// (with --json). Full trace -> ~/.gunk/runs/<runId>/trace.json (with --trace).

import { randomUUID } from "node:crypto";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";

import {
  insertSource,
  openStore,
  sourceById,
  type Source,
} from "./store/index.js";
import {
  NdjsonEventSink,
  NullEventSink,
  type EventSink,
} from "./contract/events.js";
import {
  CompositeObserver,
  LoggingObserver,
  RunTraceRecorder,
  type DecompositionObserver,
} from "./trace/trace.js";
import { defaultModel, makeClient, type LLMProvider } from "./llm/client.js";
import { makeEmbeddingProvider } from "./llm/embeddings.js";
import { DecompositionPipeline } from "./decompose/pipeline.js";
import { formatEvalReport, runEval } from "./eval/runEval.js";

interface CliArgs {
  folder: string;
  provider: LLMProvider;
  model: string;
  sourceId: number | null;
  dbPath: string;
  gunkHome: string;
  confidenceThreshold: number | null;
  contextBudgetTokens: number | null;
  trace: boolean;
  json: boolean;
  verifyBuild: boolean;
}

interface EvalCliArgs {
  fixturesDir: string;
  fixtures: string[] | null;
  json: boolean;
}

function parseProvider(value: string): LLMProvider {
  switch (value.toLowerCase()) {
    case "openai":
      return "OpenAI";
    case "anthropic":
      return "Anthropic";
    case "ollama":
      return "Ollama";
    default:
      throw new Error(
        `Unknown provider: ${value} (expected openai|anthropic|ollama)`,
      );
  }
}

function parseArgs(argv: string[]): CliArgs {
  const positional: string[] = [];
  const flags = new Map<string, string>();
  const booleans = new Set<string>();

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      if (key === "trace" || key === "json" || key === "verify-build") {
        booleans.add(key);
      } else {
        flags.set(key, argv[++i] ?? "");
      }
    } else {
      positional.push(arg);
    }
  }

  const folder = positional[0];
  if (!folder) {
    throw new Error(
      "Usage: gunk-engine <folder> --provider <p> --model <m> [--source-id N] [--db path] [--trace] [--json]",
    );
  }

  const provider = parseProvider(flags.get("provider") ?? "openai");
  const home = join(homedir(), ".gunk");
  return {
    folder: resolve(folder),
    provider,
    model: flags.get("model") || defaultModel(provider),
    sourceId: flags.has("source-id") ? Number(flags.get("source-id")) : null,
    dbPath: flags.get("db") ?? join(home, "store.db"),
    gunkHome: flags.get("gunk-home") ?? home,
    confidenceThreshold: flags.has("confidence")
      ? Number(flags.get("confidence"))
      : null,
    contextBudgetTokens: flags.has("context-budget")
      ? Number(flags.get("context-budget"))
      : null,
    trace: booleans.has("trace"),
    json: booleans.has("json"),
    verifyBuild: booleans.has("verify-build"),
  };
}

function parseEvalArgs(argv: string[]): EvalCliArgs {
  const flags = new Map<string, string>();
  const booleans = new Set<string>();

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (!arg.startsWith("--")) continue;
    const key = arg.slice(2);
    if (key === "json") {
      booleans.add(key);
    } else {
      flags.set(key, argv[++i] ?? "");
    }
  }

  return {
    fixturesDir: flags.get("fixtures-dir") ?? "test/fixtures",
    fixtures: flags.has("fixtures")
      ? (flags.get("fixtures") ?? "")
          .split(",")
          .filter((value) => value.length > 0)
      : null,
    json: booleans.has("json"),
  };
}

function apiKeyFromEnv(provider: LLMProvider): string {
  if (process.env.GUNK_API_KEY) return process.env.GUNK_API_KEY;
  switch (provider) {
    case "OpenAI":
      return process.env.OPENAI_API_KEY ?? "";
    case "Anthropic":
      return process.env.ANTHROPIC_API_KEY ?? "";
    case "Ollama":
      return "";
  }
}

async function main(): Promise<void> {
  if (process.argv[2] === "eval") {
    const args = parseEvalArgs(process.argv.slice(3));
    const report = await runEval({
      fixturesDir: args.fixturesDir,
      ...(args.fixtures ? { fixtureNames: args.fixtures } : {}),
    });
    process.stdout.write(
      args.json
        ? `${JSON.stringify(report, null, 2)}\n`
        : `${formatEvalReport(report)}\n`,
    );
    if (!report.passed) {
      process.exitCode = 1;
    }
    return;
  }

  const args = parseArgs(process.argv.slice(2));
  const events: EventSink = args.json
    ? new NdjsonEventSink()
    : new NullEventSink();
  const db = openStore(args.dbPath);

  let source: Source | null =
    args.sourceId !== null ? sourceById(db, args.sourceId) : null;
  if (!source) {
    source = insertSource(db, basename(args.folder), args.folder);
  }

  const runId = `${new Date().toISOString().replace(/[:.]/g, "-")}-${randomUUID().slice(0, 8)}`;
  const recorder = args.trace
    ? new RunTraceRecorder(
        {
          runId,
          sourceId: source.id,
          sourceName: source.name,
          provider: args.provider,
          model: args.model,
        },
        { runsDir: join(args.gunkHome, "runs") },
      )
    : null;
  const observers: DecompositionObserver[] = [new LoggingObserver()];
  if (recorder) observers.push(recorder);
  const observer = new CompositeObserver(observers);
  observer.runStarted({
    runId,
    sourceId: source.id,
    sourceName: source.name,
    provider: args.provider,
    model: args.model,
  });

  const apiKey = apiKeyFromEnv(args.provider);
  const client = makeClient(args.provider, { apiKey });
  const embeddingProvider = makeEmbeddingProvider(args.provider, { apiKey });

  try {
    const result = await new DecompositionPipeline(
      db,
      args.provider,
      args.model,
      {
        gunkHome: args.gunkHome,
        embeddingProvider,
        observer,
        eventSink: events,
        verifyBuild: args.verifyBuild,
        ...(args.confidenceThreshold !== null
          ? { confidenceThreshold: args.confidenceThreshold }
          : {}),
        ...(args.contextBudgetTokens !== null
          ? { contextBudgetTokens: args.contextBudgetTokens }
          : {}),
      },
    ).run(source, client);

    observer.runFinished({
      accepted: result.accepted,
      needsApproval: result.needsApproval,
      rejected: result.rejected,
      gunkIds: result.gunkIds,
    });
    events.emit({
      type: "result",
      runId,
      gunkIds: result.gunkIds,
      accepted: result.accepted,
      needsApproval: result.needsApproval,
      rejected: result.rejected,
      tracePath: recorder?.tracePath ?? null,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    observer.runFailed(message);
    events.emit({ type: "error", message });
    process.exitCode = 1;
  } finally {
    db.close();
  }
}

await main();
