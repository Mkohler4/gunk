import { Database } from "bun:sqlite";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  createTreeSitterSymbolExtractor,
  type SymbolExtractor,
} from "../analyze/symbolExtractor.js";
import { DecompositionPipeline } from "../decompose/pipeline.js";
import type { Module } from "../models.js";
import {
  filesForGunk,
  gunksForSource,
  insertSource,
  listGunkTags,
  runMigrations,
} from "../store/index.js";
import { RunTraceRecorder, type RunTrace } from "../trace/trace.js";

import { ReplayClient } from "./replayClient.js";
import {
  assertSignalFloor,
  loadExpected,
  score,
  signalMetrics,
  summary,
  type Scorecard,
  type SignalFloor,
  type SignalMetrics,
} from "./scorecard.js";

export interface EvalFixtureConfig {
  name: string;
  enforcePhase4Baseline?: boolean;
  scoreFloor?: {
    minActualModules?: number;
    minFileRecall?: number;
    maxTrivialModuleFalsePositives?: number;
  };
  signalFloor: SignalFloor;
}

export interface EvalFixtureResult {
  name: string;
  scorecard: Scorecard;
  signalMetrics: SignalMetrics;
  passed: boolean;
  errors: string[];
}

export interface EvalReport {
  passed: boolean;
  fixtures: EvalFixtureResult[];
}

export const DEFAULT_EVAL_FIXTURES: EvalFixtureConfig[] = [
  {
    name: "express-saas",
    enforcePhase4Baseline: true,
    signalFloor: { minParseCoverage: 0.5, minSurveyHypotheses: 2 },
  },
  {
    name: "next-media",
    enforcePhase4Baseline: true,
    signalFloor: { minParseCoverage: 0.5, minSurveyHypotheses: 2 },
  },
  {
    name: "flutter-app",
    scoreFloor: {
      minActualModules: 2,
      minFileRecall: 0.8,
      maxTrivialModuleFalsePositives: 0,
    },
    signalFloor: { minParseCoverage: 0.6, minSurveyHypotheses: 2 },
  },
  {
    name: "kotlin-android",
    signalFloor: { minParseCoverage: 0, minSurveyHypotheses: 0 },
  },
  {
    name: "java-service",
    signalFloor: { minParseCoverage: 0, minSurveyHypotheses: 0 },
  },
  {
    name: "mixed-monorepo",
    signalFloor: { minParseCoverage: 0, minSurveyHypotheses: 0 },
  },
  {
    name: "large-repo",
    signalFloor: { minParseCoverage: 0, minSurveyHypotheses: 0 },
  },
];

const defaultFixturesDir = fileURLToPath(
  new URL("../../test/fixtures", import.meta.url),
);

function modulesForSource(db: Database, sourceId: number): Module[] {
  return gunksForSource(db, sourceId).map((gunk) => ({
    name: gunk.name,
    purpose: gunk.purpose,
    tags: listGunkTags(db, gunk.id).map((tag) => tag.tag),
    files: filesForGunk(db, gunk.id).map((file) => file.relpath),
    language: gunk.language,
    confidence: gunk.confidence ?? 0,
    ownedFiles: [],
    sharedDeps: [],
    surface: [],
    anchors: [],
  }));
}

function phase4BaselineErrors(card: Scorecard): string[] {
  const errors: string[] = [];
  if (card.filePrecision < 1)
    errors.push(`file_precision ${card.filePrecision.toFixed(2)} < 1.00`);
  if (card.fileRecall < 1)
    errors.push(`file_recall ${card.fileRecall.toFixed(2)} < 1.00`);
  if (card.tagAccuracy < 1)
    errors.push(`tag_accuracy ${card.tagAccuracy.toFixed(2)} < 1.00`);
  if (card.trivialModuleFalsePositiveCount !== 0) {
    errors.push(
      `trivial_module_false_positives ${card.trivialModuleFalsePositiveCount} != 0`,
    );
  }
  return errors;
}

function scoreFloorErrors(card: Scorecard, floor: NonNullable<EvalFixtureConfig["scoreFloor"]>): string[] {
  const errors: string[] = [];
  if (
    floor.minActualModules !== undefined &&
    card.actualModuleCount < floor.minActualModules
  ) {
    errors.push(
      `actual_modules ${card.actualModuleCount} < ${floor.minActualModules}`,
    );
  }
  if (
    floor.minFileRecall !== undefined &&
    card.fileRecall < floor.minFileRecall
  ) {
    errors.push(
      `file_recall ${card.fileRecall.toFixed(2)} < ${floor.minFileRecall.toFixed(2)}`,
    );
  }
  if (
    floor.maxTrivialModuleFalsePositives !== undefined &&
    card.trivialModuleFalsePositiveCount > floor.maxTrivialModuleFalsePositives
  ) {
    errors.push(
      `trivial_module_false_positives ${card.trivialModuleFalsePositiveCount} > ${floor.maxTrivialModuleFalsePositives}`,
    );
  }
  return errors;
}

function emptyTrace(
  name: string,
  tape: Pick<RunTrace, "provider" | "model">,
  error: string,
): RunTrace {
  return {
    runId: `eval-${name}`,
    sourceId: null,
    sourceName: name,
    provider: tape.provider,
    model: tape.model,
    startedAtMs: 0,
    finishedAtMs: 0,
    status: "failed",
    error,
    stages: [],
    llmCalls: [],
    hypotheses: [],
    expansions: [],
    refinements: [],
    gateEvaluations: [],
    summary: { accepted: 0, needsApproval: 0, rejected: 0, gunkIds: [] },
  };
}

async function runFixture(
  config: EvalFixtureConfig,
  fixturesDir: string,
  extractor: SymbolExtractor,
): Promise<EvalFixtureResult> {
  const fixturePath = join(fixturesDir, config.name);
  const expected = loadExpected(
    JSON.parse(readFileSync(join(fixturePath, "expected.json"), "utf8")),
  );
  const tapePath = join(fixturePath, "recorded-trace.json");
  const tape = JSON.parse(readFileSync(tapePath, "utf8")) as RunTrace;
  const replay = new ReplayClient(tape);
  const db = new Database(":memory:");
  const gunkHome = mkdtempSync(join(tmpdir(), "gunk-eval-home-"));
  const errors: string[] = [];

  try {
    db.exec("PRAGMA foreign_keys = ON;");
    runMigrations(db);
    const source = insertSource(db, config.name, fixturePath, 100);
    const observer = new RunTraceRecorder(
      {
        runId: `eval-${config.name}`,
        sourceId: source.id,
        sourceName: source.name,
        provider: tape.provider,
        model: tape.model,
      },
      { runsDir: join(gunkHome, "runs"), now: () => 100 },
    );
    const result = await new DecompositionPipeline(
      db,
      tape.provider,
      tape.model,
      {
        contextBudgetTokens: 4000,
        confidenceThreshold: 0.7,
        gunkHome,
        symbolExtractor: extractor,
        embeddingProvider: null,
        observer,
        now: () => 100,
      },
    ).run(source, replay);
    replay.assertExhausted();
    observer.runFinished(result);

    const scorecard = score(modulesForSource(db, source.id), expected);
    const metrics = signalMetrics(observer.current);

    try {
      assertSignalFloor(metrics, config.signalFloor);
    } catch (error) {
      errors.push(error instanceof Error ? error.message : String(error));
    }

    if (config.enforcePhase4Baseline) {
      errors.push(...phase4BaselineErrors(scorecard));
    }
    if (config.scoreFloor) {
      errors.push(...scoreFloorErrors(scorecard, config.scoreFloor));
    }

    return {
      name: config.name,
      scorecard,
      signalMetrics: metrics,
      passed: errors.length === 0,
      errors,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      name: config.name,
      scorecard: score([], expected),
      signalMetrics: signalMetrics(emptyTrace(config.name, tape, message)),
      passed: false,
      errors: [message],
    };
  } finally {
    db.close();
    rmSync(gunkHome, { recursive: true, force: true });
  }
}

export async function runEval(
  options: {
    fixturesDir?: string;
    fixtureNames?: string[];
  } = {},
): Promise<EvalReport> {
  const fixturesDir = resolve(options.fixturesDir ?? defaultFixturesDir);
  const fixtureNames = new Set(
    options.fixtureNames ??
      DEFAULT_EVAL_FIXTURES.map((fixture) => fixture.name),
  );
  const configs = DEFAULT_EVAL_FIXTURES.filter((fixture) =>
    fixtureNames.has(fixture.name),
  );
  const extractor = await createTreeSitterSymbolExtractor();
  const fixtures: EvalFixtureResult[] = [];

  for (const config of configs) {
    fixtures.push(await runFixture(config, fixturesDir, extractor));
  }

  return {
    passed: fixtures.every((fixture) => fixture.passed),
    fixtures,
  };
}

export function formatEvalReport(report: EvalReport): string {
  const lines = [`eval_status: ${report.passed ? "pass" : "fail"}`];
  for (const fixture of report.fixtures) {
    lines.push("");
    lines.push(`fixture: ${fixture.name}`);
    lines.push(`status: ${fixture.passed ? "pass" : "fail"}`);
    lines.push(summary(fixture.scorecard));
    lines.push(
      `parse_coverage: ${fixture.signalMetrics.parseCoverage.toFixed(2)}`,
    );
    lines.push(
      `graph_edge_density: ${fixture.signalMetrics.graphEdgeDensity.toFixed(2)}`,
    );
    lines.push(
      `survey_hypotheses: ${fixture.signalMetrics.surveyHypothesisCount}`,
    );
    lines.push(
      `mean_expansion_closure_size: ${fixture.signalMetrics.meanExpansionClosureSize.toFixed(2)}`,
    );
    lines.push(
      `median_expansion_closure_size: ${fixture.signalMetrics.medianExpansionClosureSize.toFixed(2)}`,
    );
    if (fixture.errors.length > 0) {
      lines.push("errors:");
      for (const error of fixture.errors) {
        lines.push(`- ${error}`);
      }
    }
  }
  return lines.join("\n");
}
