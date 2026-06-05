import { describe, expect, it } from "vitest";

import type { Module } from "../src/models.js";
import { score, summary, type ExpectedDecomposition } from "../src/eval/scorecard.js";

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
