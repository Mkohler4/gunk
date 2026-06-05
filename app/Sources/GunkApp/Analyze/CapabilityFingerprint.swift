import Foundation

struct CapabilityFingerprint: Equatable, Sendable {
  let filePath: String
  let importedDependencies: Set<String>
  let routes: [RouteSurface]
  let publicExports: [ExportRef]
  let envVars: Set<String>
  let configKeys: Set<String>
  let namingTokens: Set<String>
  let capabilityHints: Set<CapabilityHint>
}

struct ClusterCapabilityFingerprint: Equatable, Sendable {
  let filePaths: Set<String>
  let importedDependencies: Set<String>
  let routes: [RouteSurface]
  let publicExports: [ExportRef]
  let envVars: Set<String>
  let configKeys: Set<String>
  let namingTokens: Set<String>
  let capabilityHints: Set<CapabilityHint>

  var hasPublicSurface: Bool {
    !routes.isEmpty || !publicExports.isEmpty
  }
}

struct CapabilityFingerprintBuilder: Sendable {
  private let lexicon: CapabilityLexicon
  private let routeDetector: RouteDetector

  init(lexicon: CapabilityLexicon = .default, routeDetector: RouteDetector = RouteDetector()) {
    self.lexicon = lexicon
    self.routeDetector = routeDetector
  }

  func fingerprints(
    files: [FileSymbols],
    manifests: [DependencyManifest],
    contentsByPath: [String: String]
  ) -> [CapabilityFingerprint] {
    let declaredDependencies = Set(manifests.flatMap(\.dependencies))

    return files.map { file in
      let contents = contentsByPath[file.path] ?? ""
      let importedDependencies = dependenciesImported(by: file, declaredDependencies: declaredDependencies)
      let hints = Set(importedDependencies.compactMap { lexicon.hint(for: $0) })

      return CapabilityFingerprint(
        filePath: file.path,
        importedDependencies: importedDependencies,
        routes: routeDetector.detect(path: file.path, contents: contents),
        publicExports: file.exports,
        envVars: envVars(in: contents),
        configKeys: configKeys(in: contents),
        namingTokens: namingTokens(for: file),
        capabilityHints: hints
      )
    }
    .sorted { $0.filePath < $1.filePath }
  }

  func aggregate(_ fingerprints: [CapabilityFingerprint], filePaths: Set<String>) -> ClusterCapabilityFingerprint {
    let included = fingerprints.filter { filePaths.contains($0.filePath) }

    return ClusterCapabilityFingerprint(
      filePaths: filePaths,
      importedDependencies: Set(included.flatMap(\.importedDependencies)),
      routes: included.flatMap(\.routes),
      publicExports: included.flatMap(\.publicExports),
      envVars: Set(included.flatMap(\.envVars)),
      configKeys: Set(included.flatMap(\.configKeys)),
      namingTokens: Set(included.flatMap(\.namingTokens)),
      capabilityHints: Set(included.flatMap(\.capabilityHints))
    )
  }

  private func dependenciesImported(by file: FileSymbols, declaredDependencies: Set<String>) -> Set<String> {
    Set(file.imports.compactMap { importRef in
      declaredDependencies.first { dependency in
        importMatchesDependency(importRef.moduleSpecifier, dependency: dependency)
      }
    })
  }

  private func importMatchesDependency(_ specifier: String, dependency: String) -> Bool {
    let normalizedSpecifier = normalizePackageName(packageRoot(for: specifier))
    let normalizedDependency = normalizePackageName(dependency)

    return normalizedSpecifier == normalizedDependency
      || normalizedSpecifier.hasPrefix("\(normalizedDependency)/")
      || normalizedDependency.hasPrefix("\(normalizedSpecifier)/")
  }

  private func packageRoot(for specifier: String) -> String {
    guard specifier.hasPrefix("@") else {
      return specifier.split(separator: "/").first.map(String.init) ?? specifier
    }

    let parts = specifier.split(separator: "/").map(String.init)
    guard parts.count >= 2 else {
      return specifier
    }

    return "\(parts[0])/\(parts[1])"
  }

  private func normalizePackageName(_ name: String) -> String {
    name.lowercased()
      .replacingOccurrences(of: "_", with: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func envVars(in contents: String) -> Set<String> {
    let patterns = [
      #"process\.env\.([A-Za-z_][A-Za-z0-9_]*)"#,
      #"process\.env\[['"]([A-Za-z_][A-Za-z0-9_]*)['"]\]"#,
      #"os\.environ\[['"]([A-Za-z_][A-Za-z0-9_]*)['"]\]"#,
      #"getenv\(['"]([A-Za-z_][A-Za-z0-9_]*)['"]\)"#,
      #"Environment\.GetEnvironmentVariable\(['"]([A-Za-z_][A-Za-z0-9_]*)['"]\)"#
    ]

    return Set(patterns.flatMap { pattern in
      analysisMatches(in: contents, pattern: pattern).compactMap(\.first)
    })
  }

  private func configKeys(in contents: String) -> Set<String> {
    let patterns = [
      #"config\.get\(['"]([A-Za-z0-9_\-\.]+)['"]\)"#,
      #"getConfig\(['"]([A-Za-z0-9_\-\.]+)['"]\)"#,
      #"settings\.([A-Za-z_][A-Za-z0-9_]*)"#
    ]

    return Set(patterns.flatMap { pattern in
      analysisMatches(in: contents, pattern: pattern).compactMap(\.first)
    })
  }

  private func namingTokens(for file: FileSymbols) -> Set<String> {
    let pathTokens = file.path
      .replacingOccurrences(of: ".", with: "/")
      .split(separator: "/")
      .map(String.init)
    let symbolTokens = file.symbols.flatMap { splitIdentifier($0.name) }
    let exportTokens = file.exports.flatMap { splitIdentifier($0.name) }

    return Set((pathTokens + symbolTokens + exportTokens)
      .flatMap(splitIdentifier)
      .map { $0.lowercased() }
      .filter { $0.count > 2 })
  }

  private func splitIdentifier(_ value: String) -> [String] {
    value
      .replacingOccurrences(of: "-", with: "_")
      .split(separator: "_")
      .flatMap { part in
        part.splitBeforeUppercase()
      }
  }
}

private extension Substring {
  func splitBeforeUppercase() -> [String] {
    var words: [String] = []
    var current = ""

    for character in self {
      if character.isUppercase, !current.isEmpty {
        words.append(current)
        current = ""
      }

      current.append(character)
    }

    if !current.isEmpty {
      words.append(current)
    }

    return words
  }
}
