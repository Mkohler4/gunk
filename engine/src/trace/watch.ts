// `gunk-engine watch`: a live tail viewer for a decomposition run. It attaches
// to the active run (or waits for the next one to start), follows its
// live.jsonl, and pretty-prints every step in real time — stage transitions and
// the full prompt + raw response of every LLM call. This is the "watch the AI
// think" debugging surface; run it in a terminal while the app (or CLI)
// processes a folder.

import {
  closeSync,
  existsSync,
  fstatSync,
  openSync,
  readdirSync,
  readSync,
  readFileSync,
  statSync,
} from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import type { LiveEvent } from "./liveLog.js";

export interface WatchCliArgs {
  target: string | undefined;
  gunkHome: string;
  full: boolean;
  follow: boolean;
  promptLimit: number;
  responseLimit: number;
}

export function parseWatchArgs(argv: string[]): WatchCliArgs {
  const positional: string[] = [];
  const flags = new Map<string, string>();
  const booleans = new Set<string>();
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      if (key === "full" || key === "no-follow") booleans.add(key);
      else flags.set(key, argv[++i] ?? "");
    } else {
      positional.push(arg);
    }
  }
  const full = booleans.has("full");
  return {
    target: positional[0],
    gunkHome: flags.get("gunk-home") ?? join(homedir(), ".gunk"),
    full,
    follow: !booleans.has("no-follow"),
    promptLimit: full ? Number.POSITIVE_INFINITY : Number(flags.get("prompt-limit") ?? 800),
    responseLimit: full ? Number.POSITIVE_INFINITY : Number(flags.get("response-limit") ?? 4000),
  };
}

const sleep = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));

function newestRunDir(runsDir: string): { dir: string; mtimeMs: number } | null {
  if (!existsSync(runsDir)) return null;
  const runs = readdirSync(runsDir)
    .map((name) => join(runsDir, name))
    .filter((path) => {
      try {
        return statSync(path).isDirectory() && existsSync(join(path, "live.jsonl"));
      } catch {
        return false;
      }
    })
    .map((dir) => ({ dir, mtimeMs: statSync(join(dir, "live.jsonl")).mtimeMs }))
    .sort((a, b) => b.mtimeMs - a.mtimeMs);
  return runs[0] ?? null;
}

function runIsFinished(logPath: string): boolean {
  try {
    const text = readFileSync(logPath, "utf8");
    return text.includes('"kind":"run.finished"') || text.includes('"kind":"run.failed"');
  } catch {
    return false;
  }
}

/**
 * Resolve the live.jsonl to follow. With an explicit target, point straight at
 * it. Without one, attach to an in-flight run if there is one, otherwise wait
 * for the next run to begin (so you can start `watch` first, then process).
 */
async function resolveLogPath(args: WatchCliArgs, log: (s: string) => void): Promise<string> {
  const runsDir = join(args.gunkHome, "runs");

  if (args.target) {
    let path = args.target;
    if (existsSync(path) && statSync(path).isDirectory()) path = join(path, "live.jsonl");
    else if (!existsSync(path)) path = join(runsDir, args.target, "live.jsonl");
    if (!args.follow && !existsSync(path)) {
      throw new Error(`No live log at ${path}.`);
    }
    while (!existsSync(path)) {
      log(`waiting for ${path} …`);
      await sleep(400);
    }
    return path;
  }

  const baseline = newestRunDir(runsDir);
  if (baseline && !runIsFinished(join(baseline.dir, "live.jsonl"))) {
    return join(baseline.dir, "live.jsonl");
  }
  if (!args.follow) {
    if (!baseline) throw new Error(`No runs found under ${runsDir}. Run the engine with --trace first.`);
    return join(baseline.dir, "live.jsonl");
  }

  const baselineMtime = baseline?.mtimeMs ?? 0;
  log("waiting for a run to start … (process a folder in the app or run the engine with --trace)");
  for (;;) {
    const newest = newestRunDir(runsDir);
    if (newest && newest.mtimeMs > baselineMtime) {
      return join(newest.dir, "live.jsonl");
    }
    await sleep(400);
  }
}

function indent(text: string, prefix = "    "): string {
  return text
    .split("\n")
    .map((line) => prefix + line)
    .join("\n");
}

function truncate(text: string, limit: number): string {
  if (text.length <= limit) return text;
  return `${text.slice(0, limit)}\n… (+${text.length - limit} more chars; use --full)`;
}

function fmtTokens(input: number | null, output: number | null): string {
  return `in ${input ?? "?"} / out ${output ?? "?"} tok`;
}

function fmtDuration(ms: number): string {
  return ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`;
}

export function formatLiveEvent(event: LiveEvent, args: Pick<WatchCliArgs, "promptLimit" | "responseLimit">): string {
  switch (event.kind) {
    case "run.started":
      return [
        "",
        `══════════════════════════════════════════════════════════════`,
        ` RUN ${event.runId}`,
        ` ${event.sourceName}  ·  ${event.provider}/${event.model}`,
        `══════════════════════════════════════════════════════════════`,
      ].join("\n");
    case "stage.started":
      return `→ ${event.stage}`;
    case "stage.finished": {
      const glyph = event.status === "ok" ? "✓" : "✗";
      const counts = Object.entries(event.counts)
        .map(([k, v]) => `${k} ${v}`)
        .join(" · ");
      const err = event.error ? `  ↳ ${event.error}` : "";
      return `${glyph} ${event.stage} (${fmtDuration(event.durationMs)})  ${counts}${err}`;
    }
    case "survey":
      return `  survey → ${event.count} hypotheses: ${event.names.join(", ") || "(none)"}`;
    case "expansion":
      return `  expansion → ${event.count} closures`;
    case "refine": {
      const glyph = event.accepted ? "✓" : "✗";
      const detail = event.accepted
        ? `confidence ${event.confidence?.toFixed(2) ?? "?"}`
        : `reject: ${event.rejectReason ?? "no reason"}`;
      return `  refine ${glyph} ${event.capability} — ${detail}`;
    }
    case "gates":
      return [
        "  quality gates:",
        ...event.evaluations.map((e) => {
          const g = e.decision === "accepted" ? "✓" : e.decision === "needsApproval" ? "~" : "✗";
          const reasons = e.reasons.length ? ` [${e.reasons.join(", ")}]` : "";
          return `    ${g} ${e.decision}  ${e.name}${reasons}`;
        }),
      ].join("\n");
    case "selfContainment": {
      const fails = event.results.filter((r) => r.imports === "fail" || r.entrypoint === "fail");
      if (fails.length === 0) return `  self-containment: all ${event.results.length} ok`;
      return [
        "  self-containment failures:",
        ...fails.map((r) => `    ✗ ${r.name} (imports ${r.imports}, entrypoint ${r.entrypoint}, ${r.danglingImports} dangling, ${r.missingEntrypoints} missing)`),
      ].join("\n");
    }
    case "build":
      return [
        "  build verification:",
        ...event.results.map((r) => `    ${r.skipped ? "—" : r.built ? "✓" : "✗"} ${r.language}  ${r.bundlePath}`),
      ].join("\n");
    case "llm.call": {
      const lines: string[] = [];
      lines.push(`┌─ LLM ${event.stage} · ${event.provider}/${event.model} · ${fmtDuration(event.durationMs)} · ${fmtTokens(event.inputTokens, event.outputTokens)}`);
      for (const message of event.requestMessages ?? []) {
        lines.push(`│ PROMPT (${message.role}):`);
        lines.push(indent(truncate(message.content, args.promptLimit)));
      }
      lines.push("│ RESPONSE:");
      const response = typeof event.responseJson === "string" ? event.responseJson : JSON.stringify(event.responseJson, null, 2);
      lines.push(indent(truncate(response, args.responseLimit)));
      lines.push("└─");
      return lines.join("\n");
    }
    case "run.finished":
      return [
        `RESULT — accepted ${event.summary.accepted} · needsApproval ${event.summary.needsApproval} · rejected ${event.summary.rejected}`,
        `gunkIds: ${event.summary.gunkIds.join(", ") || "(none)"}`,
      ].join("\n");
    case "run.failed":
      return `✗ RUN FAILED — ${event.error}`;
    default:
      return JSON.stringify(event);
  }
}

/** Follow a live log, printing each event until the run ends (or once if --no-follow). */
export async function runWatchCli(
  argv: string[],
  out: (line: string) => void = (line) => process.stdout.write(`${line}\n`),
): Promise<void> {
  const args = parseWatchArgs(argv);
  const logPath = await resolveLogPath(args, out);
  out(`tailing ${logPath}`);

  let offset = 0;
  let pending = "";
  let finished = false;

  const drain = (): void => {
    const fd = openSync(logPath, "r");
    try {
      const size = fstatSync(fd).size;
      if (size > offset) {
        const length = size - offset;
        const buffer = Buffer.alloc(length);
        readSync(fd, buffer, 0, length, offset);
        offset = size;
        pending += buffer.toString("utf8");
        let newlineIndex = pending.indexOf("\n");
        while (newlineIndex !== -1) {
          const line = pending.slice(0, newlineIndex).trim();
          pending = pending.slice(newlineIndex + 1);
          if (line.length > 0) {
            try {
              const event = JSON.parse(line) as LiveEvent;
              out(formatLiveEvent(event, args));
              if (event.kind === "run.finished" || event.kind === "run.failed") finished = true;
            } catch {
              out(`(unparsed) ${line}`);
            }
          }
          newlineIndex = pending.indexOf("\n");
        }
      }
    } finally {
      closeSync(fd);
    }
  };

  drain();
  if (!args.follow) return;
  while (!finished) {
    await sleep(250);
    drain();
  }
}
