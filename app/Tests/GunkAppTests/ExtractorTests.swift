import Foundation
import GRDB
import XCTest
@testable import GunkApp

final class ExtractorTests: XCTestCase {
  func testCopiesOnlyModuleFiles() throws {
    let fixture = try makeFixture()
    let project = try makeProject(in: fixture.home)
    try write("Sources/Auth.swift", contents: "struct Auth {}\n", in: project)
    try write("Sources/Profile.swift", contents: "struct Profile {}\n", in: project)
    try write("Tests/AuthTests.swift", contents: "import XCTest\n", in: project)
    try write("unrelated.txt", contents: "not part of this module\n", in: project)
    let (store, _, gunk) = try makeStoredGunk(
      sourceRoot: project,
      files: ["Sources/Auth.swift", "Tests/AuthTests.swift"]
    )

    let result = try XCTUnwrap(try makeExtractor(
      store: store,
      gunkHome: fixture.gunkHome,
      homeDirectory: fixture.home
    ).extract(gunk: gunk))

    XCTAssertEqual(
      try bundledModuleFiles(in: result.bundleURL),
      ["Sources/Auth.swift", "Tests/AuthTests.swift"]
    )
    XCTAssertFalse(fileExists("Sources/Profile.swift", in: result.bundleURL))
    XCTAssertFalse(fileExists("unrelated.txt", in: result.bundleURL))

    let updated = try XCTUnwrap(try store.gunk(id: gunk.id))
    XCTAssertEqual(updated.bundlePath, result.bundleURL.path)
    XCTAssertEqual(updated.manifestPath, result.manifestURL.path)
    XCTAssertEqual(updated.extractedAt, fixedNow)
  }

  func testNeverWritesSecretsIntoBundle() throws {
    let fixture = try makeFixture()
    let project = try makeProject(in: fixture.home)
    let secret = "sk-" + String(repeating: "a", count: 24)
    try write(".env", contents: "TOKEN=\(secret)\n", in: project)
    try write(
      "Sources/Auth.swift",
      contents: """
      let token = "\(secret)"
      let safeValue = "visible"
      """,
      in: project
    )
    let (store, _, gunk) = try makeStoredGunk(
      sourceRoot: project,
      files: [".env", "Sources/Auth.swift"]
    )

    let result = try XCTUnwrap(try makeExtractor(
      store: store,
      gunkHome: fixture.gunkHome,
      homeDirectory: fixture.home
    ).extract(gunk: gunk))

    XCTAssertFalse(fileExists(".env", in: result.bundleURL))
    let copiedSource = try String(
      contentsOf: result.bundleURL.appendingPathComponent("Sources/Auth.swift"),
      encoding: .utf8
    )
    XCTAssertFalse(copiedSource.contains(secret))
    XCTAssertTrue(copiedSource.contains("[gunk redacted: secret-like content]"))
    XCTAssertTrue(copiedSource.contains("safeValue"))
    XCTAssertFalse(try bundleContains(secret, in: result.bundleURL))

    let manifest = try String(contentsOf: result.manifestURL, encoding: .utf8)
    XCTAssertTrue(manifest.contains("redactions:"))
    XCTAssertTrue(manifest.contains("secret_filename"))
    XCTAssertTrue(manifest.contains("secret_like_content"))
  }

  func testWritesValidManifestWithRelativeProvenance() throws {
    let fixture = try makeFixture()
    let project = try makeProject(in: fixture.home)
    try write("Sources/Auth.swift", contents: "struct Auth {}\n", in: project)
    let (store, _, gunk) = try makeStoredGunk(
      sourceRoot: project,
      files: ["Sources/Auth.swift"],
      tags: ["auth", "api"],
      language: "Swift",
      purpose: "Handles sign in callbacks."
    )

    let result = try XCTUnwrap(try makeExtractor(
      store: store,
      gunkHome: fixture.gunkHome,
      homeDirectory: fixture.home
    ).extract(gunk: gunk))
    let manifest = try String(contentsOf: result.manifestURL, encoding: .utf8)

    XCTAssertTrue(manifest.contains("schema_version: 0"))
    XCTAssertTrue(manifest.contains("id: \(gunk.id)"))
    XCTAssertTrue(manifest.contains("name: \"auth-module\""))
    XCTAssertTrue(manifest.contains("tags:"))
    XCTAssertTrue(manifest.contains("- \"auth\""))
    XCTAssertTrue(manifest.contains("language: \"Swift\""))
    XCTAssertTrue(manifest.contains("purpose: \"Handles sign in callbacks.\""))
    XCTAssertTrue(manifest.contains("deps:"))
    XCTAssertTrue(manifest.contains("requirements:"))
    // No dependency manifest in the fixture, so the runtime falls back to the
    // module's language and packages/env are honestly empty.
    XCTAssertTrue(manifest.contains("  runtime: \"Swift\""))
    XCTAssertTrue(manifest.contains("  packages: []"))
    XCTAssertTrue(manifest.contains("  env: []"))
    XCTAssertTrue(manifest.contains("entrypoints:"))
    XCTAssertTrue(manifest.contains("provenance:"))
    XCTAssertTrue(manifest.contains("source_path: \"~/Documents/project\""))
    XCTAssertTrue(manifest.contains("source_commit: null"))
    XCTAssertTrue(manifest.contains("license:"))
    XCTAssertTrue(manifest.contains("confidence: 0.91"))
    XCTAssertTrue(manifest.contains("extracted_at: \"2026-06-04T18:00:00Z\""))
    XCTAssertFalse(manifest.contains(project.path))
    XCTAssertFalse(manifest.contains(NSUserName()))
    XCTAssertFalse(manifest.contains("github.com"))
    XCTAssertFalse(manifest.contains("git@"))
  }

  func testGeneratesMiniReadme() throws {
    let fixture = try makeFixture()
    let project = try makeProject(in: fixture.home)
    try write("Sources/main.swift", contents: "print(\"hello\")\n", in: project)
    let (store, _, gunk) = try makeStoredGunk(
      sourceRoot: project,
      files: ["Sources/main.swift"],
      tags: ["cli"],
      language: "Swift",
      purpose: "Runs the command line entrypoint."
    )

    let result = try XCTUnwrap(try makeExtractor(
      store: store,
      gunkHome: fixture.gunkHome,
      homeDirectory: fixture.home
    ).extract(gunk: gunk))
    let readme = try String(contentsOf: result.readmeURL, encoding: .utf8)

    XCTAssertFalse(readme.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    XCTAssertTrue(readme.contains("# auth-module"))
    XCTAssertTrue(readme.contains("Runs the command line entrypoint."))
    XCTAssertTrue(readme.contains("Tags: cli"))
    XCTAssertTrue(readme.contains("`Sources/main.swift`"))
  }

  func testDetectsSourceLicenseAndFlagsRestrictive() throws {
    let fixture = try makeFixture()
    let project = try makeProject(in: fixture.home)
    try write("Sources/Auth.swift", contents: "struct Auth {}\n", in: project)
    try write(
      "LICENSE",
      contents: """
      GNU GENERAL PUBLIC LICENSE
      Version 3, 29 June 2007
      """,
      in: project
    )
    let (store, _, gunk) = try makeStoredGunk(
      sourceRoot: project,
      files: ["Sources/Auth.swift"]
    )

    let result = try XCTUnwrap(try makeExtractor(
      store: store,
      gunkHome: fixture.gunkHome,
      homeDirectory: fixture.home
    ).extract(gunk: gunk))
    let manifest = try String(contentsOf: result.manifestURL, encoding: .utf8)

    XCTAssertTrue(manifest.contains("detected: \"GPL-3.0-or-later\""))
    XCTAssertTrue(manifest.contains("warning: \"Restrictive source license detected: GPL-3.0-or-later."))
  }

  func testSkipsGunksBelowConfidenceThreshold() throws {
    let fixture = try makeFixture()
    let project = try makeProject(in: fixture.home)
    try write("Sources/Auth.swift", contents: "struct Auth {}\n", in: project)
    let (store, _, gunk) = try makeStoredGunk(
      sourceRoot: project,
      files: ["Sources/Auth.swift"],
      confidence: 0.69
    )

    let result = try makeExtractor(
      store: store,
      gunkHome: fixture.gunkHome,
      homeDirectory: fixture.home
    ).extract(gunk: gunk)

    XCTAssertNil(result)
    XCTAssertFalse(fileExists("modules/\(gunk.id)", in: fixture.gunkHome))
    XCTAssertNil(try store.gunk(id: gunk.id)?.bundlePath)
  }

  private func makeFixture() throws -> (root: URL, home: URL, gunkHome: URL) {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("GunkExtractorTests-\(UUID().uuidString)", isDirectory: true)
    let home = root.appendingPathComponent("home", isDirectory: true)
    let gunkHome = root.appendingPathComponent("gunk-home", isDirectory: true)

    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: root)
    }

    return (root, home, gunkHome)
  }

  private func makeProject(in home: URL) throws -> URL {
    let project = home
      .appendingPathComponent("Documents", isDirectory: true)
      .appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    return project
  }

  private func makeStoredGunk(
    sourceRoot: URL,
    files: [String],
    tags: [String] = ["auth"],
    language: String = "Swift",
    purpose: String = "Handles sign in.",
    confidence: Double = 0.91
  ) throws -> (Store, Source, Gunk) {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { fixedNow })
    let source = try store.insertSource(name: "project", path: sourceRoot.path)
    let gunk = try store.insertGunk(
      sourceId: source.id,
      name: "auth-module",
      purpose: purpose,
      language: language,
      confidence: confidence
    )

    for tagName in tags {
      let tag = try store.addTag(name: tagName)
      try store.addGunkTag(gunkId: gunk.id, tagId: tag.id, confidence: gunk.confidence)
    }

    for relpath in files {
      let size = try Int64(
        FileManager.default.attributesOfItem(
          atPath: sourceRoot.appendingPathComponent(relpath).path
        )[.size] as? Int ?? 0
      )
      try store.addGunkFile(gunkId: gunk.id, relpath: relpath, size: size)
    }

    return (store, source, gunk)
  }

  private func makeExtractor(
    store: Store,
    gunkHome: URL,
    homeDirectory: URL
  ) -> Extractor {
    Extractor(
      store: store,
      gunkHome: gunkHome,
      manifestWriter: ManifestWriter(homeDirectory: homeDirectory),
      now: { fixedNow }
    )
  }

  private func write(_ relpath: String, contents: String, in root: URL) throws {
    let url = root.appendingPathComponent(relpath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
  }

  private func fileExists(_ relpath: String, in root: URL) -> Bool {
    FileManager.default.fileExists(atPath: root.appendingPathComponent(relpath).path)
  }

  private func bundledModuleFiles(in bundleURL: URL) throws -> [String] {
    let urls = try XCTUnwrap(
      FileManager.default.enumerator(
        at: bundleURL,
        includingPropertiesForKeys: [.isRegularFileKey]
      )?.compactMap { $0 as? URL }
    )

    return try urls.compactMap { url in
      let values = try url.resourceValues(forKeys: [.isRegularFileKey])
      guard values.isRegularFile == true else {
        return nil
      }

      let relpath = relativePath(url, from: bundleURL)
      return ["gunk.yml", "README.gunk.md"].contains(relpath) ? nil : relpath
    }
    .sorted()
  }

  private func bundleContains(_ needle: String, in bundleURL: URL) throws -> Bool {
    let urls = try XCTUnwrap(
      FileManager.default.enumerator(
        at: bundleURL,
        includingPropertiesForKeys: [.isRegularFileKey]
      )?.compactMap { $0 as? URL }
    )
    let needleData = Data(needle.utf8)

    for url in urls {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey])
      if values.isRegularFile == true,
         try Data(contentsOf: url).range(of: needleData) != nil {
        return true
      }
    }

    return false
  }

  private func relativePath(_ url: URL, from root: URL) -> String {
    let standardizedURL = url.standardizedFileURL
    let standardizedRoot = root.standardizedFileURL
    let rootPath = standardizedRoot.path.hasSuffix("/")
      ? standardizedRoot.path
      : standardizedRoot.path + "/"
    return String(standardizedURL.path.dropFirst(rootPath.count))
  }
}

private let fixedNow: Int64 = 1_780_596_000_000
