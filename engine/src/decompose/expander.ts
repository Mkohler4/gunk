// Deterministic capability closure expansion. Ported from
// app/Sources/GunkApp/Decompose/CapabilityExpander.swift.
//
// Operates purely on the CodeGraph data structure (file-level nodes/edges) so
// it has no dependency on the graph builder internals.

import type {
  CapabilityExpansion,
  CapabilityExpansionEdgeEvidence,
  CapabilityExpansionExcludedFile,
  CapabilityHypothesis,
  CodeGraph,
  CodeGraphEdge,
  CodeGraphEdgeKind,
} from "../models.js";
import { uniqued } from "../models.js";

export interface CapabilityExpansionOptions {
  maxDepth: number;
  maxFilesPerCapability: number;
  sharedFanInThreshold: number;
  edgeKinds: Set<CodeGraphEdgeKind>;
}

export const defaultExpansionOptions: CapabilityExpansionOptions = {
  maxDepth: 3,
  maxFilesPerCapability: 25,
  sharedFanInThreshold: 3,
  edgeKinds: new Set(["call", "import", "implements", "inherit", "reference"]),
};

interface Traversal {
  closureFiles: Set<string>;
  excludedFiles: Map<string, CapabilityExpansionExcludedFile>;
  edgeEvidence: Map<string, CapabilityExpansionEdgeEvidence>;
}

function excludedKey(file: CapabilityExpansionExcludedFile): string {
  return `${file.path}\u0000${file.reason}`;
}

function evidenceKey(evidence: CapabilityExpansionEdgeEvidence): string {
  return `${evidence.fromPath}\u0000${evidence.toPath}\u0000${evidence.kind}\u0000${evidence.depth}`;
}

function compareExcluded(a: CapabilityExpansionExcludedFile, b: CapabilityExpansionExcludedFile): number {
  return a.path === b.path ? a.reason.localeCompare(b.reason) : a.path.localeCompare(b.path);
}

function compareEvidence(a: CapabilityExpansionEdgeEvidence, b: CapabilityExpansionEdgeEvidence): number {
  if (a.fromPath !== b.fromPath) return a.fromPath.localeCompare(b.fromPath);
  if (a.toPath !== b.toPath) return a.toPath.localeCompare(b.toPath);
  if (a.kind !== b.kind) return a.kind.localeCompare(b.kind);
  return a.depth - b.depth;
}

export class CapabilityExpander {
  constructor(private readonly options: CapabilityExpansionOptions = defaultExpansionOptions) {}

  expand(hypotheses: CapabilityHypothesis[], graph: CodeGraph): CapabilityExpansion[] {
    const traversals = hypotheses.map((h) => this.traversal(h, graph));
    const sharedFiles = this.sharedDependencyFiles(traversals, graph);

    return hypotheses.map((hypothesis, index) => {
      const traversal = traversals[index];
      const closureFiles = [...traversal.closureFiles].sort((a, b) => a.localeCompare(b));
      const sharedDependencyFiles = closureFiles.filter((f) => sharedFiles.has(f));
      return {
        hypothesis,
        closureFiles,
        ownedFiles: closureFiles.filter((f) => !sharedFiles.has(f)),
        sharedDependencyFiles,
        excludedFiles: [...traversal.excludedFiles.values()].sort(compareExcluded),
        edgeEvidence: [...traversal.edgeEvidence.values()].sort(compareEvidence),
      };
    });
  }

  private graphFiles(graph: CodeGraph): Set<string> {
    return new Set(graph.nodes.filter((n) => n.kind === "file").map((n) => n.filePath));
  }

  private outboundFileEdges(path: string, graph: CodeGraph): CodeGraphEdge[] {
    return graph.edges
      .filter(
        (edge) =>
          edge.from.kind === "file" &&
          edge.from.filePath === path &&
          edge.to.filePath !== path &&
          this.options.edgeKinds.has(edge.kind),
      )
      .sort((lhs, rhs) => {
        if (lhs.to.filePath !== rhs.to.filePath) return lhs.to.filePath.localeCompare(rhs.to.filePath);
        if (lhs.kind !== rhs.kind) return lhs.kind.localeCompare(rhs.kind);
        return lhs.to.id.localeCompare(rhs.to.id);
      });
  }

  private inboundFileSourceCount(path: string, graph: CodeGraph): number {
    const sources = new Set(
      graph.edges
        .filter((edge) => edge.to.filePath === path && this.options.edgeKinds.has(edge.kind) && edge.from.kind === "file")
        .map((edge) => edge.from.filePath),
    );
    return sources.size;
  }

  private traversal(hypothesis: CapabilityHypothesis, graph: CodeGraph): Traversal {
    const graphFiles = this.graphFiles(graph);
    const closureFiles = new Set<string>();
    const excludedFiles = new Map<string, CapabilityExpansionExcludedFile>();
    const edgeEvidence = new Map<string, CapabilityExpansionEdgeEvidence>();
    const queue: { path: string; depth: number }[] = [];

    const addExcluded = (file: CapabilityExpansionExcludedFile) => {
      excludedFiles.set(excludedKey(file), file);
    };
    const addEvidence = (evidence: CapabilityExpansionEdgeEvidence) => {
      edgeEvidence.set(evidenceKey(evidence), evidence);
    };

    for (const seedFile of uniqued(hypothesis.seedFiles).sort((a, b) => a.localeCompare(b))) {
      if (!graphFiles.has(seedFile)) {
        addExcluded({ path: seedFile, reason: "seed file is not present in the code graph" });
        continue;
      }
      if (closureFiles.size >= this.options.maxFilesPerCapability) {
        addExcluded({ path: seedFile, reason: "closure file limit reached" });
        continue;
      }
      if (!closureFiles.has(seedFile)) {
        closureFiles.add(seedFile);
        queue.push({ path: seedFile, depth: 0 });
      }
    }

    let cursor = 0;
    while (cursor < queue.length) {
      const current = queue[cursor];
      cursor += 1;
      if (current.depth >= this.options.maxDepth) continue;

      for (const edge of this.outboundFileEdges(current.path, graph)) {
        const targetPath = edge.to.filePath;
        if (closureFiles.has(targetPath)) {
          addEvidence({ fromPath: current.path, toPath: targetPath, kind: edge.kind, depth: current.depth + 1 });
          continue;
        }
        if (closureFiles.size >= this.options.maxFilesPerCapability) {
          addExcluded({ path: targetPath, reason: "closure file limit reached" });
          continue;
        }
        closureFiles.add(targetPath);
        queue.push({ path: targetPath, depth: current.depth + 1 });
        addEvidence({ fromPath: current.path, toPath: targetPath, kind: edge.kind, depth: current.depth + 1 });
      }
    }

    return { closureFiles, excludedFiles, edgeEvidence };
  }

  private sharedDependencyFiles(traversals: Traversal[], graph: CodeGraph): Set<string> {
    const reachedByCapability = new Map<string, Set<number>>();
    for (let index = 0; index < traversals.length; index += 1) {
      for (const path of traversals[index].closureFiles) {
        const set = reachedByCapability.get(path) ?? new Set<number>();
        set.add(index);
        reachedByCapability.set(path, set);
      }
    }

    const reachedByMultiple = [...reachedByCapability.entries()]
      .filter(([, set]) => set.size > 1)
      .map(([path]) => path);

    const highFanIn = [...reachedByCapability.keys()].filter(
      (path) =>
        isLikelySharedDependency(path) &&
        this.inboundFileSourceCount(path, graph) >= this.options.sharedFanInThreshold,
    );

    return new Set([...reachedByMultiple, ...highFanIn]);
  }
}

export function isLikelySharedDependency(path: string): boolean {
  const lower = path.toLowerCase();
  const components = lower.split("/").filter((c) => c.length > 0);
  const filename = components.at(-1) ?? lower;
  const sharedDirectories = new Set(["common", "config", "lib", "shared", "types", "utils"]);
  return (
    components.some((c) => sharedDirectories.has(c)) ||
    filename === "types.ts" ||
    filename === "types.tsx" ||
    filename === "types.swift" ||
    filename === "types.go" ||
    filename === "types.py" ||
    filename.endsWith("utils.ts") ||
    filename.endsWith("util.ts")
  );
}
