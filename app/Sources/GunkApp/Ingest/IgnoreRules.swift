import Darwin
import Foundation

struct IgnoreRules {
  enum Decision: Equatable {
    case include
    case skip
  }

  private let patterns: [Pattern]

  init(patterns: [String] = []) {
    self.patterns = patterns.compactMap(Pattern.init(rawValue:))
  }

  static func load(sourceRoot: URL, fileManager: FileManager = .default) throws -> IgnoreRules {
    let ignoreURL = sourceRoot.appendingPathComponent(".gunkignore")

    guard fileManager.fileExists(atPath: ignoreURL.path) else {
      return IgnoreRules()
    }

    let contents = try String(contentsOf: ignoreURL, encoding: .utf8)
    return IgnoreRules(patterns: contents.components(separatedBy: .newlines))
  }

  func decision(relpath: String, isDirectory: Bool) -> Decision {
    let normalized = normalize(relpath)
    let basename = URL(fileURLWithPath: normalized).lastPathComponent

    if isDefaultIgnored(relpath: normalized, basename: basename, isDirectory: isDirectory) {
      return .skip
    }

    if isLikelySecret(relpath: normalized, basename: basename) {
      return .skip
    }

    if patterns.contains(where: { $0.matches(relpath: normalized, basename: basename, isDirectory: isDirectory) }) {
      return .skip
    }

    return .include
  }

  private func isDefaultIgnored(relpath: String, basename: String, isDirectory: Bool) -> Bool {
    if basename == ".DS_Store" || basename == ".gunkignore" {
      return true
    }

    guard isDirectory else {
      return false
    }

    return [".git", "node_modules", "build", "dist", ".build"].contains(basename)
      || relpath.hasSuffix("/.git")
      || relpath.hasSuffix("/node_modules")
      || relpath.hasSuffix("/build")
      || relpath.hasSuffix("/dist")
      || relpath.hasSuffix("/.build")
  }

  private func isLikelySecret(relpath: String, basename: String) -> Bool {
    let candidates = [basename, relpath]
    let secretPatterns = [
      ".env*",
      "*.pem",
      "*.key",
      "id_rsa*",
      "credentials*",
      "*.p12",
      "*.pfx"
    ]

    return secretPatterns.contains { pattern in
      candidates.contains { candidate in
        fnmatch(pattern, candidate, FNM_CASEFOLD) == 0
      }
    }
  }

  private func normalize(_ path: String) -> String {
    path
      .replacingOccurrences(of: "\\", with: "/")
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }
}

private struct Pattern {
  private let value: String
  private let directoryOnly: Bool
  private let anchored: Bool

  init?(rawValue: String) {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
      return nil
    }

    self.directoryOnly = trimmed.hasSuffix("/")
    self.anchored = trimmed.contains("/")
    self.value = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }

  func matches(relpath: String, basename: String, isDirectory: Bool) -> Bool {
    if directoryOnly && !isDirectory {
      return false
    }

    if anchored {
      return fnmatch(value, relpath, FNM_CASEFOLD) == 0
        || relpath.hasPrefix(value + "/")
    }

    return fnmatch(value, basename, FNM_CASEFOLD) == 0
      || (isDirectory && basename == value)
  }
}
