import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";

import {
  buildDigest,
  formatDigest,
  formatStagePrompts,
  loadTrace,
  resolveTracePath,
} from "../src/trace/digest.js";
import type { RunTrace } from "../src/trace/trace.js";

const fixturesDir = join(dirname(fileURLToPath(import.meta.url)), "fixtures");

function loadFixtureTrace(name: string): RunTrace {
  return loadTrace(join(fixturesDir, name, "recorded-trace.json"));
}

describe("buildDigest", () => {
  it("builds a full-funnel digest from a recorded trace", () => {
    const report = buildDigest(loadFixtureTrace("express-saas"));

    expect(report.sourceName).toBe("express-saas");
    expect(report.funnel).toHaveLength(11);
    const scan = report.funnel.find((row) => row.stage === "scan");
    expect(scan?.counts.files).toBe(12);
    const symbols = report.funnel.find((row) => row.stage === "symbols");
    expect(symbols?.summary).toContain("10/12 parsed");
    // survived hypotheses come straight from trace.hypotheses
    expect(report.survey.survived).toBe(report.survey.hypotheses.length);
    expect(report.summary).toBeDefined();
  });

  it("flags a sparse graph with zero edges as a warning", () => {
    const trace: RunTrace = {
      runId: "synthetic-sparse",
      sourceId: 1,
      sourceName: "sparse",
      provider: "OpenAI",
      model: "test",
      startedAtMs: 0,
      finishedAtMs: 10,
      status: "succeeded",
      error: null,
      stages: [
        { stage: "scan", startedAtMs: 0, finishedAtMs: 1, durationMs: 1, counts: { files: 20 }, status: "ok" },
        { stage: "graph", startedAtMs: 1, finishedAtMs: 2, durationMs: 1, counts: { nodes: 20, edges: 0 }, status: "ok" },
      ],
      llmCalls: [],
      hypotheses: [],
      expansions: [],
      refinements: [],
      gateEvaluations: [],
      verification: { build: [], selfContainment: [] },
      summary: { accepted: 0, needsApproval: 0, rejected: 0, gunkIds: [] },
    };

    const report = buildDigest(trace);
    const graphWarning = report.warnings.find((w) => w.stage === "graph");
    expect(graphWarning?.message).toContain("0 edges");
    // No hypotheses survived on a non-empty repo -> survey warning too.
    expect(report.warnings.some((w) => w.stage === "survey")).toBe(true);
  });

  it("detects dropped survey hypotheses by comparing llm response to survivors", () => {
    const trace: RunTrace = {
      runId: "synthetic-drop",
      sourceId: 1,
      sourceName: "drop",
      provider: "OpenAI",
      model: "test",
      startedAtMs: 0,
      finishedAtMs: 10,
      status: "succeeded",
      error: null,
      stages: [
        { stage: "scan", startedAtMs: 0, finishedAtMs: 1, durationMs: 1, counts: { files: 10 }, status: "ok" },
      ],
      llmCalls: [
        {
          stage: "survey",
          model: "test",
          provider: "OpenAI",
          requestMessages: [{ role: "system", content: "prompt" }],
          responseJson: { hypotheses: [{}, {}, {}] },
          inputTokens: 1,
          outputTokens: 1,
          durationMs: 5,
        },
      ],
      hypotheses: [
        {
          name: "Survivor",
          rationale: "r",
          anchors: [],
          seedFiles: ["a.ts"],
          expectedCollaborators: [],
          granularity: "feature",
          priority: "normal",
        },
      ],
      expansions: [],
      refinements: [],
      gateEvaluations: [],
      verification: { build: [], selfContainment: [] },
      summary: { accepted: 0, needsApproval: 0, rejected: 0, gunkIds: [] },
    };

    const report = buildDigest(trace);
    expect(report.survey.proposed).toBe(3);
    expect(report.survey.survived).toBe(1);
    expect(report.survey.dropped).toBe(2);
    expect(report.warnings.some((w) => w.stage === "survey" && w.message.includes("survived path filtering"))).toBe(true);
  });
});

describe("formatDigest / formatStagePrompts", () => {
  it("renders a readable text report", () => {
    const text = formatDigest(loadFixtureTrace("express-saas"));
    expect(text).toContain("gunk trace digest");
    expect(text).toContain("SIGNAL FUNNEL");
    expect(text).toContain("RESULT —");
  });

  it("dumps verbatim prompt + response for a stage", () => {
    const trace = loadFixtureTrace("express-saas");
    const text = formatStagePrompts(trace, "survey");
    // Either there are recorded survey calls, or it reports none cleanly.
    expect(text.length).toBeGreaterThan(0);
  });
});

describe("resolveTracePath", () => {
  let gunkHome: string;

  afterEach(() => {
    if (gunkHome) rmSync(gunkHome, { recursive: true, force: true });
  });

  it("resolves the latest run when no target is given", () => {
    gunkHome = mkdtempSync(join(tmpdir(), "gunk-home-"));
    const runsDir = join(gunkHome, "runs");
    const older = join(runsDir, "run-old");
    const newer = join(runsDir, "run-new");
    mkdirSync(older, { recursive: true });
    mkdirSync(newer, { recursive: true });
    writeFileSync(join(older, "trace.json"), "{}");
    writeFileSync(join(newer, "trace.json"), "{}");

    const resolved = resolveTracePath(undefined, gunkHome);
    // newer was written last, so it should win by mtime
    expect(resolved).toBe(join(newer, "trace.json"));
  });

  it("resolves a runId under the runs directory", () => {
    gunkHome = mkdtempSync(join(tmpdir(), "gunk-home-"));
    const runDir = join(gunkHome, "runs", "my-run");
    mkdirSync(runDir, { recursive: true });
    writeFileSync(join(runDir, "trace.json"), "{}");

    expect(resolveTracePath("my-run", gunkHome)).toBe(join(runDir, "trace.json"));
  });
});
