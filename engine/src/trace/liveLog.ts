// Live log: streams every pipeline step to <runsDir>/<runId>/live.jsonl as it
// happens, one JSON object per line, flushed immediately. Unlike trace.json
// (written once at the end), this is tail-able while the run is in flight — it
// is what `gunk-engine watch` follows so you can see every stage transition and
// every LLM prompt + raw response in real time.

import { appendFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import type { PipelineStage } from "../contract/events.js";
import type {
  CapabilityExpansion,
  CapabilityHypothesis,
  QualityGateEvaluation,
} from "../models.js";
import type { BuildVerifyResult } from "../extract/buildVerify.js";
import type { SelfContainmentResult } from "../decompose/selfContainment.js";
import type {
  DecompositionObserver,
  LlmCallRecord,
  RefinementRecord,
  RunTrace,
  StageRecord,
} from "./trace.js";

/** One line of the live log. `kind` discriminates; `t` is epoch ms. */
export type LiveEvent =
  | { t: number; kind: "run.started"; runId: string; sourceName: string; provider: string; model: string }
  | { t: number; kind: "stage.started"; stage: PipelineStage }
  | { t: number; kind: "stage.finished"; stage: PipelineStage; durationMs: number; counts: Record<string, number>; status: "ok" | "error"; error?: string }
  | { t: number; kind: "survey"; count: number; names: string[] }
  | { t: number; kind: "expansion"; count: number }
  | { t: number; kind: "refine"; capability: string; accepted: boolean; rejectReason: string | null; confidence: number | null }
  | { t: number; kind: "gates"; evaluations: { name: string; decision: string; reasons: string[]; cohesion: number | null }[] }
  | { t: number; kind: "selfContainment"; results: { name: string; imports: string; entrypoint: string; danglingImports: number; missingEntrypoints: number }[] }
  | { t: number; kind: "build"; results: { bundlePath: string; language: string; built: boolean; skipped: boolean }[] }
  | { t: number; kind: "llm.call"; stage: PipelineStage; provider: string; model: string; inputTokens: number | null; outputTokens: number | null; durationMs: number; requestMessages: { role: string; content: string }[]; responseJson: unknown }
  | { t: number; kind: "run.finished"; summary: RunTrace["summary"] }
  | { t: number; kind: "run.failed"; error: string };

/** Omit that distributes over a discriminated union (so each variant keeps its keys). */
type DistributiveOmit<T, K extends keyof T> = T extends unknown ? Omit<T, K> : never;

/**
 * Observer that appends a JSONL line per event. Writes synchronously and
 * flushes each line so a tailing process sees steps immediately, including the
 * full prompt and raw response of every LLM call.
 */
export class LiveLogObserver implements DecompositionObserver {
  private readonly logPath: string;
  private readonly now: () => number;

  constructor(
    init: { runId: string; runsDir?: string; now?: () => number },
  ) {
    this.now = init.now ?? Date.now;
    const runsDir = init.runsDir ?? join(homedir(), ".gunk", "runs");
    const dir = join(runsDir, init.runId);
    mkdirSync(dir, { recursive: true });
    this.logPath = join(dir, "live.jsonl");
  }

  /** Path the live log is written to (so callers can advertise it). */
  get path(): string {
    return this.logPath;
  }

  private write(event: DistributiveOmit<LiveEvent, "t">): void {
    const line = JSON.stringify({ t: this.now(), ...event });
    appendFileSync(this.logPath, `${line}\n`);
  }

  runStarted(trace: Pick<RunTrace, "runId" | "sourceName" | "provider" | "model">): void {
    this.write({ kind: "run.started", runId: trace.runId, sourceName: trace.sourceName, provider: trace.provider, model: trace.model });
  }

  stageStarted(stage: PipelineStage): void {
    this.write({ kind: "stage.started", stage });
  }

  stageFinished(record: StageRecord): void {
    this.write({
      kind: "stage.finished",
      stage: record.stage,
      durationMs: record.durationMs,
      counts: record.counts ?? {},
      status: record.status,
      ...(record.error ? { error: record.error } : {}),
    });
  }

  recordedHypotheses(hypotheses: CapabilityHypothesis[]): void {
    this.write({ kind: "survey", count: hypotheses.length, names: hypotheses.map((h) => h.name) });
  }

  recordedExpansions(expansions: CapabilityExpansion[]): void {
    this.write({ kind: "expansion", count: expansions.length });
  }

  recordedRefinement(record: RefinementRecord): void {
    this.write({
      kind: "refine",
      capability: record.capability,
      accepted: record.accepted,
      rejectReason: record.rejectReason,
      confidence: record.module?.confidence ?? null,
    });
  }

  recordedGateEvaluations(evaluations: QualityGateEvaluation[]): void {
    this.write({
      kind: "gates",
      evaluations: evaluations.map((e) => ({
        name: e.module.name,
        decision: e.decision,
        reasons: e.reasons,
        cohesion: e.cohesionScore,
      })),
    });
  }

  recordedSelfContainment(results: SelfContainmentResult[]): void {
    this.write({
      kind: "selfContainment",
      results: results.map((r) => ({
        name: r.moduleName,
        imports: r.imports,
        entrypoint: r.entrypoint,
        danglingImports: r.danglingImports?.length ?? 0,
        missingEntrypoints: r.missingEntrypoints?.length ?? 0,
      })),
    });
  }

  recordedBuildVerification(results: BuildVerifyResult[]): void {
    this.write({
      kind: "build",
      results: results.map((r) => ({ bundlePath: r.bundlePath, language: r.language, built: r.built, skipped: r.skipped })),
    });
  }

  llmCall(record: LlmCallRecord): void {
    this.write({
      kind: "llm.call",
      stage: record.stage,
      provider: record.provider,
      model: record.model,
      inputTokens: record.inputTokens,
      outputTokens: record.outputTokens,
      durationMs: record.durationMs,
      requestMessages: record.requestMessages,
      responseJson: record.responseJson,
    });
  }

  runFinished(summary: RunTrace["summary"]): void {
    this.write({ kind: "run.finished", summary });
  }

  runFailed(error: string): void {
    this.write({ kind: "run.failed", error });
  }
}
