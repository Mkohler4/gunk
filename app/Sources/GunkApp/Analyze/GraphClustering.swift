import Foundation

struct GraphCluster: Equatable, Sendable {
  let nodes: Set<CodeGraphNode>
  let intraEdgeCount: Int
  let outboundEdgeCount: Int
  let inboundEdgeCount: Int

  var filePaths: Set<String> {
    Set(nodes.filter { $0.kind == .file }.map(\.filePath))
  }

  var cohesionScore: Double {
    let total = intraEdgeCount + outboundEdgeCount + inboundEdgeCount
    guard total > 0 else {
      return 1
    }

    return Double(intraEdgeCount) / Double(total)
  }
}

struct GraphClustering: Sendable {
  let graph: CodeGraph

  func connectedComponents() -> [GraphCluster] {
    var unvisited = Set(graph.nodes.filter { $0.kind == .file })
    var clusters: [GraphCluster] = []

    while let start = unvisited.first {
      var component: Set<CodeGraphNode> = []
      var stack = [start]
      unvisited.remove(start)

      while let node = stack.popLast() {
        component.insert(node)

        let adjacent = weakFileNeighbors(of: node).filter { unvisited.contains($0) }
        for neighbor in adjacent {
          unvisited.remove(neighbor)
          stack.append(neighbor)
        }
      }

      clusters.append(cluster(for: component))
    }

    return clusters.sorted { lhs, rhs in
      lhs.filePaths.sorted().joined(separator: "\n") < rhs.filePaths.sorted().joined(separator: "\n")
    }
  }

  func highFanInBridgeFiles(minInbound: Int = 2) -> [CodeGraphNode] {
    graph.nodes
      .filter { $0.kind == .file }
      .filter { graph.inboundEdges(to: $0).count >= minInbound }
      .sorted { $0.filePath < $1.filePath }
  }

  private func weakFileNeighbors(of node: CodeGraphNode) -> Set<CodeGraphNode> {
    let outbound = graph.edges.compactMap { edge -> CodeGraphNode? in
      edge.from == node && edge.to.kind == .file ? edge.to : nil
    }
    let inbound = graph.edges.compactMap { edge -> CodeGraphNode? in
      edge.to == node && edge.from.kind == .file ? edge.from : nil
    }

    return Set(outbound + inbound)
  }

  private func cluster(for fileNodes: Set<CodeGraphNode>) -> GraphCluster {
    let intraEdges = graph.edges.filter { fileNodes.contains($0.from) && fileNodes.contains($0.to) }
    let outboundEdges = graph.edges.filter { fileNodes.contains($0.from) && !fileNodes.contains($0.to) }
    let inboundEdges = graph.edges.filter { !fileNodes.contains($0.from) && fileNodes.contains($0.to) }

    return GraphCluster(
      nodes: fileNodes,
      intraEdgeCount: intraEdges.count,
      outboundEdgeCount: outboundEdges.count,
      inboundEdgeCount: inboundEdges.count
    )
  }
}
