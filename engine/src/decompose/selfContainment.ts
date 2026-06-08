import type { CodeGraph } from "../analyze/codeGraph.js";
import type { FileSymbols, Module } from "../models.js";
import { fileNode } from "../models.js";

export interface DanglingImport {
  fromPath: string;
  moduleSpecifier: string | null;
  resolvedTarget: string | null;
  reason: "internalImportOutsideModule" | "missingExternalDependency";
}

export interface MissingEntrypoint {
  path: string;
  symbol: string | null;
  reason: "pathOutsideModule" | "missingSymbol" | "notExported";
}

export interface SelfContainmentResult {
  moduleName: string;
  imports: "pass" | "fail";
  entrypoint: "pass" | "fail";
  danglingImports: DanglingImport[];
  missingEntrypoints: MissingEntrypoint[];
}

interface VerifySelfContainmentArgs {
  module: Module;
  graph: CodeGraph;
  files: FileSymbols[];
  declaredExternalDependencies: string[];
}

function dedupeStrings(values: string[]): string[] {
  return [...new Set(values)].sort((a, b) => a.localeCompare(b));
}

function normalizePackageName(name: string): string {
  return name.toLowerCase().replace(/_/g, "-").trim();
}

function packageRoot(specifier: string): string {
  if (specifier.startsWith("package:")) {
    const body = specifier.slice("package:".length);
    const first = body.split("/")[0];
    return first.length > 0 ? first : specifier;
  }

  if (!specifier.startsWith("@")) {
    const first = specifier.split("/")[0];
    return first.length > 0 ? first : specifier;
  }

  const parts = specifier.split("/");
  return parts.length >= 2 ? `${parts[0]}/${parts[1]}` : specifier;
}

function externalDependencyCovers(specifier: string, dependency: string): boolean {
  const normalizedSpecifier = normalizePackageName(packageRoot(specifier));
  const normalizedDependency = normalizePackageName(dependency);
  const normalizedGroup = normalizePackageName(dependency.split(":")[0] ?? "");

  return (
    normalizedSpecifier === normalizedDependency ||
    normalizedSpecifier.startsWith(`${normalizedDependency}/`) ||
    normalizedDependency.startsWith(`${normalizedSpecifier}/`) ||
    (normalizedGroup.length > 0 &&
      (normalizedSpecifier === normalizedGroup ||
        normalizedSpecifier.startsWith(`${normalizedGroup}.`)))
  );
}

function isExternalImportCovered(specifier: string, dependencies: Set<string>): boolean {
  return [...dependencies].some((dependency) =>
    externalDependencyCovers(specifier, dependency),
  );
}

function importSpecifierFor(
  filesByPath: Map<string, FileSymbols>,
  fromPath: string,
  resolvedTarget: string,
): string | null {
  return (
    filesByPath
      .get(fromPath)
      ?.imports.find((importRef) => importRef.resolvedTarget === resolvedTarget)
      ?.moduleSpecifier ?? null
  );
}

export function verifySelfContainment({
  module,
  graph,
  files,
  declaredExternalDependencies,
}: VerifySelfContainmentArgs): SelfContainmentResult {
  const moduleFiles = new Set(module.files);
  const filesByPath = new Map(files.map((file) => [file.path, file]));
  const dependencies = new Set(dedupeStrings(declaredExternalDependencies));
  const danglingImports: DanglingImport[] = [];

  for (const path of moduleFiles) {
    const sourceNode = fileNode(path);
    for (const edge of graph.edges) {
      if (
        edge.kind !== "import" ||
        edge.from.id !== sourceNode.id ||
        edge.to.kind !== "file"
      ) {
        continue;
      }
      if (moduleFiles.has(edge.to.filePath)) {
        continue;
      }

      danglingImports.push({
        fromPath: path,
        moduleSpecifier: importSpecifierFor(filesByPath, path, edge.to.filePath),
        resolvedTarget: edge.to.filePath,
        reason: "internalImportOutsideModule",
      });
    }

    for (const moduleSpecifier of graph.externalDependencies[path] ?? []) {
      if (isExternalImportCovered(moduleSpecifier, dependencies)) {
        continue;
      }
      danglingImports.push({
        fromPath: path,
        moduleSpecifier,
        resolvedTarget: null,
        reason: "missingExternalDependency",
      });
    }
  }

  const missingEntrypoints: MissingEntrypoint[] = [];
  for (const entrypoint of module.surface) {
    if (!moduleFiles.has(entrypoint.path)) {
      missingEntrypoints.push({
        path: entrypoint.path,
        symbol: entrypoint.symbol,
        reason: "pathOutsideModule",
      });
      continue;
    }
    if (!entrypoint.symbol) {
      missingEntrypoints.push({
        path: entrypoint.path,
        symbol: entrypoint.symbol,
        reason: "missingSymbol",
      });
      continue;
    }
    const file = filesByPath.get(entrypoint.path);
    const exported = file?.exports.some((exportRef) => exportRef.name === entrypoint.symbol) ?? false;
    if (!exported) {
      missingEntrypoints.push({
        path: entrypoint.path,
        symbol: entrypoint.symbol,
        reason: "notExported",
      });
    }
  }

  return {
    moduleName: module.name,
    imports: danglingImports.length === 0 ? "pass" : "fail",
    entrypoint: missingEntrypoints.length === 0 ? "pass" : "fail",
    danglingImports,
    missingEntrypoints,
  };
}
