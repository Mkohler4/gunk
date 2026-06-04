import Foundation

final class SourceDetector {
  private let fileManager: FileManager

  private let projectMarkerNames: Set<String> = [
    "package.json",
    "Package.swift",
    "pyproject.toml",
    "Cargo.toml",
    "go.mod"
  ]

  private let sourceFileExtensions: Set<String> = [
    "c",
    "cc",
    "cpp",
    "cs",
    "css",
    "go",
    "h",
    "hpp",
    "html",
    "java",
    "js",
    "jsx",
    "kt",
    "m",
    "mm",
    "php",
    "py",
    "rb",
    "rs",
    "swift",
    "ts",
    "tsx"
  ]

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func detect(folder: URL) throws -> [URL] {
    let folder = folder.standardizedFileURL

    guard isDirectory(folder) else {
      return []
    }

    if try looksLikeProject(folder) {
      return [folder]
    }

    let childProjects = try childDirectories(of: folder)
      .filter { try looksLikeProject($0) }

    return childProjects.isEmpty ? [folder] : childProjects
  }

  private func looksLikeProject(_ folder: URL) throws -> Bool {
    let children = try contentsOfDirectory(folder)

    for child in children {
      if projectMarkerNames.contains(child.lastPathComponent) {
        return true
      }

      if isRootSourceFile(child) {
        return true
      }
    }

    return false
  }

  private func childDirectories(of folder: URL) throws -> [URL] {
    try contentsOfDirectory(folder)
      .filter(isDirectory)
  }

  private func contentsOfDirectory(_ folder: URL) throws -> [URL] {
    try fileManager.contentsOfDirectory(
      at: folder,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    )
    .map(\.standardizedFileURL)
    .sorted { lhs, rhs in lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending }
  }

  private func isDirectory(_ url: URL) -> Bool {
    var isDirectory = ObjCBool(false)
    return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  private func isRootSourceFile(_ url: URL) -> Bool {
    var isDirectory = ObjCBool(false)
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
      return false
    }

    let fileExtension = url.pathExtension.lowercased()
    return !fileExtension.isEmpty && sourceFileExtensions.contains(fileExtension)
  }
}
