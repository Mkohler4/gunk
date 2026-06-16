import Foundation

/// The portability readout persisted into `gunk.yml` and rendered by the module
/// page (T-10.6): *to run this elsewhere, you need* a `runtime`, some
/// `packages`, and some env vars. Mirrors the engine's `ModuleRequirements`.
///
/// The engine extraction path (auto-accepted modules) fills all three from the
/// per-module capability fingerprint. This Swift extractor handles the manual
/// approve path and persists what it can derive cheaply and faithfully —
/// `runtime` from the repo's manifests — leaving `packages`/`env` empty rather
/// than over-reporting the whole repo's dependencies as the module's.
struct ModuleRequirements: Equatable, Sendable {
  var runtime: String?
  var packages: [String]
  var env: [String]

  static let empty = ModuleRequirements(runtime: nil, packages: [], env: [])

  var isEmpty: Bool {
    runtime == nil && packages.isEmpty && env.isEmpty
  }
}

/// Derives the runtime line (`Python ≥ 3.11`, `Node ≥ 18`, …) from a source
/// repo's dependency manifests, preferring the one whose runtime matches the
/// module's language. Falls back to the bare language name when no constraint
/// is parseable and to `nil` only when even the language is unknown — show what
/// is parseable, omit what is not.
struct RequirementsDeriver {
  private static let manifestBasenames: Set<String> = [
    "package.json",
    "pyproject.toml",
    "requirements.txt",
    "go.mod",
    "cargo.toml",
    "package.swift",
    "pubspec.yaml",
  ]

  func derive(language: String?, sourceRoot: URL, fileManager: FileManager = .default) -> ModuleRequirements {
    let manifests = manifestContents(sourceRoot: sourceRoot, fileManager: fileManager)
    return ModuleRequirements(
      runtime: deriveRuntime(language: language, manifests: manifests),
      packages: [],
      env: []
    )
  }

  func deriveRuntime(language: String?, manifests: [String: String]) -> String? {
    var candidates: [(name: String, version: String?)] = []
    for (path, contents) in manifests {
      if let candidate = runtimeFromManifest(path: path, contents: contents) {
        candidates.append(candidate)
      }
    }

    let languageName = Self.humanizeLanguage(language)
    let preferred = candidates.first { languageName != nil && $0.name == languageName }
      ?? candidates.first

    if let preferred {
      if let version = preferred.version {
        return "\(preferred.name) \(version)"
      }
      return preferred.name
    }
    return languageName
  }

  private func manifestContents(sourceRoot: URL, fileManager: FileManager) -> [String: String] {
    var manifests: [String: String] = [:]
    for basename in Self.manifestBasenames {
      let candidates = [
        sourceRoot.appendingPathComponent(basename),
        // Manifests are conventionally lowercased; also try the canonical case.
        sourceRoot.appendingPathComponent(canonicalCase(of: basename))
      ]
      for url in candidates {
        guard manifests[basename] == nil,
              fileManager.fileExists(atPath: url.path),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
          continue
        }
        manifests[basename] = contents
      }
    }
    return manifests
  }

  private func canonicalCase(of basename: String) -> String {
    switch basename {
    case "package.swift":
      return "Package.swift"
    case "cargo.toml":
      return "Cargo.toml"
    default:
      return basename
    }
  }

  private func runtimeFromManifest(path: String, contents: String) -> (name: String, version: String?)? {
    let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()

    switch name {
    case "package.json":
      let constraint = firstMatch(in: contents, pattern: #""node"\s*:\s*"([^"]+)""#)
      return ("Node", Self.formatVersion(constraint))
    case "pyproject.toml":
      let constraint = firstMatch(in: contents, pattern: #"requires-python\s*=\s*["']([^"']+)["']"#)
      return ("Python", Self.formatVersion(constraint))
    case "requirements.txt":
      return ("Python", nil)
    case "go.mod":
      let constraint = firstMatch(in: contents, pattern: #"(?m)^go\s+([0-9]+(?:\.[0-9]+){0,2})"#)
      return ("Go", Self.formatVersion(constraint))
    case "cargo.toml":
      let constraint = firstMatch(in: contents, pattern: #"rust-version\s*=\s*["']([^"']+)["']"#)
      return ("Rust", Self.formatVersion(constraint))
    case "package.swift":
      let constraint = firstMatch(in: contents, pattern: #"swift-tools-version:\s*([0-9.]+)"#)
      return ("Swift", Self.formatVersion(constraint))
    case "pubspec.yaml":
      let constraint = firstMatch(in: contents, pattern: #"sdk:\s*["']?([^"'\n]+)"#)
      return ("Dart", Self.formatVersion(constraint))
    default:
      return nil
    }
  }

  private func firstMatch(in text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
          let captureRange = Range(match.range(at: 1), in: text) else {
      return nil
    }
    return String(text[captureRange])
  }

  static func formatVersion(_ raw: String?) -> String? {
    guard let raw else {
      return nil
    }
    guard let regex = try? NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+){0,2})"#) else {
      return nil
    }
    let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
    guard let match = regex.firstMatch(in: raw, range: range),
          let captureRange = Range(match.range(at: 1), in: raw) else {
      return nil
    }
    return "≥ \(raw[captureRange])"
  }

  static func humanizeLanguage(_ language: String?) -> String? {
    guard let language else {
      return nil
    }
    let normalized = language.trimmingCharacters(in: .whitespaces)
    guard !normalized.isEmpty else {
      return nil
    }

    let known: [String: String] = [
      "python": "Python",
      "typescript": "Node",
      "javascript": "Node",
      "node": "Node",
      "go": "Go",
      "rust": "Rust",
      "swift": "Swift",
      "dart": "Dart",
      "java": "Java",
      "kotlin": "Kotlin",
      "ruby": "Ruby",
      "php": "PHP",
      "csharp": "C#"
    ]
    if let mapped = known[normalized.lowercased()] {
      return mapped
    }
    return normalized.prefix(1).uppercased() + normalized.dropFirst()
  }
}
