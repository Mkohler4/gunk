import Foundation

struct ScannedFile: Equatable, Sendable {
  let url: URL
  let relpath: String
  let size: Int64
}

final class SourceScanner {
  private let fileManager: FileManager
  private let maxFileSizeBytes: Int64
  private let store: Store?
  private let sourceId: Int64?

  init(
    fileManager: FileManager = .default,
    maxFileSizeBytes: Int64 = 512 * 1_024,
    store: Store? = nil,
    sourceId: Int64? = nil
  ) {
    self.fileManager = fileManager
    self.maxFileSizeBytes = maxFileSizeBytes
    self.store = store
    self.sourceId = sourceId
  }

  func scan(folder: URL) throws -> [ScannedFile] {
    let root = folder.standardizedFileURL
    let ignoreRules = try IgnoreRules.load(sourceRoot: root, fileManager: fileManager)
    var files: [ScannedFile] = []

    try walk(root: root, current: root, ignoreRules: ignoreRules, files: &files)

    return files.sorted { lhs, rhs in
      lhs.relpath.localizedStandardCompare(rhs.relpath) == .orderedAscending
    }
  }

  private func walk(
    root: URL,
    current: URL,
    ignoreRules: IgnoreRules,
    files: inout [ScannedFile]
  ) throws {
    for child in try children(of: current) {
      let isDirectory = try child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
      let relpath = relativePath(child, from: root)

      guard ignoreRules.decision(relpath: relpath, isDirectory: isDirectory) == .include else {
        continue
      }

      if isDirectory {
        try walk(root: root, current: child, ignoreRules: ignoreRules, files: &files)
      } else if let scannedFile = try scannedFile(child, relpath: relpath) {
        files.append(scannedFile)
        try persist(scannedFile)
      }
    }
  }

  private func children(of folder: URL) throws -> [URL] {
    try fileManager.contentsOfDirectory(
      at: folder,
      includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
      options: []
    )
    .map(\.standardizedFileURL)
    .sorted { lhs, rhs in lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending }
  }

  private func scannedFile(_ url: URL, relpath: String) throws -> ScannedFile? {
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])

    guard values.isRegularFile == true else {
      return nil
    }

    let size = Int64(values.fileSize ?? 0)
    guard size <= maxFileSizeBytes, try !isBinary(url) else {
      return nil
    }

    return ScannedFile(url: url, relpath: relpath, size: size)
  }

  private func persist(_ scannedFile: ScannedFile) throws {
    guard let store, let sourceId else {
      return
    }

    try store.addSourceFile(
      sourceId: sourceId,
      relpath: scannedFile.relpath,
      size: scannedFile.size
    )
  }

  private func isBinary(_ url: URL) throws -> Bool {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    let prefix = try handle.read(upToCount: 4_096) ?? Data()
    return prefix.contains(0)
  }

  private func relativePath(_ url: URL, from root: URL) -> String {
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    return String(url.path.dropFirst(rootPath.count))
  }
}
