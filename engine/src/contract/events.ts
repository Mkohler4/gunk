// NDJSON event protocol emitted on stdout for host UIs (Swift app, Windows app).
// One JSON object per line. This is the control/telemetry half of the
// cross-language contract; durable state lives in the SQLite store.

export type PipelineStage =
  | "scan"
  | "symbols"
  | "graph"
  | "fingerprints"
  | "repoMap"
  | "survey"
  | "expansion"
  | "refine"
  | "qualityGates"
  | "persist"
  | "extract";

export const PIPELINE_STAGES: PipelineStage[] = [
  "scan",
  "symbols",
  "graph",
  "fingerprints",
  "repoMap",
  "survey",
  "expansion",
  "refine",
  "qualityGates",
  "persist",
  "extract",
];

export interface ProgressEvent {
  type: "progress";
  stage: PipelineStage;
  fraction: number;
  modulesFound: number | null;
}

export interface StageEvent {
  type: "stage";
  stage: PipelineStage;
  phase: "started" | "finished";
  durationMs?: number;
  counts?: Record<string, number>;
}

export interface ResultEvent {
  type: "result";
  runId: string;
  gunkIds: number[];
  accepted: number;
  needsApproval: number;
  rejected: number;
  tracePath: string | null;
}

export interface ErrorEvent {
  type: "error";
  message: string;
  stage?: PipelineStage;
}

export type EngineEvent = ProgressEvent | StageEvent | ResultEvent | ErrorEvent;

export interface EventSink {
  emit(event: EngineEvent): void;
}

/** Writes NDJSON events to a stream (stdout by default). */
export class NdjsonEventSink implements EventSink {
  constructor(private readonly write: (line: string) => void = (line) => process.stdout.write(line)) {}

  emit(event: EngineEvent): void {
    this.write(`${JSON.stringify(event)}\n`);
  }
}

/** Drops all events (used when the engine runs without a host UI). */
export class NullEventSink implements EventSink {
  emit(): void {
    // intentionally empty
  }
}
