import { readFileSync } from "node:fs";
import path from "node:path";

import type { ExportRef, FileSymbols, ImportRef, ScannedFile, Symbol } from "../models.js";
import {
  type CapabilityFingerprint,
  CapabilityFingerprintBuilder,
} from "../analyze/capabilityFingerprint.js";
import { type CapabilityHint } from "../analyze/capabilityLexicon.js";
import { CodeGraphBuilder } from "../analyze/codeGraph.js";
import { type DependencyManifest, DependencyManifestParser } from "../analyze/dependencyManifest.js";
import { type GraphCluster, GraphClustering } from "../analyze/graphClustering.js";
import { dartPackageNameFromManifests, ImportResolver } from "../analyze/importResolver.js";
import { type RouteSurface } from "../analyze/routeDetector.js";
import { type SymbolExtractor } from "../analyze/symbolExtractor.js";
import {
  RepoMap,
  RepoMapCluster,
  RepoMapFile,
  type RepoMapImport,
  type RepoMapSnippet,
  TRUNCATION_MARKER,
} from "./repoMap.js";

const MANIFEST_BASENAMES = [
  "package.json",
  "package.swift",
  "pyproject.toml",
  "requirements.txt",
  "go.mod",
  "cargo.toml",
  "pubspec.yaml",
  "build.gradle",
  "build.gradle.kts",
];

function splitLines(contents: string): string[] {
  return contents.split(/\r\n|\r|\n/);
}

function trimWhitespace(value: string): string {
  return value.replace(/^[ \t]+/, "").replace(/[ \t]+$/, "");
}

function sortedCapabilityHints(hints: CapabilityHint[]): CapabilityHint[] {
  return [...hints].sort((lhs, rhs) => {
    if (lhs.library !== rhs.library) {
      return lhs.library < rhs.library ? -1 : 1;
    }
    const lhsLabels = [...lhs.labels].sort().join("/");
    const rhsLabels = [...rhs.labels].sort().join("/");
    return lhsLabels < rhsLabels ? -1 : lhsLabels > rhsLabels ? 1 : 0;
  });
}

function sortedExports(exports: ExportRef[]): ExportRef[] {
  return [...exports].sort((lhs, rhs) => {
    if (lhs.line !== rhs.line) {
      return lhs.line - rhs.line;
    }
    return lhs.name < rhs.name ? -1 : lhs.name > rhs.name ? 1 : 0;
  });
}

function sortedRoutes(routes: RouteSurface[]): RouteSurface[] {
  return [...routes].sort((lhs, rhs) => {
    if (lhs.line !== rhs.line) {
      return lhs.line - rhs.line;
    }
    if (lhs.path !== rhs.path) {
      return lhs.path < rhs.path ? -1 : 1;
    }
    return lhs.method < rhs.method ? -1 : lhs.method > rhs.method ? 1 : 0;
  });
}

function sortedSymbols(symbols: Symbol[]): Symbol[] {
  return [...symbols].sort((lhs, rhs) => {
    if (lhs.line !== rhs.line) {
      return lhs.line - rhs.line;
    }
    return lhs.name < rhs.name ? -1 : lhs.name > rhs.name ? 1 : 0;
  });
}

export class ContextBuilder {
  static readonly truncationMarker = TRUNCATION_MARKER;

  private readonly symbolExtractor: SymbolExtractor;
  private readonly manifestParser: DependencyManifestParser;
  private readonly fingerprintBuilder: CapabilityFingerprintBuilder;

  constructor(
    symbolExtractor: SymbolExtractor,
    manifestParser: DependencyManifestParser = new DependencyManifestParser(),
    fingerprintBuilder: CapabilityFingerprintBuilder = new CapabilityFingerprintBuilder(),
  ) {
    this.symbolExtractor = symbolExtractor;
    this.manifestParser = manifestParser;
    this.fingerprintBuilder = fingerprintBuilder;
  }

  build(files: ScannedFile[], budgetTokens: number): string {
    return this.buildRepoMap(files).serialized(budgetTokens);
  }

  serialize(repoMap: RepoMap, budgetTokens: number): string {
    return repoMap.serialized(budgetTokens);
  }

  serializeChunks(repoMap: RepoMap, budgetTokens: number): string[] {
    return repoMap.serializedChunks(budgetTokens);
  }

  buildRepoMap(files: ScannedFile[]): RepoMap {
    const sortedFiles = [...files].sort((lhs, rhs) =>
      lhs.relpath < rhs.relpath ? -1 : lhs.relpath > rhs.relpath ? 1 : 0,
    );
    const contentsByPath = this.readContents(sortedFiles);
    const fileSymbols = sortedFiles.map((file) =>
      this.symbols(file, contentsByPath[file.relpath] ?? ""),
    );
    const manifestContents = this.manifestContents(contentsByPath);
    const manifests = this.manifestParser.parse(manifestContents);
    const resolver = new ImportResolver({
      sourceFiles: new Set(sortedFiles.map((file) => file.relpath)),
      dartPackageName: dartPackageNameFromManifests(manifestContents),
    });
    const graph = new CodeGraphBuilder(resolver).build(fileSymbols, contentsByPath);
    const clustering = new GraphClustering(graph);
    const clusters = clustering.connectedComponents();
    const bridgeFiles = new Set(
      clustering.highFanInBridgeFiles(2).map((node) => node.filePath),
    );
    const fingerprints = this.fingerprintBuilder.fingerprints(
      fileSymbols,
      manifests,
      contentsByPath,
    );
    const fingerprintsByPath = new Map<string, CapabilityFingerprint>(
      fingerprints.map((fingerprint) => [fingerprint.filePath, fingerprint]),
    );
    const clusterIdsByPath = this.clusterIds(clusters);

    const repoClusters = clusters.map((cluster, index) => {
      const id = `c${index + 1}`;
      const aggregate = this.fingerprintBuilder.aggregate(
        fingerprints,
        new Set(cluster.filePaths),
      );
      return new RepoMapCluster(
        id,
        [...cluster.filePaths].sort(),
        cluster.cohesionScore,
        cluster.filePaths.filter((filePath) => bridgeFiles.has(filePath)).sort(),
        sortedCapabilityHints(aggregate.capabilityHints),
        sortedRoutes(aggregate.routes),
      );
    });

    const repoFiles = sortedFiles.map((file) => {
      const symbols = fileSymbols.find((value) => value.path === file.relpath);
      const fingerprint = fingerprintsByPath.get(file.relpath);
      const contents = contentsByPath[file.relpath] ?? "";

      return new RepoMapFile(
        file.relpath,
        file.size,
        clusterIdsByPath.get(file.relpath) ?? null,
        sortedExports(symbols?.exports ?? []),
        this.keySymbols(symbols?.symbols ?? []),
        this.repoImports(symbols?.imports ?? [], resolver, file.relpath),
        sortedRoutes(fingerprint?.routes ?? []),
        [...(fingerprint?.envVars ?? [])].sort(),
        [...(fingerprint?.configKeys ?? [])].sort(),
        sortedCapabilityHints(fingerprint?.capabilityHints ?? []),
        this.snippets(file, contents, fingerprint?.routes ?? [], manifests),
      );
    });

    const externalDependencies: Record<string, string[]> = {};
    for (const [filePath, deps] of Object.entries(graph.externalDependencies)) {
      externalDependencies[filePath] = [...deps].sort();
    }

    return new RepoMap(repoFiles, repoClusters, externalDependencies);
  }

  static estimatedTokens(text: string): number {
    return Math.ceil(text.length / 4);
  }

  private readContents(files: ScannedFile[]): Record<string, string> {
    const contentsByPath: Record<string, string> = {};
    for (const file of files) {
      contentsByPath[file.relpath] = readFileSync(file.absPath, "utf8");
    }
    return contentsByPath;
  }

  private symbols(file: ScannedFile, contents: string): FileSymbols {
    return this.symbolExtractor.extract({ path: file.relpath, contents });
  }

  private manifestContents(contentsByPath: Record<string, string>): Record<string, string> {
    const manifests: Record<string, string> = {};
    for (const [filePath, contents] of Object.entries(contentsByPath)) {
      const basename = path.basename(filePath).toLowerCase();
      if (MANIFEST_BASENAMES.includes(basename)) {
        manifests[filePath] = contents;
      }
    }
    return manifests;
  }

  private clusterIds(clusters: GraphCluster[]): Map<string, string> {
    const ids = new Map<string, string>();
    clusters.forEach((cluster, index) => {
      for (const filePath of cluster.filePaths) {
        ids.set(filePath, `c${index + 1}`);
      }
    });
    return ids;
  }

  private keySymbols(symbols: Symbol[]): Symbol[] {
    return sortedSymbols(symbols).slice(0, 8);
  }

  private repoImports(
    imports: ImportRef[],
    resolver: ImportResolver,
    filePath: string,
  ): RepoMapImport[] {
    return imports
      .map((importRef) => ({
        specifier: importRef.moduleSpecifier,
        target: resolver.resolve(importRef.moduleSpecifier, filePath) ?? importRef.resolvedTarget,
      }))
      .sort((lhs, rhs) => {
        if (lhs.specifier !== rhs.specifier) {
          return lhs.specifier < rhs.specifier ? -1 : 1;
        }
        const lhsTarget = lhs.target ?? "";
        const rhsTarget = rhs.target ?? "";
        return lhsTarget < rhsTarget ? -1 : lhsTarget > rhsTarget ? 1 : 0;
      });
  }

  private snippets(
    file: ScannedFile,
    contents: string,
    routes: RouteSurface[],
    manifests: DependencyManifest[],
  ): RepoMapSnippet[] {
    const snippets: RepoMapSnippet[] = [];
    const lines = splitLines(contents);

    for (const route of sortedRoutes(routes).slice(0, 4)) {
      if (route.line - 1 >= 0 && route.line - 1 < lines.length) {
        snippets.push({
          kind: "route",
          line: route.line,
          text: trimWhitespace(lines[route.line - 1]),
        });
      }
    }

    const manifest = manifests.find((value) => value.path === file.relpath);
    if (manifest && manifest.dependencies.length > 0) {
      snippets.push({
        kind: "manifest",
        line: 1,
        text: `dependencies: ${[...manifest.dependencies].sort().slice(0, 12).join(", ")}`,
      });
    }

    return snippets;
  }
}
