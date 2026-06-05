import Foundation

struct ImportResolver: Sendable {
  struct Config: Equatable, Sendable {
    let sourceFiles: Set<String>
    let tsconfigPaths: [String: [String]]

    init(sourceFiles: Set<String>, tsconfigPaths: [String: [String]] = [:]) {
      self.sourceFiles = Set(sourceFiles.map(Self.normalize(path:)))
      self.tsconfigPaths = tsconfigPaths
    }

    private static func normalize(path: String) -> String {
      path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    }
  }

  private let config: Config
  private let extensions = ["", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".py", ".swift", ".go"]

  init(config: Config) {
    self.config = config
  }

  func resolve(_ specifier: String, from sourcePath: String) -> String? {
    if specifier.hasPrefix(".") {
      return resolveRelative(specifier, from: sourcePath)
    }

    if let aliased = resolveAlias(specifier) {
      return aliased
    }

    return resolveCandidate(specifier)
  }

  private func resolveRelative(_ specifier: String, from sourcePath: String) -> String? {
    let sourceDirectory = (sourcePath as NSString).deletingLastPathComponent
    return resolveCandidate(normalize(path: "\(sourceDirectory)/\(specifier)"))
  }

  private func resolveAlias(_ specifier: String) -> String? {
    for (pattern, targets) in config.tsconfigPaths {
      guard let captured = captureAliasWildcard(specifier: specifier, pattern: pattern) else {
        continue
      }

      for target in targets {
        let candidate = target.replacingOccurrences(of: "*", with: captured)
        if let resolved = resolveCandidate(candidate) {
          return resolved
        }
      }
    }

    return nil
  }

  private func resolveCandidate(_ candidate: String) -> String? {
    let normalizedCandidate = normalize(path: candidate)

    for suffix in extensions {
      let path = normalizedCandidate + suffix
      if config.sourceFiles.contains(path) {
        return path
      }
    }

    for suffix in extensions.dropFirst() {
      let indexPath = "\(normalizedCandidate)/index\(suffix)"
      if config.sourceFiles.contains(indexPath) {
        return indexPath
      }
    }

    return nil
  }

  private func captureAliasWildcard(specifier: String, pattern: String) -> String? {
    guard let wildcardRange = pattern.range(of: "*") else {
      return specifier == pattern ? "" : nil
    }

    let prefix = String(pattern[..<wildcardRange.lowerBound])
    let suffix = String(pattern[wildcardRange.upperBound...])

    guard specifier.hasPrefix(prefix), specifier.hasSuffix(suffix) else {
      return nil
    }

    return String(specifier.dropFirst(prefix.count).dropLast(suffix.count))
  }

  private func normalize(path: String) -> String {
    var components: [String] = []

    for component in path.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
      switch component {
      case ".":
        continue
      case "..":
        _ = components.popLast()
      default:
        components.append(component)
      }
    }

    return components.joined(separator: "/")
  }
}
