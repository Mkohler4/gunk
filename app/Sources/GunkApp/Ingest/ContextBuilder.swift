import Foundation

final class ContextBuilder {
  static let truncationMarker = "\n[...truncated for token budget...]"

  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func build(files: [ScannedFile], budgetTokens: Int) throws -> String {
    let charBudget = max(0, budgetTokens * 4)
    var remaining = charBudget
    var result = ""
    var didTruncate = false

    func append(_ text: String) {
      guard remaining > 0 else {
        didTruncate = true
        return
      }

      if text.count <= remaining {
        result += text
        remaining -= text.count
      } else {
        let marker = ContextBuilder.truncationMarker
        let prefixCount = max(0, remaining - marker.count)
        if prefixCount > 0 {
          result += String(text.prefix(prefixCount))
          remaining -= prefixCount
        }

        if remaining >= marker.count {
          result += marker
          remaining -= marker.count
        }
        didTruncate = true
      }
    }

    let sortedFiles = files.sorted { lhs, rhs in
      lhs.relpath.localizedStandardCompare(rhs.relpath) == .orderedAscending
    }

    append("File tree:\n")
    for file in sortedFiles {
      append("- \(file.relpath) (\(file.size) bytes)\n")
    }

    append("\nSelected files:\n")
    for file in prioritized(sortedFiles) {
      guard remaining > ContextBuilder.truncationMarker.count else {
        didTruncate = true
        break
      }

      let contents = try textContents(of: file.url)
      append("\n--- \(file.relpath) ---\n")
      append(contents)
      append(contents.hasSuffix("\n") ? "" : "\n")
    }

    if didTruncate && !result.contains(ContextBuilder.truncationMarker) {
      let marker = ContextBuilder.truncationMarker
      if result.count + marker.count <= charBudget {
        result += marker
      }
    }

    return result
  }

  static func estimatedTokens(for text: String) -> Int {
    Int(ceil(Double(text.count) / 4.0))
  }

  private func prioritized(_ files: [ScannedFile]) -> [ScannedFile] {
    files.sorted { lhs, rhs in
      let lhsScore = priority(for: lhs)
      let rhsScore = priority(for: rhs)

      if lhsScore != rhsScore {
        return lhsScore < rhsScore
      }

      if lhs.size != rhs.size {
        return lhs.size < rhs.size
      }

      return lhs.relpath.localizedStandardCompare(rhs.relpath) == .orderedAscending
    }
  }

  private func priority(for file: ScannedFile) -> Int {
    let basename = URL(fileURLWithPath: file.relpath).lastPathComponent.lowercased()

    if basename == "readme.md" || basename == "readme" {
      return 0
    }

    if [
      "package.json",
      "package.swift",
      "pyproject.toml",
      "cargo.toml",
      "go.mod"
    ].contains(basename) {
      return 1
    }

    if basename.hasPrefix("main.")
      || basename.hasPrefix("index.")
      || basename == "app.swift" {
      return 2
    }

    return 3
  }

  private func textContents(of url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    return String(decoding: data, as: UTF8.self)
  }
}
