import Foundation

enum ExtractorError: Error, Equatable {
  case sourceNotFound(Int64)
  case invalidRelativePath(String)
  case sourceFileOutsideRoot(String)
}

struct ExtractionResult: Equatable, Sendable {
  let bundleURL: URL
  let manifestURL: URL
  let readmeURL: URL
  let redactions: [Redaction]
}

final class Extractor {
  static let defaultConfidenceThreshold = 0.7

  private let store: Store
  private let gunkHome: URL
  private let confidenceThreshold: Double
  private let fileManager: FileManager
  private let redactor: SecretRedactor
  private let manifestWriter: ManifestWriter
  private let licenseDetector: LicenseDetector
  private let now: () -> Int64

  init(
    store: Store,
    gunkHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gunk"),
    confidenceThreshold: Double = Extractor.defaultConfidenceThreshold,
    fileManager: FileManager = .default,
    redactor: SecretRedactor = SecretRedactor(),
    manifestWriter: ManifestWriter = ManifestWriter(),
    licenseDetector: LicenseDetector = LicenseDetector(),
    now: @escaping () -> Int64 = Store.currentTimeInMilliseconds
  ) {
    self.store = store
    self.gunkHome = gunkHome.standardizedFileURL
    self.confidenceThreshold = confidenceThreshold
    self.fileManager = fileManager
    self.redactor = redactor
    self.manifestWriter = manifestWriter
    self.licenseDetector = licenseDetector
    self.now = now
  }

  @discardableResult
  func extract(gunk: Gunk) throws -> ExtractionResult? {
    guard (gunk.confidence ?? 0) >= confidenceThreshold else {
      return nil
    }

    guard let source = try store.source(id: gunk.sourceId) else {
      throw ExtractorError.sourceNotFound(gunk.sourceId)
    }

    let sourceRoot = URL(fileURLWithPath: source.path).standardizedFileURL
    let bundleURL = gunkHome
      .appendingPathComponent("modules", isDirectory: true)
      .appendingPathComponent(String(gunk.id), isDirectory: true)
    let manifestURL = bundleURL.appendingPathComponent("gunk.yml")
    let readmeURL = bundleURL.appendingPathComponent("README.gunk.md")
    let gunkFiles = try store.filesForGunk(gunkId: gunk.id)
    let tags = try store.listGunkTags(gunkId: gunk.id).map(\.tag)
    var redactions: [Redaction] = []

    if fileManager.fileExists(atPath: bundleURL.path) {
      try fileManager.removeItem(at: bundleURL)
    }
    try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)

    for file in gunkFiles {
      try copyFile(
        relpath: file.relpath,
        sourceRoot: sourceRoot,
        bundleRoot: bundleURL,
        redactions: &redactions
      )
    }

    let extractedAt = now()
    let artifact = manifestWriter.artifact(
      input: ManifestInput(
        gunk: gunk,
        tags: tags,
        files: gunkFiles.map(\.relpath),
        sourcePath: manifestWriter.homeRelativePath(source.path),
        sourceCommit: shortCommitHash(sourceRoot: sourceRoot),
        license: try licenseDetector.detect(sourceRoot: sourceRoot),
        redactions: redactions,
        extractedAt: Date(timeIntervalSince1970: Double(extractedAt) / 1_000)
      )
    )

    try artifact.manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
    try artifact.readme.write(to: readmeURL, atomically: true, encoding: .utf8)
    try store.updateGunkExtraction(
      id: gunk.id,
      bundlePath: bundleURL.path,
      manifestPath: manifestURL.path,
      extractedAt: extractedAt
    )

    return ExtractionResult(
      bundleURL: bundleURL,
      manifestURL: manifestURL,
      readmeURL: readmeURL,
      redactions: redactions
    )
  }

  private func copyFile(
    relpath: String,
    sourceRoot: URL,
    bundleRoot: URL,
    redactions: inout [Redaction]
  ) throws {
    try validateRelativePath(relpath)

    let sourceURL = sourceRoot.appendingPathComponent(relpath).standardizedFileURL
    let sourceRootPath = sourceRoot.path.hasSuffix("/") ? sourceRoot.path : sourceRoot.path + "/"
    guard sourceURL.path.hasPrefix(sourceRootPath) else {
      throw ExtractorError.sourceFileOutsideRoot(relpath)
    }

    let result = try redactor.redact(url: sourceURL, relpath: relpath)
    redactions.append(contentsOf: result.redactions)

    guard case .write(let data, _) = result else {
      return
    }

    let destinationURL = bundleRoot.appendingPathComponent(relpath)
    try fileManager.createDirectory(
      at: destinationURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: destinationURL, options: .atomic)
  }

  private func validateRelativePath(_ relpath: String) throws {
    let normalized = relpath.replacingOccurrences(of: "\\", with: "/")

    guard !normalized.hasPrefix("/"),
          !normalized.isEmpty,
          !normalized.split(separator: "/").contains("..") else {
      throw ExtractorError.invalidRelativePath(relpath)
    }
  }

  private func shortCommitHash(sourceRoot: URL) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", sourceRoot.path, "rev-parse", "--short", "HEAD"]

    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return nil
    }

    guard process.terminationStatus == 0 else {
      return nil
    }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
