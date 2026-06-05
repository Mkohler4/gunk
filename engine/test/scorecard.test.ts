import { describe, expect, it } from "vitest";

import type { Module } from "../src/models.js";
import type { RunTrace } from "../src/trace/trace.js";
import {
  assertSignalFloor,
  score,
  signalMetrics,
  summary,
  type ExpectedDecomposition,
} from "../src/eval/scorecard.js";

function module(partial: Pick<Module, "name" | "tags" | "files"> & { confidence?: number }): Module {
  return {
    name: partial.name,
    purpose: null,
    tags: partial.tags,
    files: partial.files,
    language: "typeScript",
    confidence: partial.confidence ?? 0.9,
    ownedFiles: partial.files,
    sharedDeps: [],
    surface: [],
    anchors: [],
  };
}

describe("DecompositionEval scorer", () => {
  it("scores file membership precision/recall and tag accuracy", () => {
    const expected: ExpectedDecomposition = {
      modules: [
        { name: "Google OAuth login", tags: ["auth", "api"], files: ["routes/auth.ts", "services/auth.ts", "types/auth.ts"] },
      ],
      mustNotBeModules: [],
    };
    const actual = [
      module({ name: "Google OAuth login", tags: ["auth"], files: ["routes/auth.ts", "services/auth.ts", "services/session.ts"] }),
    ];
    const card = score(actual, expected);
    expect(card.filePrecision).toBeCloseTo(2 / 3, 5);
    expect(card.fileRecall).toBeCloseTo(2 / 3, 5);
    expect(card.tagAccuracy).toBeCloseTo(0.5, 5);
    expect(card.moduleCountDelta).toBe(0);
  });

  it("counts trivial-module false positives", () => {
    const expected: ExpectedDecomposition = {
      modules: [],
      mustNotBeModules: ["src/types.ts", "src/utils/"],
    };
    const actual = [
      module({ name: "types", tags: [], files: ["src/types.ts"] }),
      module({ name: "utils", tags: [], files: ["src/utils/format.ts"] }),
      module({ name: "auth-with-types", tags: ["auth"], files: ["src/auth/service.ts", "src/types.ts"] }),
    ];
    const card = score(actual, expected);
    expect(card.trivialModuleFalsePositiveCount).toBe(2);
    expect(card.trivialModuleFalsePositiveRate).toBeCloseTo(1, 5);
  });

  it("renders a summary block", () => {
    const card = score([], { modules: [], mustNotBeModules: [] });
    expect(summary(card)).toContain("file_precision: 0.00");
  });
});

function trace(partial: Partial<RunTrace>): RunTrace {
  return {
    runId: "run-1",
    sourceId: 1,
    sourceName: "fixture",
    provider: "OpenAI",
    model: "gpt",
    startedAtMs: 0,
    finishedAtMs: 10,
    status: "succeeded",
    error: null,
    stages: [],
    llmCalls: [],
    hypotheses: [],
    expansions: [],
    refinements: [],
    gateEvaluations: [],
    summary: { accepted: 0, needsApproval: 0, rejected: 0, gunkIds: [] },
    ...partial,
  };
}

describe("SignalMetrics", () => {
  it("computes parse-coverage from a trace", () => {
    const metrics = signalMetrics(
      trace({
        stages: [
          {
            stage: "symbols",
            startedAtMs: 0,
            finishedAtMs: 1,
            durationMs: 1,
            counts: { files: 10, parsedFiles: 4, fallbackFiles: 6, realSymbolFiles: 3 },
            status: "ok",
          },
          {
            stage: "graph",
            startedAtMs: 1,
            finishedAtMs: 2,
            durationMs: 1,
            counts: { nodes: 12, edges: 6 },
            status: "ok",
          },
          {
            stage: "survey",
            startedAtMs: 2,
            finishedAtMs: 3,
            durationMs: 1,
            counts: { hypotheses: 2 },
            status: "ok",
          },
        ],
        expansions: [
          {
            hypothesis: {
              name: "Auth",
              rationale: "auth files",
              anchors: ["auth"],
              seedFiles: ["src/auth.ts"],
              expectedCollaborators: [],
              granularity: "feature",
              priority: "normal",
            },
            closureFiles: ["src/auth.ts", "src/session.ts", "src/types.ts"],
            ownedFiles: ["src/auth.ts", "src/session.ts"],
            sharedDependencyFiles: ["src/types.ts"],
            excludedFiles: [],
            edgeEvidence: [],
          },
          {
            hypothesis: {
              name: "Billing",
              rationale: "billing files",
              anchors: ["stripe"],
              seedFiles: ["src/billing.ts"],
              expectedCollaborators: [],
              granularity: "feature",
              priority: "normal",
            },
            closureFiles: ["src/billing.ts"],
            ownedFiles: ["src/billing.ts"],
            sharedDependencyFiles: [],
            excludedFiles: [],
            edgeEvidence: [],
          },
        ],
      }),
    );

    expect(metrics.totalSymbolFiles).toBe(10);
    expect(metrics.parsedFiles).toBe(4);
    expect(metrics.fallbackFiles).toBe(6);
    expect(metrics.realSymbolFiles).toBe(3);
    expect(metrics.parseCoverage).toBeCloseTo(0.3, 5);
    expect(metrics.graphEdgeDensity).toBeCloseTo(0.5, 5);
    expect(metrics.surveyHypothesisCount).toBe(2);
    expect(metrics.meanExpansionClosureSize).toBe(2);
    expect(metrics.medianExpansionClosureSize).toBe(2);
  });

  it("builds a gate-rejection histogram", () => {
    const metrics = signalMetrics(
      trace({
        gateEvaluations: [
          { name: "types", decision: "rejected", reasons: ["typeOnly"], cohesionScore: null },
          { name: "util", decision: "rejected", reasons: ["utilityOnly", "missingSurface"], cohesionScore: 0.1 },
          { name: "auth", decision: "accepted", reasons: ["missingSurface"], cohesionScore: 0.8 },
        ],
      }),
    );

    expect(metrics.gateRejectionHistogram).toEqual({
      missingSurface: 1,
      typeOnly: 1,
      utilityOnly: 1,
    });
  });

  it("assertSignalFloor throws below the floor", () => {
    const metrics = signalMetrics(
      trace({
        stages: [
          {
            stage: "symbols",
            startedAtMs: 0,
            finishedAtMs: 1,
            durationMs: 1,
            counts: { files: 10, parsedFiles: 0, fallbackFiles: 10, realSymbolFiles: 0 },
            status: "ok",
          },
          {
            stage: "graph",
            startedAtMs: 1,
            finishedAtMs: 2,
            durationMs: 1,
            counts: { nodes: 10, edges: 0 },
            status: "ok",
          },
          {
            stage: "survey",
            startedAtMs: 2,
            finishedAtMs: 3,
            durationMs: 1,
            counts: { hypotheses: 0 },
            status: "ok",
          },
        ],
      }),
    );

    expect(() =>
      assertSignalFloor(metrics, {
        minParseCoverage: 0.1,
        minGraphEdgeDensity: 0.1,
        minSurveyHypotheses: 1,
      }),
    ).toThrow(/parseCoverage.*graphEdgeDensity.*surveyHypothesisCount/);
  });
});
