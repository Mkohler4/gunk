import GRDB
import XCTest
@testable import GunkApp

final class SourceScannerTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testSkipsIgnoredDirsAndBinaries() throws {
    try writeFile("src/App.swift", "print(\"ok\")")
    try writeFile(".git/config", "repo")
    try writeFile("node_modules/pkg/index.js", "module")
    try writeFile("dist/bundle.js", "bundle")
    try writeFile(".DS_Store", "metadata")
    try writeData("image.png", Data([0x89, 0x50, 0x00, 0x47]))

    let files = try SourceScanner().scan(folder: temporaryDirectory)

    XCTAssertEqual(files.map(\.relpath), ["src/App.swift"])
  }

  func testSkipsLikelySecretFiles() throws {
    try writeFile("src/App.swift", "print(\"ok\")")
    try writeFile(".env", "TOKEN=secret")
    try writeFile("certs/api.pem", "secret")
    try writeFile("certs/api.key", "secret")
    try writeFile("id_rsa", "secret")
    try writeFile("credentials.json", "{}")
    try writeFile("certs/archive.p12", "secret")

    let files = try SourceScanner().scan(folder: temporaryDirectory)

    XCTAssertEqual(files.map(\.relpath), ["src/App.swift"])
  }

  func testHonorsGunkignore() throws {
    try writeFile(".gunkignore", """
    Generated.swift
    ignored-dir/
    *.snap
    """)
    try writeFile("Generated.swift", "generated")
    try writeFile("ignored-dir/App.swift", "ignored")
    try writeFile("snapshot.snap", "ignored")
    try writeFile("Sources/App.swift", "print(\"ok\")")

    let files = try SourceScanner().scan(folder: temporaryDirectory)

    XCTAssertEqual(files.map(\.relpath), ["Sources/App.swift"])
  }

  func testRecordsFileRows() throws {
    try writeFile("Sources/App.swift", "print(\"ok\")")
    try writeFile("README.md", "# Fixture")
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let source = try store.insertSource(name: "fixture", path: temporaryDirectory.path)
    let scanner = SourceScanner(store: store, sourceId: source.id)

    _ = try scanner.scan(folder: temporaryDirectory)

    XCTAssertEqual(
      try store.filesForSource(sourceId: source.id).map(\.relpath),
      ["README.md", "Sources/App.swift"]
    )
  }

  private func writeFile(_ relpath: String, _ contents: String) throws {
    try writeData(relpath, Data(contents.utf8))
  }

  private func writeData(_ relpath: String, _ data: Data) throws {
    let url = temporaryDirectory.appendingPathComponent(relpath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: url)
  }
}
