import Foundation

struct CapabilityExpansionOptions: Equatable, Sendable {
  let maxDepth: Int
  let maxFilesPerCapability: Int
  let sharedFanInThreshold: Int
  let edgeKinds: Set<CodeGraphEdgeKind>

  init(
    maxDepth: Int = 3,
    maxFilesPerCapability: Int = 25,
    sharedFanInThreshold: Int = 3,
    edgeKinds: Set<CodeGraphEdgeKind> = [.call, .import, .implements, .inherit, .reference]
  ) {
    self.maxDepth = maxDepth
    self.maxFilesPerCapability = maxFilesPerCapability
    self.sharedFanInThreshold = sharedFanInThreshold
    self.edgeKinds = edgeKinds
  }
}

struct CapabilityExpansion: Equatable, Sendable {
  let hypothesis: CapabilityHypothesis
  let closureFiles: [String]
  let ownedFiles: [String]
  let sharedDependencyFiles: [String]
  let excludedFiles: [CapabilityExpansionExcludedFile]
  let edgeEvidence: [CapabilityExpansionEdgeEvidence]
}

struct CapabilityExpansionExcludedFile: Equatable, Hashable, Sendable {
  let path: String
  let reason: String
}

struct CapabilityExpansionEdgeEvidence: Equatable, Hashable, Sendable {
  let fromPath: String
  let toPath: String
  let kind: CodeGraphEdgeKind
  let depth: Int
}

struct CapabilityExpander: Sendable {
  let options: CapabilityExpansionOptions

  init(options: CapabilityExpansionOptions = CapabilityExpansionOptions()) {
    self.options = options
  }

  func expand(hypotheses: [CapabilityHypothesis], graph: CodeGraph) -> [CapabilityExpansion] {
    let traversals = hypotheses.map { traversal(for: $0, graph: graph) }
    let sharedFiles = sharedDependencyFiles(from: traversals, graph: graph)

    return zip(hypotheses, traversals).map { hypothesis, traversal in
      let closureFiles = traversal.closureFiles.sorted()
      let sharedDependencyFiles = closureFiles.filter { sharedFiles.contains($0) }

      return CapabilityExpansion(
        hypothesis: hypothesis,
        closureFiles: closureFiles,
        ownedFiles: closureFiles.filter { !sharedFiles.contains($0) },
        sharedDependencyFiles: sharedDependencyFiles,
        excludedFiles: traversal.excludedFiles.sorted(),
        edgeEvidence: traversal.edgeEvidence.sorted()
      )
    }
  }

  private func traversal(for hypothesis: CapabilityHypothesis, graph: CodeGraph) -> Traversal {
    let graphFiles = Set(graph.nodes.filter { $0.kind == .file }.map(\.filePath))
    var closureFiles: Set<String> = []
    var queue: [QueuedFile] = []
    var excludedFiles: Set<CapabilityExpansionExcludedFile> = []
    var edgeEvidence: Set<CapabilityExpansionEdgeEvidence> = []

    for seedFile in hypothesis.seedFiles.uniqued().sorted() {
      guard graphFiles.contains(seedFile) else {
        excludedFiles.insert(
          CapabilityExpansionExcludedFile(path: seedFile, reason: "seed file is not present in the code graph")
        )
        continue
      }

      guard closureFiles.count < options.maxFilesPerCapability else {
        excludedFiles.insert(
          CapabilityExpansionExcludedFile(path: seedFile, reason: "closure file limit reached")
        )
        continue
      }

      if closureFiles.insert(seedFile).inserted {
        queue.append(QueuedFile(path: seedFile, depth: 0))
      }
    }

    var cursor = 0
    while cursor < queue.count {
      let current = queue[cursor]
      cursor += 1

      guard current.depth < options.maxDepth else {
        continue
      }

      for edge in outboundFileEdges(from: current.path, graph: graph) {
        let targetPath = edge.to.filePath

        if closureFiles.contains(targetPath) {
          edgeEvidence.insert(
            CapabilityExpansionEdgeEvidence(
              fromPath: current.path,
              toPath: targetPath,
              kind: edge.kind,
              depth: current.depth + 1
            )
          )
          continue
        }

        guard closureFiles.count < options.maxFilesPerCapability else {
          excludedFiles.insert(
            CapabilityExpansionExcludedFile(path: targetPath, reason: "closure file limit reached")
          )
          continue
        }

        closureFiles.insert(targetPath)
        queue.append(QueuedFile(path: targetPath, depth: current.depth + 1))
        edgeEvidence.insert(
          CapabilityExpansionEdgeEvidence(
            fromPath: current.path,
            toPath: targetPath,
            kind: edge.kind,
            depth: current.depth + 1
          )
        )
      }
    }

    return Traversal(
      closureFiles: closureFiles,
      excludedFiles: excludedFiles,
      edgeEvidence: edgeEvidence
    )
  }

  private func outboundFileEdges(from path: String, graph: CodeGraph) -> [CodeGraphEdge] {
    graph.outboundEdges(from: CodeGraphNode.file(path), kinds: options.edgeKinds)
      .filter { edge in
        edge.to.filePath != path
      }
      .sorted { lhs, rhs in
        if lhs.to.filePath == rhs.to.filePath {
          if lhs.kind == rhs.kind {
            return lhs.to.id < rhs.to.id
          }

          return lhs.kind.rawValue < rhs.kind.rawValue
        }

        return lhs.to.filePath < rhs.to.filePath
      }
  }

  private func sharedDependencyFiles(from traversals: [Traversal], graph: CodeGraph) -> Set<String> {
    var reachedByCapability: [String: Set<Int>] = [:]

    for (index, traversal) in traversals.enumerated() {
      for path in traversal.closureFiles {
        reachedByCapability[path, default: []].insert(index)
      }
    }

    let reachedByMultipleCapabilities = reachedByCapability
      .filter { $0.value.count > 1 }
      .map(\.key)

    let highFanInFiles = reachedByCapability.keys.filter { path in
      isLikelySharedDependency(path)
        && inboundFileSourceCount(for: path, graph: graph) >= options.sharedFanInThreshold
    }

    return Set(reachedByMultipleCapabilities + highFanInFiles)
  }

  private func inboundFileSourceCount(for path: String, graph: CodeGraph) -> Int {
    Set(
      graph.inboundEdges(to: CodeGraphNode.file(path), kinds: options.edgeKinds)
        .filter { $0.from.kind == .file }
        .map(\.from.filePath)
    ).count
  }

  private func isLikelySharedDependency(_ path: String) -> Bool {
    let components = path.lowercased().split(separator: "/").map(String.init)
    let filename = components.last ?? path.lowercased()
    let sharedDirectories: Set<String> = ["common", "config", "lib", "shared", "types", "utils"]

    return components.contains { sharedDirectories.contains($0) }
      || filename == "types.ts"
      || filename == "types.tsx"
      || filename == "types.swift"
      || filename == "types.go"
      || filename == "types.py"
      || filename.hasSuffix("utils.ts")
      || filename.hasSuffix("util.ts")
  }
}

private struct QueuedFile: Equatable {
  let path: String
  let depth: Int
}

private struct Traversal: Equatable {
  let closureFiles: Set<String>
  let excludedFiles: Set<CapabilityExpansionExcludedFile>
  let edgeEvidence: Set<CapabilityExpansionEdgeEvidence>
}

private extension Array where Element: Hashable {
  func uniqued() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}

extension CapabilityExpansionExcludedFile: Comparable {
  static func < (lhs: CapabilityExpansionExcludedFile, rhs: CapabilityExpansionExcludedFile) -> Bool {
    if lhs.path == rhs.path {
      return lhs.reason < rhs.reason
    }

    return lhs.path < rhs.path
  }
}

extension CapabilityExpansionEdgeEvidence: Comparable {
  static func < (lhs: CapabilityExpansionEdgeEvidence, rhs: CapabilityExpansionEdgeEvidence) -> Bool {
    if lhs.fromPath == rhs.fromPath {
      if lhs.toPath == rhs.toPath {
        if lhs.kind == rhs.kind {
          return lhs.depth < rhs.depth
        }

        return lhs.kind.rawValue < rhs.kind.rawValue
      }

      return lhs.toPath < rhs.toPath
    }

    return lhs.fromPath < rhs.fromPath
  }
}
