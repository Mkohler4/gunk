// Decomposition eval scorer. Ported from
// app/Sources/GunkApp/Decompose/DecompositionEval.swift. This is the acceptance
// gate: the engine must meet or beat the recorded baseline scorecard.

import type { Module } from "../models.js";

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
