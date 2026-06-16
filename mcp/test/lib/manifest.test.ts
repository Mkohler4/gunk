import { describe, expect, test } from "vitest";

import {
  parseEntrypoints,
  parseRequirementPackages,
} from "../../src/lib/manifest.js";

const MANIFEST = `schema_version: 0
id: 7
name: "parser"
language: "Python"
deps:
  package_managers: []
  packages: []
requirements:
  runtime: "Python >= 3.11"
  packages:
    - "ebooklib"
    - "markdownify"
  env:
    - "API_KEY"
entrypoints:
  - path: "main.py"
    symbol: "parse_epub"
  - path: "src/index.py"
    symbol: null
provenance:
  source_path: "/code/source"
confidence: 0.9
`;

describe("parseEntrypoints", () => {
  test("reads path + symbol pairs", () => {
    expect(parseEntrypoints(MANIFEST)).toEqual([
      { path: "main.py", symbol: "parse_epub" },
      { path: "src/index.py", symbol: null },
    ]);
  });

  test("handles an empty inline list", () => {
    expect(parseEntrypoints("entrypoints: []\nconfidence: 0\n")).toEqual([]);
  });

  test("handles a path without a symbol line", () => {
    const manifest = `entrypoints:\n  - path: "only.py"\nconfidence: 0\n`;
    expect(parseEntrypoints(manifest)).toEqual([
      { path: "only.py", symbol: null },
    ]);
  });

  test("returns nothing when the block is absent", () => {
    expect(parseEntrypoints("name: x\n")).toEqual([]);
  });
});

describe("parseRequirementPackages", () => {
  test("reads the packages list, not env or runtime", () => {
    expect(parseRequirementPackages(MANIFEST)).toEqual([
      "ebooklib",
      "markdownify",
    ]);
  });

  test("returns [] for an inline-empty packages list", () => {
    const manifest = `requirements:\n  runtime: null\n  packages: []\n  env: []\nconfidence: 0\n`;
    expect(parseRequirementPackages(manifest)).toEqual([]);
  });

  test("returns [] when the block is absent (older bundles)", () => {
    expect(parseRequirementPackages("name: x\n")).toEqual([]);
  });
});
