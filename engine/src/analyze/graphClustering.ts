import type { CodeGraphNode } from "../models.js";
import { type CodeGraph, inboundEdges } from "./codeGraph.js";

export interface GraphCluster {
  filePaths: string[];
  cohesionScore: number;
}

function cohesionScore(intra: number, outbound: number, inbound: number): number {
  const total = intra + outbound + inbound;
  if (total <= 0) {
    return 1;
  }
  return intra / total;
}

export class GraphClustering {
  private readonly graph: CodeGraph;

  constructor(graph: CodeGraph) {
    this.graph = graph;
  }

  connectedComponents(): GraphCluster[] {
    const fileNodes = this.graph.nodes
      .filter((node) => node.kind === "file")
      .sort((lhs, rhs) => (lhs.id < rhs.id ? -1 : lhs.id > rhs.id ? 1 : 0));

    const unvisited = new Map<string, CodeGraphNode>();
    for (const node of fileNodes) {
      unvisited.set(node.id, node);
    }

    const clusters: GraphCluster[] = [];

    for (const start of fileNodes) {
      if (!unvisited.has(start.id)) {
        continue;
      }

      const component = new Map<string, CodeGraphNode>();
      const stack: CodeGraphNode[] = [start];
      unvisited.delete(start.id);

      while (stack.length > 0) {
        const node = stack.pop() as CodeGraphNode;
        component.set(node.id, node);

        for (const neighbor of this.weakFileNeighbors(node)) {
          if (unvisited.has(neighbor.id)) {
            unvisited.delete(neighbor.id);
            stack.push(neighbor);
          }
        }
      }

      clusters.push(this.cluster([...component.values()]));
    }

    return clusters.sort((lhs, rhs) => {
      const lhsKey = [...lhs.filePaths].sort().join("\n");
      const rhsKey = [...rhs.filePaths].sort().join("\n");
      return lhsKey < rhsKey ? -1 : lhsKey > rhsKey ? 1 : 0;
    });
  }

  highFanInBridgeFiles(minInbound = 2): CodeGraphNode[] {
    return this.graph.nodes
      .filter((node) => node.kind === "file")
      .filter((node) => inboundEdges(this.graph, node).length >= minInbound)
      .sort((lhs, rhs) => (lhs.filePath < rhs.filePath ? -1 : lhs.filePath > rhs.filePath ? 1 : 0));
  }

  private weakFileNeighbors(node: CodeGraphNode): CodeGraphNode[] {
    const byId = new Map<string, CodeGraphNode>();
    for (const edge of this.graph.edges) {
      if (edge.from.id === node.id && edge.to.kind === "file") {
        byId.set(edge.to.id, edge.to);
      }
      if (edge.to.id === node.id && edge.from.kind === "file") {
        byId.set(edge.from.id, edge.from);
      }
    }
    return [...byId.values()];
  }

  private cluster(fileNodes: CodeGraphNode[]): GraphCluster {
    const ids = new Set(fileNodes.map((node) => node.id));

    let intra = 0;
    let outbound = 0;
    let inbound = 0;
    for (const edge of this.graph.edges) {
      const fromIn = ids.has(edge.from.id);
      const toIn = ids.has(edge.to.id);
      if (fromIn && toIn) {
        intra += 1;
      } else if (fromIn && !toIn) {
        outbound += 1;
      } else if (!fromIn && toIn) {
        inbound += 1;
      }
    }

    const filePaths = fileNodes
      .filter((node) => node.kind === "file")
      .map((node) => node.filePath)
      .sort();

    return {
      filePaths,
      cohesionScore: cohesionScore(intra, outbound, inbound),
    };
  }
}
