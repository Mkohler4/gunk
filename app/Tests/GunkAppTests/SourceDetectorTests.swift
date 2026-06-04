import XCTest
@testable import GunkApp

final class SourceDetectorTests: XCTestCase {
  private var temporaryDirectory: URL!
  private var detector: SourceDetector!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    detector = SourceDetector()
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testSingleProjectReturnsItself() throws {
    try writeFile("package.json", in: temporaryDirectory)
    let nestedProject = try makeDirectory("nested")
    try writeFile("Package.swift", in: nestedProject)

    XCTAssertEqual(
      try detector.detect(folder: temporaryDirectory),
      [standardized(temporaryDirectory)]
    )
  }

  func testParentOfProjectsReturnsChildren() throws {
    let api = try makeDirectory("api")
    let app = try makeDirectory("app")
    let cli = try makeDirectory("cli")
    let notes = try makeDirectory("notes")

    try writeFile("go.mod", in: api)
    try writeFile("package.json", in: app)
    try writeFile("main.swift", in: cli)
    try writeFile("README.md", in: notes)

    XCTAssertEqual(
      try detector.detect(folder: temporaryDirectory),
      [api, app, cli].map(\.standardizedFileURL)
    )
  }

  func testLooseFolderReturnsItself() throws {
    try writeFile("README.md", in: temporaryDirectory)

    XCTAssertEqual(
      try detector.detect(folder: temporaryDirectory),
      [standardized(temporaryDirectory)]
    )
  }

  private func makeDirectory(_ name: String) throws -> URL {
    let url = temporaryDirectory.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func writeFile(_ name: String, in folder: URL) throws {
    let url = folder.appendingPathComponent(name)
    try Data("fixture".utf8).write(to: url)
  }

  private func standardized(_ url: URL) -> URL {
    url.standardizedFileURL
  }
}
