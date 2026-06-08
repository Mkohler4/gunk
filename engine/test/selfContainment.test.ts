import { describe, expect, it } from "vitest";

import { CodeGraphBuilder, type CodeGraph } from "../src/analyze/codeGraph.js";
import { ImportResolver } from "../src/analyze/importResolver.js";
import { verifySelfContainment } from "../src/decompose/selfContainment.js";
import type { FileSymbols, ImportRef, Module, Symbol } from "../src/models.js";
import { languageKindForPath } from "../src/models.js";

function fileSymbols(
  path: string,
  options: { symbols?: Symbol[]; imports?: ImportRef[]; exports?: FileSymbols["exports"] } = {},
): FileSymbols {
  return {
    path,
    language: languageKindForPath(path),
    viaFallback: false,
    symbols: options.symbols ?? [],
    imports: options.imports ?? [],
    exports: options.exports ?? [],
  };
}

function module(options: Partial<Module> = {}): Module {
  return {
    name: "Auth module",
    purpose: "Handles auth",
    tags: ["auth"],
    files: ["src/auth/route.ts", "src/auth/service.ts"],
    language: "TypeScript",
    confidence: 0.9,
    ownedFiles: ["src/auth/route.ts", "src/auth/service.ts"],
    sharedDeps: [],
    surface: [{ path: "src/auth/route.ts", symbol: "POST" }],
    anchors: ["POST"],
    ...options,
  };
}

function buildGraph(files: FileSymbols[]): CodeGraph {
  return new CodeGraphBuilder(
    new ImportResolver({ sourceFiles: new Set(files.map((file) => file.path)) }),
  ).build(files);
}

describe("verifySelfContainment", () => {
  it("passes a complete, exported-entrypoint module", () => {
    const files = [
      fileSymbols("src/auth/route.ts", {
        symbols: [{ name: "POST", kind: "function", line: 2 }],
        exports: [{ name: "POST", kind: "function", line: 2 }],
        imports: [
          { moduleSpecifier: "./service", resolvedTarget: null, line: 1 },
          { moduleSpecifier: "stripe", resolvedTarget: null, line: 2 },
        ],
      }),
      fileSymbols("src/auth/service.ts", {
        symbols: [{ name: "createSession", kind: "function", line: 1 }],
        exports: [{ name: "createSession", kind: "function", line: 1 }],
      }),
    ];

    const result = verifySelfContainment({
      module: module(),
      graph: buildGraph(files),
      files,
      declaredExternalDependencies: ["stripe"],
    });

    expect(result.imports).toBe("pass");
    expect(result.entrypoint).toBe("pass");
    expect(result.danglingImports).toEqual([]);
    expect(result.missingEntrypoints).toEqual([]);
  });

  it("fails when an internal import dangles", () => {
    const files = [
      fileSymbols("src/auth/route.ts", {
        symbols: [{ name: "POST", kind: "function", line: 2 }],
        exports: [{ name: "POST", kind: "function", line: 2 }],
        imports: [{ moduleSpecifier: "./service", resolvedTarget: null, line: 1 }],
      }),
      fileSymbols("src/auth/service.ts"),
    ];

    const result = verifySelfContainment({
      module: module({
        files: ["src/auth/route.ts"],
        ownedFiles: ["src/auth/route.ts"],
      }),
      graph: buildGraph(files),
      files,
      declaredExternalDependencies: [],
    });

    expect(result.imports).toBe("fail");
    expect(result.danglingImports).toEqual([
      {
        fromPath: "src/auth/route.ts",
        moduleSpecifier: null,
        resolvedTarget: "src/auth/service.ts",
        reason: "internalImportOutsideModule",
      },
    ]);
  });

  it("fails when the claimed entrypoint is not exported", () => {
    const files = [
      fileSymbols("src/auth/route.ts", {
        symbols: [{ name: "POST", kind: "function", line: 2 }],
        exports: [],
      }),
    ];

    const result = verifySelfContainment({
      module: module({
        files: ["src/auth/route.ts"],
        ownedFiles: ["src/auth/route.ts"],
      }),
      graph: buildGraph(files),
      files,
      declaredExternalDependencies: [],
    });

    expect(result.entrypoint).toBe("fail");
    expect(result.missingEntrypoints).toEqual([
      {
        path: "src/auth/route.ts",
        symbol: "POST",
        reason: "notExported",
      },
    ]);
  });
});
