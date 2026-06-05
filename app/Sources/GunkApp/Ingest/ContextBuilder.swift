import Foundation

final class ContextBuilder {
  static let truncationMarker = "\n[...repo map truncated at cluster boundary...]"

  private let fileManager: FileManager
  private let symbolExtractor: SymbolExtractor
  private let manifestParser: DependencyManifestParser
  private let routeDetector: RouteDetector
  private let fingerprintBuilder: CapabilityFingerprintBuilder

  init(
    fileManager: FileManager = .default,
    symbolExtractor: SymbolExtractor = TreeSitterSymbolExtractor(),
    manifestParser: DependencyManifestParser = DependencyManifestParser(),
    routeDetector: RouteDetector = RouteDetector(),
    fingerprintBuilder: CapabilityFingerprintBuilder = CapabilityFingerprintBuilder()
  ) {
    self.fileManager = fileManager
    self.symbolExtractor = symbolExtractor
    self.manifestParser = manifestParser
    self.routeDetector = routeDetector
    self.fingerprintBuilder = fingerprintBuilder
  }

  func build(files: [ScannedFile], budgetTokens: Int) throws -> String {
    try buildRepoMap(files: files).serialized(budgetTokens: budgetTokens)
  }

  func buildRepoMap(files: [ScannedFile]) throws -> RepoMap {
    let sortedFiles = files.sorted { $0.relpath < $1.relpath }
    let contentsByPath = try readContents(files: sortedFiles)
    let fileSymbols = sortedFiles.map { file in
      symbols(for: file, contents: contentsByPath[file.relpath] ?? "")
    }
    let manifests = manifestParser.parse(manifests: manifestContents(contentsByPath))
    let resolver = ImportResolver(config: .init(sourceFiles: Set(sortedFiles.map(\.relpath))))
    let graph = CodeGraphBuilder(resolver: resolver).build(files: fileSymbols, contentsByPath: contentsByPath)
    let clustering = GraphClustering(graph: graph)
    let clusters = clustering.connectedComponents()
    let bridgeFiles = Set(clustering.highFanInBridgeFiles(minInbound: 2).map(\.filePath))
    let fingerprints = fingerprintBuilder.fingerprints(
      files: fileSymbols,
      manifests: manifests,
      contentsByPath: contentsByPath
    )
    let fingerprintsByPath = Dictionary(uniqueKeysWithValues: fingerprints.map { ($0.filePath, $0) })
    let clusterIdsByPath = clusterIds(clusters: clusters)

    let repoClusters = clusters.enumerated().map { index, cluster in
      let id = "c\(index + 1)"
      let aggregate = fingerprintBuilder.aggregate(fingerprints, filePaths: cluster.filePaths)
      return RepoMapCluster(
        id: id,
        filePaths: cluster.filePaths.sorted(),
        cohesionScore: cluster.cohesionScore,
        bridgeFiles: cluster.filePaths.filter { bridgeFiles.contains($0) }.sorted(),
        capabilityHints: Array(aggregate.capabilityHints).sortedForRepoMap(),
        routes: aggregate.routes.sortedForRepoMap()
      )
    }

    let repoFiles = sortedFiles.map { file in
      let symbols = fileSymbols.first { $0.path == file.relpath }
      let fingerprint = fingerprintsByPath[file.relpath]
      let contents = contentsByPath[file.relpath] ?? ""

      return RepoMapFile(
        path: file.relpath,
        size: file.size,
        clusterId: clusterIdsByPath[file.relpath],
        exports: (symbols?.exports ?? []).sortedForRepoMap(),
        keySymbols: keySymbols(symbols?.symbols ?? []),
        imports: repoImports(symbols?.imports ?? [], resolver: resolver, from: file.relpath),
        routes: (fingerprint?.routes ?? []).sortedForRepoMap(),
        envVars: Array(fingerprint?.envVars ?? []).sorted(),
        configKeys: Array(fingerprint?.configKeys ?? []).sorted(),
        capabilityHints: Array(fingerprint?.capabilityHints ?? []).sortedForRepoMap(),
        snippets: snippets(for: file, contents: contents, routes: fingerprint?.routes ?? [], manifests: manifests)
      )
    }

    return RepoMap(
      files: repoFiles,
      clusters: repoClusters,
      externalDependencies: graph.externalDependencies.mapValues { Array($0).sorted() }
    )
  }

  static func estimatedTokens(for text: String) -> Int {
    Int(ceil(Double(text.count) / 4.0))
  }

  private func readContents(files: [ScannedFile]) throws -> [String: String] {
    try Dictionary(uniqueKeysWithValues: files.map { file in
      let data = try Data(contentsOf: file.url)
      return (file.relpath, String(decoding: data, as: UTF8.self))
    })
  }

  private func symbols(for file: ScannedFile, contents: String) -> FileSymbols {
    do {
      return try symbolExtractor.extract(file: SymbolFile(path: file.relpath, contents: contents))
    } catch {
      return FileSymbols(path: file.relpath, language: LanguageKind(path: file.relpath), symbols: [], imports: [], exports: [])
    }
  }

  private func manifestContents(_ contentsByPath: [String: String]) -> [String: String] {
    contentsByPath.filter { path, _ in
      let basename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
      return [
        "package.json",
        "package.swift",
        "pyproject.toml",
        "requirements.txt",
        "go.mod",
        "cargo.toml"
      ].contains(basename)
    }
  }

  private func clusterIds(clusters: [GraphCluster]) -> [String: String] {
    var ids: [String: String] = [:]
    for (index, cluster) in clusters.enumerated() {
      for path in cluster.filePaths {
        ids[path] = "c\(index + 1)"
      }
    }

    return ids
  }

  private func keySymbols(_ symbols: [Symbol]) -> [Symbol] {
    symbols
      .sortedForRepoMap()
      .prefix(8)
      .map { $0 }
  }

  private func repoImports(_ imports: [ImportRef], resolver: ImportResolver, from path: String) -> [RepoMapImport] {
    imports
      .map { importRef in
        RepoMapImport(
          specifier: importRef.moduleSpecifier,
          target: resolver.resolve(importRef.moduleSpecifier, from: path) ?? importRef.resolvedTarget
        )
      }
      .sorted { lhs, rhs in
        if lhs.specifier != rhs.specifier {
          return lhs.specifier < rhs.specifier
        }

        return (lhs.target ?? "") < (rhs.target ?? "")
      }
  }

  private func snippets(
    for file: ScannedFile,
    contents: String,
    routes: [RouteSurface],
    manifests: [DependencyManifest]
  ) -> [RepoMapSnippet] {
    var snippets: [RepoMapSnippet] = []
    let lines = contents.components(separatedBy: .newlines)

    for route in routes.sortedForRepoMap().prefix(4) {
      if lines.indices.contains(route.line - 1) {
        snippets.append(RepoMapSnippet(kind: "route", line: route.line, text: lines[route.line - 1].trimmingCharacters(in: .whitespaces)))
      }
    }

    if let manifest = manifests.first(where: { $0.path == file.relpath }), !manifest.dependencies.isEmpty {
      snippets.append(
        RepoMapSnippet(
          kind: "manifest",
          line: 1,
          text: "dependencies: \(manifest.dependencies.sorted().prefix(12).joined(separator: ", "))"
        )
      )
    }

    return snippets
  }
}

private extension Array where Element == CapabilityHint {
  func sortedForRepoMap() -> [CapabilityHint] {
    sorted { lhs, rhs in
      if lhs.library != rhs.library {
        return lhs.library < rhs.library
      }

      return lhs.labels.sorted().joined(separator: "/") < rhs.labels.sorted().joined(separator: "/")
    }
  }
}

private extension Array where Element == ExportRef {
  func sortedForRepoMap() -> [ExportRef] {
    sorted { lhs, rhs in
      if lhs.line != rhs.line {
        return lhs.line < rhs.line
      }

      return lhs.name < rhs.name
    }
  }
}

private extension Array where Element == RouteSurface {
  func sortedForRepoMap() -> [RouteSurface] {
    sorted { lhs, rhs in
      if lhs.line != rhs.line {
        return lhs.line < rhs.line
      }
      if lhs.path != rhs.path {
        return lhs.path < rhs.path
      }

      return lhs.method < rhs.method
    }
  }
}

private extension Array where Element == Symbol {
  func sortedForRepoMap() -> [Symbol] {
    sorted { lhs, rhs in
      if lhs.line != rhs.line {
        return lhs.line < rhs.line
      }

      return lhs.name < rhs.name
    }
  }
}
