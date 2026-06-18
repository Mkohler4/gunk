// Trace digest: turn a verbose ~/.gunk/runs/<runId>/trace.json into a one-screen,
// symptom-oriented report. This is the "see what the engine did" tool — it shows
// the signal funnel (files -> edges -> hypotheses -> modules -> accepted), the
// survey/refine/gate decisions, self-containment failures, and heuristic
// warnings that point at the likely failing stage. Pure functions so it can be
// unit-tested against the recorded-trace.json fixtures.

import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import type { PipelineStage } from "../contract/events.js";
import { PIPELINE_STAGES } from "../contract/events.js";
import type { RunTrace, StageRecord } from "./trace.js";

export interface DigestWarning {
  /** Stage most likely responsible, for jump-to-source. */
  stage: PipelineStage | "run";
  message: string;
}

export interface DigestFunnelRow {
  stage: PipelineStage;
  durationMs: number | null;
  status: "ok" | "error" | "missing";
  /** Human-readable one-line summary of this stage's counts. */
  summary: string;
  counts: Record<string, number>;
  error?: string;
}

export interface DigestReport {
  runId: string;
  sourceName: string;
  provider: string;
  model: string;
  status: RunTrace["status"];
  error: string | null;
  durationMs: number | null;
  funnel: DigestFunnelRow[];
  survey: {
    survived: number;
    proposed: number;
    dropped: number;
    hypotheses: { name: string; priority: string; seeds: string[] }[];
  };
  refine: { capability: string; accepted: boolean; rejectReason: string | null; confidence: number | null }[];
  gates: { name: string; decision: string; reasons: string[]; cohesion: number | null }[];
  selfContainmentFailures: {
    name: string;
    imports: string;
    entrypoint: string;
    dangling: string[];
    missingEntrypoints: string[];
  }[];
  summary: RunTrace["summary"];
  warnings: DigestWarning[];
}

/**
 * Resolve a CLI target into a trace.json path.
 * Accepts: a direct path to trace.json, a run directory, a runId, or nothing
 * (in which case the most recently modified run under <gunkHome>/runs is used).
 */
export function resolveTracePath(target: string | undefined, gunkHome: string): string {
  const runsDir = join(gunkHome, "runs");

  if (target) {
    if (existsSync(target) && statSync(target).isFile()) return target;
    const asDir = existsSync(target) && statSync(target).isDirectory() ? target : null;
    if (asDir) return join(asDir, "trace.json");
    // Treat as a runId under runsDir.
    const candidate = join(runsDir, target, "trace.json");
    if (existsSync(candidate)) return candidate;
    throw new Error(`No trace found for "${target}" (looked for a file, directory, or runId under ${runsDir}).`);
  }

  if (!existsSync(runsDir)) {
    throw new Error(`No runs directory at ${runsDir}. Run the engine with --trace first.`);
  }
  const runs = readdirSync(runsDir)
    .map((name) => join(runsDir, name))
    .filter((path) => existsSync(join(path, "trace.json")))
    .map((path) => ({ path, mtimeMs: statSync(join(path, "trace.json")).mtimeMs }))
    .sort((a, b) => b.mtimeMs - a.mtimeMs);
  if (runs.length === 0) {
    throw new Error(`No trace.json found under ${runsDir}. Run the engine with --trace first.`);
  }
  return join(runs[0].path, "trace.json");
}

export function loadTrace(path: string): RunTrace {
  return JSON.parse(readFileSync(path, "utf8")) as RunTrace;
}

function stageSummary(stage: PipelineStage, counts: Record<string, number>): string {
  const n = (key: string): number => counts[key] ?? 0;
  switch (stage) {
    case "scan":
      return `${n("files")} files`;
    case "symbols":
      return `${n("parsedFiles")}/${n("files")} parsed (${n("fallbackFiles")} fallback, ${n("realSymbolFiles")} with symbols)`;
    case "graph":
      return `${n("nodes")} nodes · ${n("edges")} edges`;
    case "fingerprints":
      return `${n("fingerprints")} fingerprints`;
    case "repoMap":
      return `${n("chars")} chars · ${n("chunks")} chunk(s)`;
    case "survey":
      return `${n("hypotheses")} hypotheses`;
    case "expansion":
      return `${n("expansions")} expansions`;
    case "refine":
      return `${n("modules")} modules`;
    case "qualityGates":
      return `${n("accepted")} accepted · ${n("needsApproval")} needsApproval · ${n("rejected")} rejected`;
    case "persist":
      return `${n("persisted")} persisted`;
    case "extract":
      return `${n("extracted")} extracted`;
    default:
      return Object.entries(counts)
        .map(([k, v]) => `${k} ${v}`)
        .join(" · ");
  }
}

/** Largest hypothesis set the model returned (approximates the pre-filter proposal). */
function surveyProposedCount(trace: RunTrace): number {
  let max = 0;
  for (const call of trace.llmCalls ?? []) {
    if (call.stage !== "survey") continue;
    const json = call.responseJson as { hypotheses?: unknown[] } | null;
    const len = Array.isArray(json?.hypotheses) ? json!.hypotheses!.length : 0;
    if (len > max) max = len;
  }
  return max;
}

function computeWarnings(trace: RunTrace, report: Omit<DigestReport, "warnings">): DigestWarning[] {
  const warnings: DigestWarning[] = [];
  const byStage = new Map(trace.stages.map((s) => [s.stage, s]));
  const count = (stage: PipelineStage, key: string): number => byStage.get(stage)?.counts?.[key] ?? 0;

  if (trace.status === "failed") {
    warnings.push({ stage: "run", message: `Run failed: ${trace.error ?? "unknown error"}` });
  }
  for (const s of trace.stages) {
    if (s.status === "error") {
      warnings.push({ stage: s.stage, message: `Stage "${s.stage}" errored: ${s.error ?? "unknown"}` });
    }
  }

  const files = count("scan", "files");
  const edges = count("graph", "edges");
  if (files >= 5 && edges === 0) {
    warnings.push({ stage: "graph", message: `${files} files scanned but the code graph has 0 edges — import resolution likely failed (aliases/monorepo/unsupported language). Expansion can't pull collaborators.` });
  } else if (files >= 8 && edges > 0 && edges < files) {
    warnings.push({ stage: "graph", message: `Sparse graph (${edges} edges over ${files} files) — closures may be thin and modules may be rejected as lowCohesion.` });
  }

  if (report.survey.dropped > 0) {
    warnings.push({ stage: "survey", message: `Survey: model proposed ~${report.survey.proposed} hypotheses, only ${report.survey.survived} survived path filtering. Likely hallucinated/mismatched seed or collaborator paths (compare llmCalls[survey] vs hypotheses).` });
  }
  if (report.survey.survived === 0 && files > 0) {
    warnings.push({ stage: "survey", message: `No hypotheses survived — pass 2 has nothing to refine. Check the repo map (repoMap chars/chunks) and survey response.` });
  }

  const refineRejected = report.refine.filter((r) => !r.accepted).length;
  if (report.refine.length > 0 && refineRejected === report.refine.length) {
    warnings.push({ stage: "refine", message: `All ${report.refine.length} refinements rejected — check reject reasons and whether closures were too thin.` });
  }

  const lowCohesion = report.gates.filter((g) => g.decision === "rejected" && g.reasons.includes("lowCohesion")).length;
  if (lowCohesion > 0) {
    warnings.push({ stage: "qualityGates", message: `${lowCohesion} module(s) rejected for lowCohesion — usually a sparse graph upstream, not a bad module.` });
  }
  if (report.selfContainmentFailures.length > 0) {
    warnings.push({ stage: "qualityGates", message: `${report.selfContainmentFailures.length} module(s) failed self-containment (dangling internal imports or missing entrypoints).` });
  }

  if (report.summary.accepted === 0 && report.survey.survived > 0) {
    warnings.push({ stage: "qualityGates", message: `0 modules accepted despite ${report.survey.survived} hypotheses — the signal was lost between survey and the quality gate.` });
  }

  return warnings;
}

export function buildDigest(trace: RunTrace): DigestReport {
  const byStage = new Map((trace.stages ?? []).map((s) => [s.stage, s]));
  const funnel: DigestFunnelRow[] = PIPELINE_STAGES.map((stage) => {
    const record: StageRecord | undefined = byStage.get(stage);
    if (!record) {
      return { stage, durationMs: null, status: "missing" as const, summary: "(not reached)", counts: {} };
    }
    return {
      stage,
      durationMs: record.durationMs,
      status: record.status,
      summary: stageSummary(stage, record.counts ?? {}),
      counts: record.counts ?? {},
      ...(record.error ? { error: record.error } : {}),
    };
  });

  const survived = trace.hypotheses?.length ?? 0;
  const proposed = Math.max(surveyProposedCount(trace), survived);
  const survey = {
    survived,
    proposed,
    dropped: Math.max(proposed - survived, 0),
    hypotheses: (trace.hypotheses ?? []).map((h) => ({
      name: h.name,
      priority: h.priority,
      seeds: h.seedFiles ?? [],
    })),
  };

  const refine = (trace.refinements ?? []).map((r) => ({
    capability: r.capability,
    accepted: r.accepted,
    rejectReason: r.rejectReason,
    confidence: r.module?.confidence ?? null,
  }));

  const gates = (trace.gateEvaluations ?? []).map((g) => ({
    name: g.name,
    decision: g.decision,
    reasons: g.reasons ?? [],
    cohesion: g.cohesionScore,
  }));

  const selfContainmentFailures = (trace.verification?.selfContainment ?? [])
    .filter((s) => s.imports === "fail" || s.entrypoint === "fail")
    .map((s) => ({
      name: s.moduleName,
      imports: s.imports,
      entrypoint: s.entrypoint,
      dangling: (s.danglingImports ?? []).map((d) => `${d.moduleSpecifier ?? d.resolvedTarget ?? "?"} (${d.reason})`),
      missingEntrypoints: (s.missingEntrypoints ?? []).map((m) => `${m.path}${m.symbol ? `#${m.symbol}` : ""} (${m.reason})`),
    }));

  const durationMs =
    trace.finishedAtMs != null && trace.startedAtMs != null
      ? trace.finishedAtMs - trace.startedAtMs
      : null;

  const partial: Omit<DigestReport, "warnings"> = {
    runId: trace.runId,
    sourceName: trace.sourceName,
    provider: trace.provider,
    model: trace.model,
    status: trace.status,
    error: trace.error,
    durationMs,
    funnel,
    survey,
    refine,
    gates,
    selfContainmentFailures,
    summary: trace.summary,
  };

  return { ...partial, warnings: computeWarnings(trace, partial) };
}

const STATUS_GLYPH: Record<string, string> = {
  ok: "✓",
  error: "✗",
  missing: "·",
};

const DECISION_GLYPH: Record<string, string> = {
  accepted: "✓",
  needsApproval: "~",
  rejected: "✗",
};

function pad(value: string, width: number): string {
  return value.length >= width ? value : value + " ".repeat(width - value.length);
}

function formatDuration(ms: number | null): string {
  if (ms == null) return "—";
  if (ms < 1000) return `${ms}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

export function formatDigest(trace: RunTrace): string {
  const report = buildDigest(trace);
  const lines: string[] = [];

  lines.push(`gunk trace digest — ${report.runId}`);
  lines.push(
    `${report.sourceName}  ·  ${report.provider}/${report.model}  ·  status: ${report.status}  ·  ${formatDuration(report.durationMs)}`,
  );
  if (report.error) lines.push(`error: ${report.error}`);
  lines.push("");

  lines.push("SIGNAL FUNNEL");
  for (const row of report.funnel) {
    const glyph = STATUS_GLYPH[row.status] ?? "·";
    const dur = row.status === "missing" ? "" : `(${formatDuration(row.durationMs)})`;
    lines.push(`  ${glyph} ${pad(row.stage, 13)} ${pad(row.summary, 48)} ${dur}`);
    if (row.error) lines.push(`      ↳ ${row.error}`);
  }
  lines.push("");

  lines.push(`SURVEY — ${report.survey.survived} hypotheses survived (model proposed ~${report.survey.proposed})`);
  for (const h of report.survey.hypotheses) {
    const tag = h.priority === "low" ? " [low]" : "";
    const seeds = h.seeds.slice(0, 4).join(", ") + (h.seeds.length > 4 ? ` +${h.seeds.length - 4}` : "");
    lines.push(`  • ${h.name}${tag}  ⟵ ${seeds || "(no seeds)"}`);
  }
  if (report.survey.hypotheses.length === 0) lines.push("  (none)");
  lines.push("");

  if (report.refine.length > 0) {
    lines.push("REFINE");
    for (const r of report.refine) {
      const glyph = r.accepted ? "✓" : "✗";
      const detail = r.accepted
        ? `confidence ${r.confidence?.toFixed(2) ?? "?"}`
        : `reject: ${r.rejectReason ?? "no reason given"}`;
      lines.push(`  ${glyph} ${pad(r.capability, 36)} ${detail}`);
    }
    lines.push("");
  }

  if (report.gates.length > 0) {
    lines.push("QUALITY GATES");
    for (const g of report.gates) {
      const glyph = DECISION_GLYPH[g.decision] ?? "·";
      const cohesion = g.cohesion != null ? `cohesion ${g.cohesion.toFixed(2)}` : "";
      const reasons = g.reasons.length > 0 ? `[${g.reasons.join(", ")}]` : "";
      lines.push(`  ${glyph} ${pad(g.decision, 13)} ${pad(g.name, 30)} ${cohesion} ${reasons}`.trimEnd());
    }
    lines.push("");
  }

  if (report.selfContainmentFailures.length > 0) {
    lines.push("SELF-CONTAINMENT FAILURES");
    for (const s of report.selfContainmentFailures) {
      lines.push(`  ✗ ${s.name}  (imports: ${s.imports}, entrypoint: ${s.entrypoint})`);
      for (const d of s.dangling) lines.push(`      dangling import: ${d}`);
      for (const m of s.missingEntrypoints) lines.push(`      missing entrypoint: ${m}`);
    }
    lines.push("");
  }

  lines.push(
    `RESULT — accepted ${report.summary?.accepted ?? 0} · needsApproval ${report.summary?.needsApproval ?? 0} · rejected ${report.summary?.rejected ?? 0}`,
  );
  lines.push("");

  if (report.warnings.length > 0) {
    lines.push("WARNINGS (likely culprits)");
    for (const w of report.warnings) {
      lines.push(`  ⚠ [${w.stage}] ${w.message}`);
    }
  } else {
    lines.push("No warnings — funnel looks healthy.");
  }

  return lines.join("\n");
}

/** Pretty-print verbatim prompt + raw response for every LLM call of a stage. */
export function formatStagePrompts(trace: RunTrace, stage: PipelineStage): string {
  const calls = (trace.llmCalls ?? []).filter((c) => c.stage === stage);
  if (calls.length === 0) return `No LLM calls recorded for stage "${stage}".`;
  const lines: string[] = [];
  calls.forEach((call, index) => {
    lines.push(`══ ${stage} call ${index + 1}/${calls.length} — ${call.provider}/${call.model} (${formatDuration(call.durationMs)}, in ${call.inputTokens ?? "?"} / out ${call.outputTokens ?? "?"} tokens)`);
    for (const message of call.requestMessages ?? []) {
      lines.push(`── ${message.role} ──`);
      lines.push(message.content);
    }
    lines.push("── response ──");
    lines.push(typeof call.responseJson === "string" ? call.responseJson : JSON.stringify(call.responseJson, null, 2));
    lines.push("");
  });
  return lines.join("\n");
}

export interface TraceCliArgs {
  target: string | undefined;
  gunkHome: string;
  json: boolean;
  showStage: PipelineStage | null;
}

function parseStage(value: string): PipelineStage {
  if ((PIPELINE_STAGES as string[]).includes(value)) return value as PipelineStage;
  throw new Error(`Unknown stage "${value}". Expected one of: ${PIPELINE_STAGES.join(", ")}`);
}

export function parseTraceArgs(argv: string[]): TraceCliArgs {
  const positional: string[] = [];
  const flags = new Map<string, string>();
  const booleans = new Set<string>();
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      if (key === "json") booleans.add(key);
      else flags.set(key, argv[++i] ?? "");
    } else {
      positional.push(arg);
    }
  }
  return {
    target: positional[0],
    gunkHome: flags.get("gunk-home") ?? join(homedir(), ".gunk"),
    json: booleans.has("json"),
    showStage: flags.has("show") ? parseStage(flags.get("show")!) : null,
  };
}

/** Entry point for the `gunk-engine trace` subcommand. */
export function runTraceCli(argv: string[]): string {
  const args = parseTraceArgs(argv);
  const path = resolveTracePath(args.target, args.gunkHome);
  const trace = loadTrace(path);
  if (args.json) return JSON.stringify(buildDigest(trace), null, 2);
  let out = formatDigest(trace);
  out += `\n\ntrace: ${path}`;
  if (args.showStage) out += `\n\n${formatStagePrompts(trace, args.showStage)}`;
  return out;
}
