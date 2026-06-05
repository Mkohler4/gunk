import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  CompositeObserver,
  LoggingObserver,
  NoopObserver,
  RunTraceRecorder,
  type RunTrace,
} from "../src/trace/trace.js";

describe("RunTraceRecorder", () => {
  let runsDir: string;

  beforeEach(() => {
    runsDir = mkdtempSync(join(tmpdir(), "gunk-runs-"));
  });

  afterEach(() => {
    rmSync(runsDir, { recursive: true, force: true });
  });

  it("accumulates and writes a trace.json on finish", () => {
    const recorder = new RunTraceRecorder(
      { runId: "run-1", sourceId: 1, sourceName: "demo", provider: "OpenAI", model: "gpt" },
      { runsDir },
    );

    recorder.stageFinished({
      stage: "scan",
      startedAtMs: 0,
      finishedAtMs: 5,
      durationMs: 5,
      counts: { files: 3 },
      status: "ok",
    });
    recorder.recordedRefinement({ capability: "auth", accepted: false, rejectReason: "type only", module: null });
    recorder.runFinished({ accepted: 1, needsApproval: 0, rejected: 1, gunkIds: [10] });

    expect(existsSync(recorder.tracePath)).toBe(true);
    const trace = JSON.parse(readFileSync(recorder.tracePath, "utf8")) as RunTrace;
    expect(trace.status).toBe("succeeded");
    expect(trace.stages).toHaveLength(1);
    expect(trace.refinements[0]?.rejectReason).toBe("type only");
    expect(trace.summary.gunkIds).toEqual([10]);
  });

  it("records failure", () => {
    const recorder = new RunTraceRecorder(
      { runId: "run-2", sourceId: 1, sourceName: "demo", provider: "OpenAI", model: "gpt" },
      { runsDir },
    );
    recorder.runFailed("boom");
    const trace = JSON.parse(readFileSync(recorder.tracePath, "utf8")) as RunTrace;
    expect(trace.status).toBe("failed");
    expect(trace.error).toBe("boom");
  });

  it("composite + noop + logging observers do not throw", () => {
    const logs: string[] = [];
    const recorder = new RunTraceRecorder(
      { runId: "run-3", sourceId: 1, sourceName: "demo", provider: "OpenAI", model: "gpt" },
      { runsDir },
    );
    const composite = new CompositeObserver([
      new NoopObserver(),
      new LoggingObserver((line) => logs.push(line)),
      recorder,
    ]);
    composite.runStarted({ runId: "run-3", sourceId: 1, sourceName: "demo", provider: "OpenAI", model: "gpt" });
    composite.stageStarted("scan");
    composite.runFinished({ accepted: 0, needsApproval: 0, rejected: 0, gunkIds: [] });
    expect(logs.some((l) => l.includes("run.started"))).toBe(true);
  });
});
