import {
  type CodeGraph as BaseCodeGraph,
  type CodeGraphEdge,
  type CodeGraphEdgeKind,
  type CodeGraphNode,
  fileNode,
  type FileSymbols,
  type Symbol,
} from "../models.js";
import { ImportResolver } from "./importResolver.js";

export interface CodeGraph extends BaseCodeGraph {
  externalDependencies: Record<string, string[]>;
}

export function symbolNode(symbol: Symbol, path: string): CodeGraphNode {
  return {
    id: `symbol:${path}#${symbol.name}`,
    kind: "symbol",
    filePath: path,
    symbolName: symbol.name,
  };
}

function edgeKey(edge: CodeGraphEdge): string {
  return `${edge.from.id}\u0000${edge.to.id}\u0000${edge.kind}`;
}

function matchesKinds(kind: CodeGraphEdgeKind, kinds: Set<CodeGraphEdgeKind> | undefined): boolean {
  return kinds === undefined || kinds.has(kind);
}

export function outboundEdges(
  graph: CodeGraph,
  node: CodeGraphNode,
  kinds?: Set<CodeGraphEdgeKind>,
): CodeGraphEdge[] {
  return graph.edges.filter(
    (edge) => edge.from.id === node.id && matchesKinds(edge.kind, kinds),
  );
}

export function inboundEdges(
  graph: CodeGraph,
  node: CodeGraphNode,
  kinds?: Set<CodeGraphEdgeKind>,
): CodeGraphEdge[] {
  return graph.edges.filter((edge) => edge.to.id === node.id && matchesKinds(edge.kind, kinds));
}

export function neighbors(
  graph: CodeGraph,
  node: CodeGraphNode,
  kinds?: Set<CodeGraphEdgeKind>,
): CodeGraphNode[] {
  const seen = new Set<string>();
  const out: CodeGraphNode[] = [];
  for (const edge of outboundEdges(graph, node, kinds)) {
    if (!seen.has(edge.to.id)) {
      seen.add(edge.to.id);
      out.push(edge.to);
    }
  }
  return out;
}

export function transitiveClosure(
  graph: CodeGraph,
  node: CodeGraphNode,
  maxDepth: number,
  kinds?: Set<CodeGraphEdgeKind>,
): CodeGraphNode[] {
  if (maxDepth <= 0) {
    return [];
  }

  const visited = new Map<string, CodeGraphNode>();
  let frontier: CodeGraphNode[] = [node];

  for (let depth = 0; depth < maxDepth; depth += 1) {
    const nextById = new Map<string, CodeGraphNode>();
    for (const current of frontier) {
      for (const neighbor of neighbors(graph, current, kinds)) {
        if (neighbor.id !== node.id && !visited.has(neighbor.id)) {
          nextById.set(neighbor.id, neighbor);
        }
      }
    }

    if (nextById.size === 0) {
      break;
    }

    for (const [id, value] of nextById) {
      visited.set(id, value);
    }
    frontier = [...nextById.values()];
  }

  return [...visited.values()];
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function regexMatch(pattern: string, contents: string): boolean {
  try {
    return new RegExp(pattern).test(contents);
  } catch {
    return false;
  }
}

function containsCall(symbolName: string, contents: string): boolean {
  return regexMatch(String.raw`\b${escapeRegExp(symbolName)}\s*\(`, contents);
}

function containsReference(symbolName: string, contents: string): boolean {
  return regexMatch(String.raw`\b${escapeRegExp(symbolName)}\b`, contents);
}

function containsInheritance(symbolName: string, contents: string): boolean {
  const escaped = escapeRegExp(symbolName);
  return (
    regexMatch(String.raw`\bextends\s+${escaped}\b`, contents) ||
    regexMatch(String.raw`:\s*${escaped}\b`, contents)
  );
}

function containsImplementation(symbolName: string, contents: string): boolean {
  return regexMatch(String.raw`\bimplements\s+${escapeRegExp(symbolName)}\b`, contents);
}

interface ExportedSymbol {
  filePath: string;
  symbol: Symbol;
}

function exportedSymbolIndex(files: FileSymbols[]): ExportedSymbol[] {
  const out: ExportedSymbol[] = [];
  for (const file of files) {
    const exportedNames = new Set(file.exports.map((ref) => ref.name));
    for (const symbol of file.symbols) {
      if (exportedNames.has(symbol.name) || file.exports.length === 0) {
        out.push({ filePath: file.path, symbol });
      }
    }
  }
  return out;
}

export class CodeGraphBuilder {
  private readonly resolver: ImportResolver;

  constructor(resolver: ImportResolver) {
    this.resolver = resolver;
  }

  build(files: FileSymbols[], contentsByPath: Record<string, string> = {}): CodeGraph {
    const nodesById = new Map<string, CodeGraphNode>();
    const edgesByKey = new Map<string, CodeGraphEdge>();
    const externalDependencies = new Map<string, Set<string>>();

    const insertNode = (node: CodeGraphNode): void => {
      if (!nodesById.has(node.id)) {
        nodesById.set(node.id, node);
      }
    };
    const insertEdge = (edge: CodeGraphEdge): void => {
      const key = edgeKey(edge);
      if (!edgesByKey.has(key)) {
        edgesByKey.set(key, edge);
      }
    };

    const symbolNodesByPath = new Map<string, CodeGraphNode[]>();
    for (const file of files) {
      symbolNodesByPath.set(
        file.path,
        file.symbols.map((symbol) => symbolNode(symbol, file.path)),
      );
    }
    const exportedSymbols = exportedSymbolIndex(files);

    for (const file of files) {
      const node = fileNode(file.path);
      insertNode(node);
      for (const symbolNodeValue of symbolNodesByPath.get(file.path) ?? []) {
        insertNode(symbolNodeValue);
      }

      for (const importRef of file.imports) {
        const targetPath =
          this.resolver.resolve(importRef.moduleSpecifier, file.path) ?? importRef.resolvedTarget;
        if (!targetPath) {
          if (!externalDependencies.has(file.path)) {
            externalDependencies.set(file.path, new Set());
          }
          externalDependencies.get(file.path)?.add(importRef.moduleSpecifier);
          continue;
        }

        const targetNode = fileNode(targetPath);
        insertNode(targetNode);
        insertEdge({ from: node, to: targetNode, kind: "import" });
      }

      const contents = contentsByPath[file.path];
      if (contents === undefined) {
        continue;
      }

      for (const exported of exportedSymbols) {
        if (exported.filePath === file.path) {
          continue;
        }

        const exportedNode = symbolNode(exported.symbol, exported.filePath);
        insertNode(exportedNode);

        if (containsCall(exported.symbol.name, contents)) {
          insertEdge({ from: node, to: exportedNode, kind: "call" });
        } else if (containsReference(exported.symbol.name, contents)) {
          insertEdge({ from: node, to: exportedNode, kind: "reference" });
        }

        if (containsInheritance(exported.symbol.name, contents)) {
          insertEdge({ from: node, to: exportedNode, kind: "inherit" });
        }

        if (containsImplementation(exported.symbol.name, contents)) {
          insertEdge({ from: node, to: exportedNode, kind: "implements" });
        }
      }
    }

    const externalDependenciesRecord: Record<string, string[]> = {};
    for (const [path, deps] of externalDependencies) {
      externalDependenciesRecord[path] = [...deps];
    }

    return {
      nodes: [...nodesById.values()],
      edges: [...edgesByKey.values()],
      externalDependencies: externalDependenciesRecord,
    };
  }
}
