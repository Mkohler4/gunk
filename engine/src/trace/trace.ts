// Per-run trace: the durable, inspectable record of everything the pipeline
// did. This is the heart of "see what's going on" - every stage, decision,
// and LLM call is captured and written to ~/.gunk/runs/<runId>/trace.json.

import { mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import type { PipelineStage } from "../contract/events.js";
import type {
  CapabilityExpansion,
  CapabilityHypothesis,
  Module,
  QualityGateEvaluation,
} from "../models.js";

export interface LlmCallRecord {
  stage: PipelineStage;
  model: string;
  provider: string;
  requestMessages: { role: string; content: string }[];
  responseJson: unknown;
  inputTokens: number | null;
  outputTokens: number | null;
  durationMs: number;
}

export interface StageRecord {
  stage: PipelineStage;
  startedAtMs: number;
  finishedAtMs: number;
  durationMs: number;
  counts: Record<string, number>;
  status: "ok" | "error";
  error?: string;
}

export interface RefinementRecord {
  capability: string;
  accepted: boolean;
  rejectReason: string | null;
  module: Module | null;
}

export interface GateRecord {
  name: string;
  decision: string;
  reasons: string[];
  cohesionScore: number | null;
}

export interface RunTrace {
  runId: string;
  sourceId: number | null;
  sourceName: string;
  provider: string;
  model: string;
  startedAtMs: number;
  finishedAtMs: number | null;
  status: "running" | "succeeded" | "failed";
  error: string | null;
  stages: StageRecord[];
  llmCalls: LlmCallRecord[];
  hypotheses: CapabilityHypothesis[];
  expansions: CapabilityExpansion[];
  refinements: RefinementRecord[];
  gateEvaluations: GateRecord[];
  summary: {
    accepted: number;
    needsApproval: number;
    rejected: number;
    gunkIds: number[];
  };
}

/**
 * Observes a single decomposition run. The pipeline calls these hooks; the
 * implementation decides what to do (accumulate a trace, log, both).
 */
export interface DecompositionObserver {
  runStarted(trace: Pick<RunTrace, "runId" | "sourceId" | "sourceName" | "provider" | "model">): void;
  stageStarted(stage: PipelineStage): void;
  stageFinished(record: StageRecord): void;
  recordedHypotheses(hypotheses: CapabilityHypothesis[]): void;
  recordedExpansions(expansions: CapabilityExpansion[]): void;
  recordedRefinement(record: RefinementRecord): void;
  recordedGateEvaluations(evaluations: QualityGateEvaluation[]): void;
  llmCall(record: LlmCallRecord): void;
  runFinished(summary: RunTrace["summary"]): void;
  runFailed(error: string): void;
}

/** Default no-op observer so callers can ignore tracing entirely. */
export class NoopObserver implements DecompositionObserver {
  runStarted(): void {}
  stageStarted(): void {}
  stageFinished(): void {}
  recordedHypotheses(): void {}
  recordedExpansions(): void {}
  recordedRefinement(): void {}
  recordedGateEvaluations(): void {}
  llmCall(): void {}
  runFinished(): void {}
  runFailed(): void {}
}

/** Accumulates a RunTrace in memory and writes it to disk when the run ends. */
export class RunTraceRecorder implements DecompositionObserver {
  private trace: RunTrace;
  private readonly runsDir: string;

  constructor(
    init: Pick<RunTrace, "runId" | "sourceId" | "sourceName" | "provider" | "model">,
    options: { runsDir?: string; now?: () => number } = {},
  ) {
    this.now = options.now ?? Date.now;
    this.runsDir = options.runsDir ?? join(homedir(), ".gunk", "runs");
    this.trace = {
      ...init,
      startedAtMs: this.now(),
      finishedAtMs: null,
      status: "running",
      error: null,
      stages: [],
      llmCalls: [],
      hypotheses: [],
      expansions: [],
      refinements: [],
      gateEvaluations: [],
      summary: { accepted: 0, needsApproval: 0, rejected: 0, gunkIds: [] },
    };
  }

  private readonly now: () => number;

  get current(): RunTrace {
    return this.trace;
  }

  runStarted(): void {}

  stageStarted(): void {}

  stageFinished(record: StageRecord): void {
    this.trace.stages.push(record);
  }

  recordedHypotheses(hypotheses: CapabilityHypothesis[]): void {
    this.trace.hypotheses = hypotheses;
  }

  recordedExpansions(expansions: CapabilityExpansion[]): void {
    this.trace.expansions = expansions;
  }

  recordedRefinement(record: RefinementRecord): void {
    this.trace.refinements.push(record);
  }

  recordedGateEvaluations(evaluations: QualityGateEvaluation[]): void {
    this.trace.gateEvaluations = evaluations.map((evaluation) => ({
      name: evaluation.module.name,
      decision: evaluation.decision,
      reasons: evaluation.reasons,
      cohesionScore: evaluation.cohesionScore,
    }));
  }

  llmCall(record: LlmCallRecord): void {
    this.trace.llmCalls.push(record);
  }

  runFinished(summary: RunTrace["summary"]): void {
    this.trace.summary = summary;
    this.trace.status = "succeeded";
    this.trace.finishedAtMs = this.now();
    this.flush();
  }

  runFailed(error: string): void {
    this.trace.status = "failed";
    this.trace.error = error;
    this.trace.finishedAtMs = this.now();
    this.flush();
  }

  /** Path the trace was (or will be) written to. */
  get tracePath(): string {
    return join(this.runsDir, this.trace.runId, "trace.json");
  }

  private flush(): void {
    const dir = join(this.runsDir, this.trace.runId);
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "trace.json"), `${JSON.stringify(this.trace, null, 2)}\n`);
  }
}

/** Emits structured log lines to stderr for live visibility. */
export class LoggingObserver implements DecompositionObserver {
  constructor(private readonly log: (line: string) => void = (line) => process.stderr.write(`${line}\n`)) {}

  private line(event: string, fields: Record<string, unknown>): void {
    this.log(`[decompose] ${event} ${JSON.stringify(fields)}`);
  }

  runStarted(trace: Pick<RunTrace, "runId" | "sourceName" | "provider" | "model">): void {
    this.line("run.started", { runId: trace.runId, source: trace.sourceName, provider: trace.provider, model: trace.model });
  }

  stageStarted(stage: PipelineStage): void {
    this.line("stage.started", { stage });
  }

  stageFinished(record: StageRecord): void {
    this.line("stage.finished", { stage: record.stage, durationMs: record.durationMs, counts: record.counts, status: record.status });
  }

  recordedHypotheses(hypotheses: CapabilityHypothesis[]): void {
    this.line("survey", { count: hypotheses.length, names: hypotheses.map((h) => h.name) });
  }

  recordedExpansions(expansions: CapabilityExpansion[]): void {
    this.line("expansion", { count: expansions.length });
  }

  recordedRefinement(record: RefinementRecord): void {
    this.line("refine", { capability: record.capability, accepted: record.accepted, rejectReason: record.rejectReason });
  }

  recordedGateEvaluations(evaluations: QualityGateEvaluation[]): void {
    this.line("gates", {
      evaluations: evaluations.map((e) => ({ name: e.module.name, decision: e.decision, reasons: e.reasons })),
    });
  }

  llmCall(record: LlmCallRecord): void {
    this.line("llm.call", { stage: record.stage, model: record.model, inputTokens: record.inputTokens, outputTokens: record.outputTokens, durationMs: record.durationMs });
  }

  runFinished(summary: RunTrace["summary"]): void {
    this.line("run.finished", summary);
  }

  runFailed(error: string): void {
    this.line("run.failed", { error });
  }
}

/** Fans out observer callbacks to several observers. */
export class CompositeObserver implements DecompositionObserver {
  constructor(private readonly observers: DecompositionObserver[]) {}

  runStarted(trace: Parameters<DecompositionObserver["runStarted"]>[0]): void {
    for (const o of this.observers) o.runStarted(trace);
  }
  stageStarted(stage: PipelineStage): void {
    for (const o of this.observers) o.stageStarted(stage);
  }
  stageFinished(record: StageRecord): void {
    for (const o of this.observers) o.stageFinished(record);
  }
  recordedHypotheses(hypotheses: CapabilityHypothesis[]): void {
    for (const o of this.observers) o.recordedHypotheses(hypotheses);
  }
  recordedExpansions(expansions: CapabilityExpansion[]): void {
    for (const o of this.observers) o.recordedExpansions(expansions);
  }
  recordedRefinement(record: RefinementRecord): void {
    for (const o of this.observers) o.recordedRefinement(record);
  }
  recordedGateEvaluations(evaluations: QualityGateEvaluation[]): void {
    for (const o of this.observers) o.recordedGateEvaluations(evaluations);
  }
  llmCall(record: LlmCallRecord): void {
    for (const o of this.observers) o.llmCall(record);
  }
  runFinished(summary: RunTrace["summary"]): void {
    for (const o of this.observers) o.runFinished(summary);
  }
  runFailed(error: string): void {
    for (const o of this.observers) o.runFailed(error);
  }
}
