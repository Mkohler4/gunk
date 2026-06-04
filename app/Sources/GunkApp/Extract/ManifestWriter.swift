import Foundation

struct ManifestInput: Equatable, Sendable {
  let gunk: Gunk
  let tags: [String]
  let files: [String]
  let sourcePath: String
  let sourceCommit: String?
  let license: DetectedLicense
  let redactions: [Redaction]
  let extractedAt: Date
}

struct ManifestArtifact: Equatable, Sendable {
  let manifest: String
  let readme: String
}

final class ManifestWriter {
  private let homeDirectory: URL
  private let isoFormatter: ISO8601DateFormatter

  init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
    self.homeDirectory = homeDirectory.standardizedFileURL
    self.isoFormatter = ISO8601DateFormatter()
    self.isoFormatter.formatOptions = [.withInternetDateTime]
  }

  func artifact(input: ManifestInput) -> ManifestArtifact {
    let entrypoints = entrypoints(from: input.files)
    let manifest = manifestYAML(input: input, entrypoints: entrypoints)
    let readme = readmeMarkdown(input: input, entrypoints: entrypoints)

    return ManifestArtifact(manifest: manifest, readme: readme)
  }

  func homeRelativePath(_ path: String) -> String {
    let sourceURL = URL(fileURLWithPath: path).standardizedFileURL
    let homePath = homeDirectory.path.hasSuffix("/") ? homeDirectory.path : homeDirectory.path + "/"

    if sourceURL.path == homeDirectory.path {
      return "~"
    }

    if sourceURL.path.hasPrefix(homePath) {
      return "~/" + String(sourceURL.path.dropFirst(homePath.count))
    }

    return "~/" + sourceURL.lastPathComponent
  }

  private func manifestYAML(input: ManifestInput, entrypoints: [String]) -> String {
    var lines: [String] = [
      "schema_version: 0",
      "id: \(input.gunk.id)",
      "name: \(yaml(input.gunk.name))"
    ]

    appendList(input.tags, key: "tags", to: &lines)
    lines.append("language: \(yaml(input.gunk.language))")
    lines.append("purpose: \(yaml(input.gunk.purpose))")
    lines.append("deps:")
    lines.append("  package_managers: []")
    lines.append("  packages: []")
    if entrypoints.isEmpty {
      lines.append("entrypoints: []")
    } else {
      lines.append("entrypoints:")
      for entrypoint in entrypoints {
        lines.append("  - path: \(yaml(entrypoint))")
        lines.append("    symbol: null")
      }
    }
    lines.append("provenance:")
    lines.append("  source_path: \(yaml(input.sourcePath))")
    lines.append("  source_commit: \(yaml(input.sourceCommit))")
    lines.append("license:")
    lines.append("  detected: \(yaml(input.license.detected))")
    lines.append("  warning: \(yaml(input.license.warning))")
    lines.append("confidence: \(input.gunk.confidence ?? 0)")
    lines.append("extracted_at: \(yaml(isoFormatter.string(from: input.extractedAt)))")

    if !input.redactions.isEmpty {
      lines.append("redactions:")
      for redaction in input.redactions {
        lines.append("  - path: \(yaml(redaction.path))")
        lines.append("    reason: \(yaml(redaction.reason))")
      }
    }

    return lines.joined(separator: "\n") + "\n"
  }

  private func readmeMarkdown(input: ManifestInput, entrypoints: [String]) -> String {
    var lines: [String] = [
      "# \(input.gunk.name)",
      "",
      input.gunk.purpose ?? "Extracted reusable gunk module.",
      ""
    ]

    if !input.tags.isEmpty {
      lines.append("Tags: \(input.tags.joined(separator: ", "))")
      lines.append("")
    }

    lines.append("## Entrypoints")
    if entrypoints.isEmpty {
      lines.append("- No confident entrypoints were inferred.")
    } else {
      lines.append(contentsOf: entrypoints.map { "- `\($0)`" })
    }

    lines.append("")
    lines.append("Confidence: \(input.gunk.confidence ?? 0)")

    return lines.joined(separator: "\n") + "\n"
  }

  private func entrypoints(from files: [String]) -> [String] {
    let prioritized = files.filter { relpath in
      let basename = URL(fileURLWithPath: relpath).lastPathComponent.lowercased()
      return basename.hasPrefix("main.")
        || basename.hasPrefix("index.")
        || basename == "package.swift"
        || basename == "package.json"
        || basename == "pyproject.toml"
        || basename == "cargo.toml"
        || basename == "go.mod"
        || relpath.lowercased().contains("/route.")
    }

    let candidates = prioritized.isEmpty ? files : prioritized
    return Array(candidates.prefix(5))
  }

  private func appendList(_ values: [String], key: String, to lines: inout [String]) {
    if values.isEmpty {
      lines.append("\(key): []")
      return
    }

    lines.append("\(key):")
    lines.append(contentsOf: values.map { "  - \(yaml($0))" })
  }

  private func yaml(_ value: String?) -> String {
    guard let value else {
      return "null"
    }

    return yaml(value)
  }

  private func yaml(_ value: String) -> String {
    let escaped = value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: "\\n")

    return "\"\(escaped)\""
  }
}
