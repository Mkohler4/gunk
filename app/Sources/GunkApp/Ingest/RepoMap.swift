import Foundation

struct RepoMap: Equatable, Sendable {
  let files: [RepoMapFile]
  let clusters: [RepoMapCluster]
  let externalDependencies: [String: [String]]

  func serialized(budgetTokens: Int) -> String {
    let charBudget = max(0, budgetTokens * 4)
    guard charBudget > ContextBuilder.truncationMarker.count else {
      return String(ContextBuilder.truncationMarker.prefix(charBudget))
    }

    var output = "repo_map_v1\n"
    output += treeBlock()
    output += "clusters:\n"

    let sortedClusters = clusters.sorted { lhs, rhs in lhs.id < rhs.id }
    for cluster in sortedClusters {
      output += cluster.serialized()
    }

    output += "files:\n"

    var didTruncate = false
    for cluster in prioritizedClusters(sortedClusters) {
      let clusterFiles = files
        .filter { $0.clusterId == cluster.id }
        .sorted { $0.path < $1.path }
      let block = clusterFiles.map { $0.serialized() }.joined()

      if output.count + block.count + ContextBuilder.truncationMarker.count > charBudget {
        didTruncate = true
        break
      }

      output += block
    }

    let unclusteredFiles = files
      .filter { $0.clusterId == nil }
      .sorted { $0.path < $1.path }
    for file in unclusteredFiles {
      let block = file.serialized()
      if output.count + block.count + ContextBuilder.truncationMarker.count > charBudget {
        didTruncate = true
        break
      }

      output += block
    }

    if !externalDependencies.isEmpty {
      let block = externalDependenciesBlock()
      if output.count + block.count + ContextBuilder.truncationMarker.count <= charBudget {
        output += block
      } else {
        didTruncate = true
      }
    }

    if didTruncate {
      output += ContextBuilder.truncationMarker
    }

    if output.count > charBudget {
      let allowed = max(0, charBudget - ContextBuilder.truncationMarker.count)
      output = String(output.prefix(allowed)) + ContextBuilder.truncationMarker
    }

    return output
  }

  private func prioritizedClusters(_ clusters: [RepoMapCluster]) -> [RepoMapCluster] {
    clusters.sorted { lhs, rhs in
      if lhs.importanceScore != rhs.importanceScore {
        return lhs.importanceScore > rhs.importanceScore
      }

      return lhs.id < rhs.id
    }
  }

  private func treeBlock() -> String {
    var output = "tree:\n"
    for file in files.sorted(by: { $0.path < $1.path }) {
      output += "- \(file.path) (\(file.size) bytes)\n"
    }

    return output
  }

  private func externalDependenciesBlock() -> String {
    var output = "external_deps:\n"
    for (path, dependencies) in externalDependencies.sorted(by: { $0.key < $1.key }) {
      output += "- file: \(path)\n"
      output += "  deps: \(dependencies.sorted().joined(separator: ", "))\n"
    }

    return output
  }
}

struct RepoMapCluster: Equatable, Sendable {
  let id: String
  let filePaths: [String]
  let cohesionScore: Double
  let bridgeFiles: [String]
  let capabilityHints: [CapabilityHint]
  let routes: [RouteSurface]

  var importanceScore: Int {
    routes.count * 20 + capabilityHints.count * 15 + bridgeFiles.count * 5 + filePaths.count
  }

  func serialized() -> String {
    var output = "- id: \(id)\n"
    output += "  files: \(filePaths.joined(separator: ", "))\n"
    output += "  cohesion: \(String(format: "%.2f", cohesionScore))\n"

    if !bridgeFiles.isEmpty {
      output += "  bridge_files: \(bridgeFiles.joined(separator: ", "))\n"
    }
    if !capabilityHints.isEmpty {
      output += "  hints: \(capabilityHints.map { $0.serialized() }.joined(separator: ", "))\n"
    }
    if !routes.isEmpty {
      output += "  routes: \(routes.map { $0.serialized() }.joined(separator: ", "))\n"
    }

    return output
  }
}

struct RepoMapFile: Equatable, Sendable {
  let path: String
  let size: Int64
  let clusterId: String?
  let exports: [ExportRef]
  let keySymbols: [Symbol]
  let imports: [RepoMapImport]
  let routes: [RouteSurface]
  let envVars: [String]
  let configKeys: [String]
  let capabilityHints: [CapabilityHint]
  let snippets: [RepoMapSnippet]

  func serialized() -> String {
    var output = "- path: \(path)\n"
    output += "  size: \(size)\n"
    if let clusterId {
      output += "  cluster: \(clusterId)\n"
    }
    if !exports.isEmpty {
      output += "  exports: \(exports.map { $0.serialized() }.joined(separator: ", "))\n"
    }
    if !keySymbols.isEmpty {
      output += "  symbols: \(keySymbols.map { $0.serialized() }.joined(separator: ", "))\n"
    }
    if !imports.isEmpty {
      output += "  imports: \(imports.map { $0.serialized() }.joined(separator: ", "))\n"
    }
    if !routes.isEmpty {
      output += "  routes: \(routes.map { $0.serialized() }.joined(separator: ", "))\n"
    }
    if !envVars.isEmpty {
      output += "  env: \(envVars.joined(separator: ", "))\n"
    }
    if !configKeys.isEmpty {
      output += "  config: \(configKeys.joined(separator: ", "))\n"
    }
    if !capabilityHints.isEmpty {
      output += "  hints: \(capabilityHints.map { $0.serialized() }.joined(separator: ", "))\n"
    }
    if !snippets.isEmpty {
      output += "  snippets:\n"
      for snippet in snippets {
        output += "    - \(snippet.serialized())\n"
      }
    }

    return output
  }
}

struct RepoMapImport: Equatable, Sendable {
  let specifier: String
  let target: String?

  func serialized() -> String {
    if let target {
      return "\(specifier)->\(target)"
    }

    return "\(specifier)->external"
  }
}

struct RepoMapSnippet: Equatable, Sendable {
  let kind: String
  let line: Int
  let text: String

  func serialized() -> String {
    "\(kind)@\(line): \(text.replacingOccurrences(of: "\n", with: " "))"
  }
}

private extension ExportRef {
  func serialized() -> String {
    if let kind {
      return "\(name):\(kind.rawValue)@\(line)"
    }

    return "\(name)@\(line)"
  }
}

private extension Symbol {
  func serialized() -> String {
    "\(name):\(kind.rawValue)@\(line)"
  }
}

private extension CapabilityHint {
  func serialized() -> String {
    "\(library)[\(labels.sorted().joined(separator: "/"))]"
  }
}

private extension RouteSurface {
  func serialized() -> String {
    "\(framework.rawValue):\(method) \(path)@\(line)"
  }
}
