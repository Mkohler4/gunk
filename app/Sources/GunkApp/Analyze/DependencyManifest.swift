import Foundation

struct DependencyManifest: Equatable, Sendable {
  enum Kind: String, Equatable, Sendable {
    case cargoToml
    case goMod
    case packageJson
    case packageSwift
    case pyprojectToml
    case requirementsTxt
  }

  let path: String
  let kind: Kind
  let dependencies: Set<String>
}

struct DependencyManifestParser: Sendable {
  func parse(path: String, contents: String) -> DependencyManifest? {
    let lowercasedPath = path.lowercased()

    if lowercasedPath.hasSuffix("package.json") {
      return DependencyManifest(path: path, kind: .packageJson, dependencies: parsePackageJSON(contents))
    } else if lowercasedPath.hasSuffix("package.swift") {
      return DependencyManifest(path: path, kind: .packageSwift, dependencies: parsePackageSwift(contents))
    } else if lowercasedPath.hasSuffix("pyproject.toml") {
      return DependencyManifest(path: path, kind: .pyprojectToml, dependencies: parsePyproject(contents))
    } else if lowercasedPath.hasSuffix("requirements.txt") {
      return DependencyManifest(path: path, kind: .requirementsTxt, dependencies: parseRequirements(contents))
    } else if lowercasedPath.hasSuffix("go.mod") {
      return DependencyManifest(path: path, kind: .goMod, dependencies: parseGoMod(contents))
    } else if lowercasedPath.hasSuffix("cargo.toml") {
      return DependencyManifest(path: path, kind: .cargoToml, dependencies: parseCargoToml(contents))
    }

    return nil
  }

  func parse(manifests: [String: String]) -> [DependencyManifest] {
    manifests.compactMap { path, contents in
      parse(path: path, contents: contents)
    }
    .sorted { $0.path < $1.path }
  }

  private func parsePackageJSON(_ contents: String) -> Set<String> {
    guard let data = contents.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return []
    }

    let sections = ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"]
    return Set(sections.flatMap { section -> [String] in
      guard let dependencies = object[section] as? [String: Any] else {
        return []
      }

      return Array(dependencies.keys)
    })
  }

  private func parsePackageSwift(_ contents: String) -> Set<String> {
    Set(analysisMatches(in: contents, pattern: #"\.package\s*\(\s*url:\s*"([^"]+)""#).compactMap { match in
      guard let url = match.first,
            let package = url.split(separator: "/").last else {
        return nil
      }

      return String(package).replacingOccurrences(of: ".git", with: "")
    })
  }

  private func parsePyproject(_ contents: String) -> Set<String> {
    var dependencies = Set<String>()

    for match in analysisMatches(in: contents, pattern: #""([A-Za-z0-9_\-\.]+)(?:[<>=~! ][^"]*)?""#) {
      if let dependency = match.first {
        dependencies.insert(dependency)
      }
    }

    for match in analysisMatches(in: contents, pattern: #"(?m)^\s*([A-Za-z0-9_\-\.]+)\s*=\s*"[^\n"]+""#) {
      if let dependency = match.first {
        dependencies.insert(dependency)
      }
    }

    return dependencies
  }

  private func parseRequirements(_ contents: String) -> Set<String> {
    Set(contents.components(separatedBy: .newlines).compactMap { line in
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
        return nil
      }

      return analysisFirstMatch(in: trimmed, pattern: #"^([A-Za-z0-9_\-\.]+)"#)
    })
  }

  private func parseGoMod(_ contents: String) -> Set<String> {
    Set(analysisMatches(in: contents, pattern: #"(?m)^\s*(?:require\s+)?([A-Za-z0-9_\-\.]+/[A-Za-z0-9_\-\./]+)\s+v[0-9]"#).compactMap(\.first))
  }

  private func parseCargoToml(_ contents: String) -> Set<String> {
    var dependencies = Set<String>()
    var inDependenciesSection = false

    for line in contents.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

      if trimmed.hasPrefix("[") {
        inDependenciesSection = trimmed == "[dependencies]" || trimmed == "[dev-dependencies]"
        continue
      }

      guard inDependenciesSection,
            let dependency = analysisFirstMatch(in: trimmed, pattern: #"^([A-Za-z0-9_\-]+)\s*="#) else {
        continue
      }

      dependencies.insert(dependency)
    }

    return dependencies
  }
}
