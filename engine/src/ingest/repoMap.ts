import type { ExportRef, Symbol } from "../models.js";
import { type CapabilityHint } from "../analyze/capabilityLexicon.js";
import { type RouteSurface } from "../analyze/routeDetector.js";

export const TRUNCATION_MARKER = "\n[...repo map truncated at cluster boundary...]";

function exportRefSerialized(ref: ExportRef): string {
  if (ref.kind) {
    return `${ref.name}:${ref.kind}@${ref.line}`;
  }
  return `${ref.name}@${ref.line}`;
}

function symbolSerialized(symbol: Symbol): string {
  return `${symbol.name}:${symbol.kind}@${symbol.line}`;
}

function capabilityHintSerialized(hint: CapabilityHint): string {
  return `${hint.library}[${[...hint.labels].sort().join("/")}]`;
}

function routeSurfaceSerialized(route: RouteSurface): string {
  return `${route.framework}:${route.method} ${route.path}@${route.line}`;
}

export interface RepoMapImport {
  specifier: string;
  target: string | null;
}

function repoMapImportSerialized(value: RepoMapImport): string {
  if (value.target !== null) {
    return `${value.specifier}->${value.target}`;
  }
  return `${value.specifier}->external`;
}

export interface RepoMapSnippet {
  kind: string;
  line: number;
  text: string;
}

function repoMapSnippetSerialized(snippet: RepoMapSnippet): string {
  return `${snippet.kind}@${snippet.line}: ${snippet.text.replace(/\n/g, " ")}`;
}

export class RepoMapCluster {
  constructor(
    readonly id: string,
    readonly filePaths: string[],
    readonly cohesionScore: number,
    readonly bridgeFiles: string[],
    readonly capabilityHints: CapabilityHint[],
    readonly routes: RouteSurface[],
  ) {}

  get importanceScore(): number {
    return (
      this.routes.length * 20 +
      this.capabilityHints.length * 15 +
      this.bridgeFiles.length * 5 +
      this.filePaths.length
    );
  }

  serialized(): string {
    let output = `- id: ${this.id}\n`;
    output += `  files: ${this.filePaths.join(", ")}\n`;
    output += `  cohesion: ${this.cohesionScore.toFixed(2)}\n`;

    if (this.bridgeFiles.length > 0) {
      output += `  bridge_files: ${this.bridgeFiles.join(", ")}\n`;
    }
    if (this.capabilityHints.length > 0) {
      output += `  hints: ${this.capabilityHints.map(capabilityHintSerialized).join(", ")}\n`;
    }
    if (this.routes.length > 0) {
      output += `  routes: ${this.routes.map(routeSurfaceSerialized).join(", ")}\n`;
    }

    return output;
  }
}

export class RepoMapFile {
  constructor(
    readonly path: string,
    readonly size: number,
    readonly clusterId: string | null,
    readonly exports: ExportRef[],
    readonly keySymbols: Symbol[],
    readonly imports: RepoMapImport[],
    readonly routes: RouteSurface[],
    readonly envVars: string[],
    readonly configKeys: string[],
    readonly capabilityHints: CapabilityHint[],
    readonly snippets: RepoMapSnippet[],
  ) {}

  serialized(): string {
    let output = `- path: ${this.path}\n`;
    output += `  size: ${this.size}\n`;
    if (this.clusterId !== null) {
      output += `  cluster: ${this.clusterId}\n`;
    }
    if (this.exports.length > 0) {
      output += `  exports: ${this.exports.map(exportRefSerialized).join(", ")}\n`;
    }
    if (this.keySymbols.length > 0) {
      output += `  symbols: ${this.keySymbols.map(symbolSerialized).join(", ")}\n`;
    }
    if (this.imports.length > 0) {
      output += `  imports: ${this.imports.map(repoMapImportSerialized).join(", ")}\n`;
    }
    if (this.routes.length > 0) {
      output += `  routes: ${this.routes.map(routeSurfaceSerialized).join(", ")}\n`;
    }
    if (this.envVars.length > 0) {
      output += `  env: ${this.envVars.join(", ")}\n`;
    }
    if (this.configKeys.length > 0) {
      output += `  config: ${this.configKeys.join(", ")}\n`;
    }
    if (this.capabilityHints.length > 0) {
      output += `  hints: ${this.capabilityHints.map(capabilityHintSerialized).join(", ")}\n`;
    }
    if (this.snippets.length > 0) {
      output += `  snippets:\n`;
      for (const snippet of this.snippets) {
        output += `    - ${repoMapSnippetSerialized(snippet)}\n`;
      }
    }

    return output;
  }

  compactSerialized(): string {
    let output = `- path: ${this.path}\n`;
    output += `  size: ${this.size}\n`;
    if (this.clusterId !== null) {
      output += `  cluster: ${this.clusterId}\n`;
    }
    if (this.exports.length > 0) {
      output += `  exports: ${this.exports.map(exportRefSerialized).join(", ")}\n`;
    }
    if (this.keySymbols.length > 0) {
      output += `  symbols: ${this.keySymbols.map(symbolSerialized).join(", ")}\n`;
    }
    if (this.routes.length > 0) {
      output += `  routes: ${this.routes.map(routeSurfaceSerialized).join(", ")}\n`;
    }
    if (this.envVars.length > 0) {
      output += `  env: ${this.envVars.join(", ")}\n`;
    }
    if (this.configKeys.length > 0) {
      output += `  config: ${this.configKeys.join(", ")}\n`;
    }
    if (this.capabilityHints.length > 0) {
      output += `  hints: ${this.capabilityHints.map(capabilityHintSerialized).join(", ")}\n`;
    }

    return output;
  }
}

interface RepoMapChunkGroup {
  cluster: RepoMapCluster | null;
  files: RepoMapFile[];
}

export class RepoMap {
  constructor(
    readonly files: RepoMapFile[],
    readonly clusters: RepoMapCluster[],
    readonly externalDependencies: Record<string, string[]>,
  ) {}

  serialized(budgetTokens: number): string {
    const charBudget = Math.max(0, budgetTokens * 4);
    if (charBudget <= TRUNCATION_MARKER.length) {
      return TRUNCATION_MARKER.slice(0, charBudget);
    }

    let output = "repo_map_v1\n";
    output += this.treeBlock();
    output += "clusters:\n";

    const sortedClusters = [...this.clusters].sort((lhs, rhs) =>
      lhs.id < rhs.id ? -1 : lhs.id > rhs.id ? 1 : 0,
    );
    for (const cluster of sortedClusters) {
      output += cluster.serialized();
    }

    output += "files:\n";

    let didTruncate = false;
    for (const cluster of this.prioritizedClusters(sortedClusters)) {
      const clusterFiles = this.files
        .filter((file) => file.clusterId === cluster.id)
        .sort((lhs, rhs) => (lhs.path < rhs.path ? -1 : lhs.path > rhs.path ? 1 : 0));
      const block = clusterFiles.map((file) => file.serialized()).join("");

      if (output.length + block.length + TRUNCATION_MARKER.length > charBudget) {
        didTruncate = true;
        break;
      }

      output += block;
    }

    const unclusteredFiles = this.files
      .filter((file) => file.clusterId === null)
      .sort((lhs, rhs) => (lhs.path < rhs.path ? -1 : lhs.path > rhs.path ? 1 : 0));
    for (const file of unclusteredFiles) {
      const block = file.serialized();
      if (output.length + block.length + TRUNCATION_MARKER.length > charBudget) {
        didTruncate = true;
        break;
      }

      output += block;
    }

    if (Object.keys(this.externalDependencies).length > 0) {
      const block = this.externalDependenciesBlock();
      if (output.length + block.length + TRUNCATION_MARKER.length <= charBudget) {
        output += block;
      } else {
        didTruncate = true;
      }
    }

    if (didTruncate) {
      output += TRUNCATION_MARKER;
    }

    if (output.length > charBudget) {
      const allowed = Math.max(0, charBudget - TRUNCATION_MARKER.length);
      output = output.slice(0, allowed) + TRUNCATION_MARKER;
    }

    return output;
  }

  serializedChunks(budgetTokens: number): string[] {
    const full = this.serialized(budgetTokens);
    if (!full.includes(TRUNCATION_MARKER)) {
      return [full];
    }

    const charBudget = Math.max(0, budgetTokens * 4);
    if (charBudget <= TRUNCATION_MARKER.length) {
      return [TRUNCATION_MARKER.slice(0, charBudget)];
    }

    const groups = this.chunkGroups();
    const chunks: RepoMapChunkGroup[][] = [];
    let current: RepoMapChunkGroup[] = [];

    for (const group of groups) {
      const next = [...current, group];
      if (current.length === 0 || this.chunkFits(next, charBudget)) {
        current = next;
        continue;
      }
      chunks.push(current);
      current = [group];
    }
    if (current.length > 0) {
      chunks.push(current);
    }

    return chunks.map((chunk, index) => this.chunkSerialized(chunk, index + 1, chunks.length, charBudget));
  }

  private chunkGroups(): RepoMapChunkGroup[] {
    const sortedClusters = [...this.clusters].sort((lhs, rhs) =>
      lhs.id < rhs.id ? -1 : lhs.id > rhs.id ? 1 : 0,
    );
    const groups: RepoMapChunkGroup[] = this.prioritizedClusters(sortedClusters).map((cluster) => ({
      cluster,
      files: this.files
        .filter((file) => file.clusterId === cluster.id)
        .sort((lhs, rhs) => (lhs.path < rhs.path ? -1 : lhs.path > rhs.path ? 1 : 0)),
    }));
    const unclusteredFiles = this.files
      .filter((file) => file.clusterId === null)
      .sort((lhs, rhs) => (lhs.path < rhs.path ? -1 : lhs.path > rhs.path ? 1 : 0));
    if (unclusteredFiles.length > 0) {
      groups.push({ cluster: null, files: unclusteredFiles });
    }
    return groups;
  }

  private chunkSerialized(groups: RepoMapChunkGroup[], index: number, total: number, charBudget: number): string {
    const full = this.chunkSerializedWithFileBlocks(groups, index, total, "full");
    if (full.length <= charBudget) return full;

    const compact = this.chunkSerializedWithFileBlocks(groups, index, total, "compact");
    if (compact.length <= charBudget) return compact;

    const allowed = Math.max(0, charBudget - TRUNCATION_MARKER.length);
    return compact.slice(0, allowed) + TRUNCATION_MARKER;
  }

  private chunkFits(groups: RepoMapChunkGroup[], charBudget: number): boolean {
    return (
      this.chunkSerializedWithFileBlocks(groups, 1, 1, "full").length <= charBudget ||
      this.chunkSerializedWithFileBlocks(groups, 1, 1, "compact").length <= charBudget
    );
  }

  private chunkSerializedWithFileBlocks(
    groups: RepoMapChunkGroup[],
    index: number,
    total: number,
    mode: "full" | "compact",
  ): string {
    const files = groups.flatMap((group) => group.files);
    let output = `repo_map_v1_chunk ${index}/${total}\n`;
    output += "tree:\n";
    for (const file of files) {
      output += `- ${file.path} (${file.size} bytes)\n`;
    }

    output += "clusters:\n";
    for (const group of groups) {
      if (group.cluster !== null) {
        output += group.cluster.serialized();
      }
    }

    output += "files:\n";
    for (const file of files) {
      output += mode === "full" ? file.serialized() : file.compactSerialized();
    }

    const dependencies = this.externalDependenciesFor(files);
    if (Object.keys(dependencies).length > 0) {
      output += this.externalDependenciesBlockFor(dependencies);
    }

    return output;
  }

  private prioritizedClusters(clusters: RepoMapCluster[]): RepoMapCluster[] {
    return [...clusters].sort((lhs, rhs) => {
      if (lhs.importanceScore !== rhs.importanceScore) {
        return rhs.importanceScore - lhs.importanceScore;
      }
      return lhs.id < rhs.id ? -1 : lhs.id > rhs.id ? 1 : 0;
    });
  }

  private treeBlock(): string {
    let output = "tree:\n";
    for (const file of [...this.files].sort((lhs, rhs) =>
      lhs.path < rhs.path ? -1 : lhs.path > rhs.path ? 1 : 0,
    )) {
      output += `- ${file.path} (${file.size} bytes)\n`;
    }

    return output;
  }

  private externalDependenciesBlock(): string {
    return this.externalDependenciesBlockFor(this.externalDependencies);
  }

  private externalDependenciesFor(files: RepoMapFile[]): Record<string, string[]> {
    const selected = new Set(files.map((file) => file.path));
    const dependencies: Record<string, string[]> = {};
    for (const [path, deps] of Object.entries(this.externalDependencies)) {
      if (selected.has(path)) {
        dependencies[path] = deps;
      }
    }
    return dependencies;
  }

  private externalDependenciesBlockFor(externalDependencies: Record<string, string[]>): string {
    let output = "external_deps:\n";
    const entries = Object.entries(externalDependencies).sort((lhs, rhs) =>
      lhs[0] < rhs[0] ? -1 : lhs[0] > rhs[0] ? 1 : 0,
    );
    for (const [path, dependencies] of entries) {
      output += `- file: ${path}\n`;
      output += `  deps: ${[...dependencies].sort().join(", ")}\n`;
    }

    return output;
  }
}
