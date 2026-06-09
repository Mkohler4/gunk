// Decomposition eval scorer. Ported from
// app/Sources/GunkApp/Decompose/DecompositionEval.swift. This is the acceptance
// gate: the engine must meet or beat the recorded baseline scorecard.

import type { Module, QualityGateReason } from "../models.js";
import type { RunTrace, StageRecord } from "../trace/trace.js";

const COHESION_PROXY_THRESHOLD = 0.35;
const SURFACE_REASONS = new Set<string>(["missingSurface", "singleFileWithoutOwnedSurface"]);
const CLASSIFICATION_REASONS = new Set<string>(["configOnly", "generatedOnly", "typeOnly", "utilityOnly"]);

export interface ExpectedModule {
  name: string;
  tags: string[];
  files: string[];
}

export interface ExpectedDecomposition {
  modules: ExpectedModule[];
  mustNotBeModules: string[];
}

export interface ModuleScore {
  expectedName: string;
  actualName: string | null;
  filePrecision: number;
  fileRecall: number;
  tagAccuracy: number;
  matchedFiles: string[];
  missingFiles: string[];
  extraFiles: string[];
}

export interface Scorecard {
  moduleScores: ModuleScore[];
  expectedModuleCount: number;
  actualModuleCount: number;
  moduleCountDelta: number;
  trivialModuleFalsePositiveCount: number;
  trivialModuleFalsePositiveRate: number;
  filePrecision: number;
  fileRecall: number;
  tagAccuracy: number;
}

export interface SignalMetrics {
  totalSymbolFiles: number;
  parsedFiles: number;
  fallbackFiles: number;
  realSymbolFiles: number;
  parseCoverage: number;
  graphNodes: number;
  graphEdges: number;
  graphEdgeDensity: number;
  surveyHypothesisCount: number;
  meanExpansionClosureSize: number;
  medianExpansionClosureSize: number;
  selfContainmentVerifiedCount: number;
  selfContainmentPassRate: number;
  buildVerifiedCount: number;
  buildPassRate: number;
  buildSkippedCount: number;
  gateRejectionHistogram: Partial<Record<QualityGateReason, number>>;
  proxyAgreement: ProxyAgreementMetrics;
}

export type QualityProxyName = "cohesion" | "surface" | "classification";

export interface ProxyAgreementMetric {
  evaluated: number;
  agreements: number;
  agreementRate: number;
  falsePositiveCount: number;
  falseNegativeCount: number;
}

export type ProxyAgreementMetrics = Record<QualityProxyName, ProxyAgreementMetric>;

export interface SignalFloor {
  minParseCoverage?: number;
  minGraphEdgeDensity?: number;
  minSurveyHypotheses?: number;
  minMeanExpansionClosureSize?: number;
  minMedianExpansionClosureSize?: number;
}

function ratio(numerator: number, denominator: number): number {
  return denominator > 0 ? numerator / denominator : 0;
}

function intersectionCount<T>(a: Set<T>, b: Set<T>): number {
  let count = 0;
  for (const item of a) if (b.has(item)) count += 1;
  return count;
}

function matchesTrap(file: string, trap: string): boolean {
  return trap.endsWith("/") ? file.startsWith(trap) : file === trap;
}

function isTrivialModule(module: Module, mustNotBeModules: string[]): boolean {
  if (module.files.length === 0) return false;
  return module.files.every((file) => mustNotBeModules.some((trap) => matchesTrap(file, trap)));
}

function scoreModule(expected: ExpectedModule, actual: Module): ModuleScore {
  const expectedFiles = new Set(expected.files);
  const actualFiles = new Set(actual.files);
  const matched = [...expectedFiles].filter((f) => actualFiles.has(f));
  const missing = [...expectedFiles].filter((f) => !actualFiles.has(f));
  const extra = [...actualFiles].filter((f) => !expectedFiles.has(f));
  const expectedTags = new Set(expected.tags);
  const actualTags = new Set(actual.tags);
  return {
    expectedName: expected.name,
    actualName: actual.name,
    filePrecision: ratio(matched.length, actualFiles.size),
    fileRecall: ratio(matched.length, expectedFiles.size),
    tagAccuracy: ratio(intersectionCount(expectedTags, actualTags), expectedTags.size),
    matchedFiles: matched.sort((a, b) => a.localeCompare(b)),
    missingFiles: missing.sort((a, b) => a.localeCompare(b)),
    extraFiles: extra.sort((a, b) => a.localeCompare(b)),
  };
}

function bestMatch(
  expected: ExpectedModule,
  candidates: { offset: number; element: Module }[],
): { offset: number; element: Module } | null {
  let best: { candidate: { offset: number; element: Module }; overlap: number; nameMatches: boolean } | null = null;
  const expectedFiles = new Set(expected.files);
  for (const candidate of candidates) {
    const overlap = intersectionCount(expectedFiles, new Set(candidate.element.files));
    const nameMatches = candidate.element.name === expected.name;
    if (overlap === 0 && !nameMatches) continue;
    if (
      !best ||
      overlap > best.overlap ||
      (overlap === best.overlap && !best.nameMatches && nameMatches)
    ) {
      best = { candidate, overlap, nameMatches };
    }
  }
  return best?.candidate ?? null;
}

function average(values: number[]): number {
  if (values.length === 0) return 0;
  return values.reduce((sum, v) => sum + v, 0) / values.length;
}

function median(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) {
    return sorted[middle] ?? 0;
  }
  return ((sorted[middle - 1] ?? 0) + (sorted[middle] ?? 0)) / 2;
}

function stage(trace: RunTrace, name: StageRecord["stage"]): StageRecord | undefined {
  return trace.stages.find((record) => record.stage === name && record.status === "ok");
}

function emptyProxyMetric(): ProxyAgreementMetric {
  return {
    evaluated: 0,
    agreements: 0,
    agreementRate: 0,
    falsePositiveCount: 0,
    falseNegativeCount: 0,
  };
}

function emptyProxyAgreementMetrics(): ProxyAgreementMetrics {
  return {
    cohesion: emptyProxyMetric(),
    surface: emptyProxyMetric(),
    classification: emptyProxyMetric(),
  };
}

function selfContainmentPasses(result: RunTrace["verification"]["selfContainment"][number]): boolean {
  return result.imports === "pass" && result.entrypoint === "pass";
}

function finalProxyMetric(metric: Omit<ProxyAgreementMetric, "agreementRate">): ProxyAgreementMetric {
  return {
    ...metric,
    agreementRate: ratio(metric.agreements, metric.evaluated),
  };
}

function proxyAgreementMetrics(trace: RunTrace): ProxyAgreementMetrics {
  const metrics = emptyProxyAgreementMetrics();

  trace.gateEvaluations.forEach((evaluation, index) => {
    const selfContainment = trace.verification.selfContainment[index];
    if (selfContainment === undefined) return;

    const expected = selfContainmentPasses(selfContainment);
    const predictions: Record<QualityProxyName, boolean> = {
      cohesion: evaluation.cohesionScore === null || evaluation.cohesionScore >= COHESION_PROXY_THRESHOLD,
      surface: !evaluation.reasons.some((reason) => SURFACE_REASONS.has(reason)),
      classification: !evaluation.reasons.some((reason) => CLASSIFICATION_REASONS.has(reason)),
    };

    for (const [name, prediction] of Object.entries(predictions) as [QualityProxyName, boolean][]) {
      const metric = metrics[name];
      metric.evaluated += 1;
      if (prediction === expected) {
        metric.agreements += 1;
      } else if (prediction) {
        metric.falsePositiveCount += 1;
      } else {
        metric.falseNegativeCount += 1;
      }
    }
  });

  return {
    cohesion: finalProxyMetric(metrics.cohesion),
    surface: finalProxyMetric(metrics.surface),
    classification: finalProxyMetric(metrics.classification),
  };
}

export function score(actual: Module[], expected: ExpectedDecomposition): Scorecard {
  let unusedActual = actual.map((element, offset) => ({ offset, element }));
  const moduleScores: ModuleScore[] = [];

  for (const expectedModule of expected.modules) {
    const match = bestMatch(expectedModule, unusedActual);
    if (match) {
      unusedActual = unusedActual.filter((c) => c.offset !== match.offset);
      moduleScores.push(scoreModule(expectedModule, match.element));
    } else {
      moduleScores.push({
        expectedName: expectedModule.name,
        actualName: null,
        filePrecision: 0,
        fileRecall: 0,
        tagAccuracy: 0,
        matchedFiles: [],
        missingFiles: [...expectedModule.files].sort((a, b) => a.localeCompare(b)),
        extraFiles: [],
      });
    }
  }

  const falsePositiveModules = actual.filter((m) => isTrivialModule(m, expected.mustNotBeModules));

  return {
    moduleScores,
    expectedModuleCount: expected.modules.length,
    actualModuleCount: actual.length,
    moduleCountDelta: actual.length - expected.modules.length,
    trivialModuleFalsePositiveCount: falsePositiveModules.length,
    trivialModuleFalsePositiveRate: ratio(falsePositiveModules.length, expected.mustNotBeModules.length),
    filePrecision: average(moduleScores.map((s) => s.filePrecision)),
    fileRecall: average(moduleScores.map((s) => s.fileRecall)),
    tagAccuracy: average(moduleScores.map((s) => s.tagAccuracy)),
  };
}

export function summary(card: Scorecard): string {
  const pct = (value: number) => value.toFixed(2);
  return [
    `file_precision: ${pct(card.filePrecision)}`,
    `file_recall: ${pct(card.fileRecall)}`,
    `tag_accuracy: ${pct(card.tagAccuracy)}`,
    `expected_modules: ${card.expectedModuleCount}`,
    `actual_modules: ${card.actualModuleCount}`,
    `module_count_delta: ${card.moduleCountDelta}`,
    `trivial_module_false_positives: ${card.trivialModuleFalsePositiveCount}`,
    `trivial_module_false_positive_rate: ${pct(card.trivialModuleFalsePositiveRate)}`,
  ].join("\n");
}

export function signalMetrics(trace: RunTrace): SignalMetrics {
  const symbolCounts = stage(trace, "symbols")?.counts ?? {};
  const graphCounts = stage(trace, "graph")?.counts ?? {};
  const surveyCounts = stage(trace, "survey")?.counts ?? {};
  const closureSizes = trace.expansions.map((expansion) => expansion.closureFiles.length);
  const selfContainmentResults = trace.verification?.selfContainment ?? [];
  const selfContainmentPassCount = selfContainmentResults.filter(
    (result) => result.imports === "pass" && result.entrypoint === "pass",
  ).length;
  const buildResults = trace.verification?.build ?? [];
  const attemptedBuilds = buildResults.filter((result) => !result.skipped);
  const buildPasses = attemptedBuilds.filter((result) => result.built).length;
  const gateRejectionHistogram: Partial<Record<QualityGateReason, number>> = {};

  for (const evaluation of trace.gateEvaluations) {
    if (evaluation.decision !== "rejected") continue;
    for (const reason of evaluation.reasons) {
      const key = reason as QualityGateReason;
      gateRejectionHistogram[key] = (gateRejectionHistogram[key] ?? 0) + 1;
    }
  }

  const totalSymbolFiles = symbolCounts.files ?? 0;
  const realSymbolFiles = symbolCounts.realSymbolFiles ?? 0;
  const graphNodes = graphCounts.nodes ?? 0;
  const graphEdges = graphCounts.edges ?? 0;

  return {
    totalSymbolFiles,
    parsedFiles: symbolCounts.parsedFiles ?? 0,
    fallbackFiles: symbolCounts.fallbackFiles ?? 0,
    realSymbolFiles,
    parseCoverage: ratio(realSymbolFiles, totalSymbolFiles),
    graphNodes,
    graphEdges,
    graphEdgeDensity: ratio(graphEdges, graphNodes),
    surveyHypothesisCount: surveyCounts.hypotheses ?? trace.hypotheses.length,
    meanExpansionClosureSize: average(closureSizes),
    medianExpansionClosureSize: median(closureSizes),
    selfContainmentVerifiedCount: selfContainmentResults.length,
    selfContainmentPassRate: ratio(selfContainmentPassCount, selfContainmentResults.length),
    buildVerifiedCount: buildResults.length,
    buildPassRate: ratio(buildPasses, attemptedBuilds.length),
    buildSkippedCount: buildResults.filter((result) => result.skipped).length,
    gateRejectionHistogram,
    proxyAgreement: proxyAgreementMetrics(trace),
  };
}

export function assertSignalFloor(metrics: SignalMetrics, floor: SignalFloor): void {
  const failures: string[] = [];
  const pushFailure = (name: string, actual: number, expected: number) => {
    failures.push(`${name} ${actual.toFixed(3)} is below floor ${expected.toFixed(3)}`);
  };

  if (floor.minParseCoverage !== undefined && metrics.parseCoverage < floor.minParseCoverage) {
    pushFailure("parseCoverage", metrics.parseCoverage, floor.minParseCoverage);
  }
  if (floor.minGraphEdgeDensity !== undefined && metrics.graphEdgeDensity < floor.minGraphEdgeDensity) {
    pushFailure("graphEdgeDensity", metrics.graphEdgeDensity, floor.minGraphEdgeDensity);
  }
  if (floor.minSurveyHypotheses !== undefined && metrics.surveyHypothesisCount < floor.minSurveyHypotheses) {
    pushFailure("surveyHypothesisCount", metrics.surveyHypothesisCount, floor.minSurveyHypotheses);
  }
  if (
    floor.minMeanExpansionClosureSize !== undefined &&
    metrics.meanExpansionClosureSize < floor.minMeanExpansionClosureSize
  ) {
    pushFailure("meanExpansionClosureSize", metrics.meanExpansionClosureSize, floor.minMeanExpansionClosureSize);
  }
  if (
    floor.minMedianExpansionClosureSize !== undefined &&
    metrics.medianExpansionClosureSize < floor.minMedianExpansionClosureSize
  ) {
    pushFailure("medianExpansionClosureSize", metrics.medianExpansionClosureSize, floor.minMedianExpansionClosureSize);
  }

  if (failures.length > 0) {
    throw new Error(`Signal floor failed: ${failures.join("; ")}`);
  }
}

export function loadExpected(json: unknown): ExpectedDecomposition {
  const root = json as Record<string, unknown>;
  const modules = Array.isArray(root.modules) ? root.modules : [];
  const mustNot = root.must_not_be_modules ?? root.mustNotBeModules;
  return {
    modules: modules.map((m) => {
      const obj = m as Record<string, unknown>;
      return {
        name: String(obj.name),
        tags: (obj.tags as string[]) ?? [],
        files: (obj.files as string[]) ?? [],
      };
    }),
    mustNotBeModules: Array.isArray(mustNot) ? (mustNot as string[]) : [],
  };
}
