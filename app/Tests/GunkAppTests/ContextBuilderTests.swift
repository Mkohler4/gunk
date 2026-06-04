import XCTest
@testable import GunkApp

final class ContextBuilderTests: XCTestCase {
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

  func testRespectsTokenBudget() throws {
    let files = [
      try scannedFile("README.md", String(repeating: "readme ", count: 80)),
      try scannedFile("Sources/App.swift", String(repeating: "source ", count: 120))
    ]
    let context = try ContextBuilder().build(files: files, budgetTokens: 80)

    XCTAssertLessThanOrEqual(ContextBuilder.estimatedTokens(for: context), 80)
    XCTAssertTrue(context.contains(ContextBuilder.truncationMarker))
  }

  func testPrioritizesReadmeAndManifests() throws {
    let files = [
      try scannedFile("Sources/ZFeature.swift", "feature"),
      try scannedFile("package.json", "{\"scripts\":{}}"),
      try scannedFile("README.md", "# Important")
    ]
    let context = try ContextBuilder().build(files: files, budgetTokens: 300)

    let readmeIndex = try XCTUnwrap(context.range(of: "--- README.md ---"))
    let manifestIndex = try XCTUnwrap(context.range(of: "--- package.json ---"))
    let sourceIndex = try XCTUnwrap(context.range(of: "--- Sources/ZFeature.swift ---"))

    XCTAssertLessThan(readmeIndex.lowerBound, manifestIndex.lowerBound)
    XCTAssertLessThan(manifestIndex.lowerBound, sourceIndex.lowerBound)
  }

  private func scannedFile(_ relpath: String, _ contents: String) throws -> ScannedFile {
    let url = temporaryDirectory.appendingPathComponent(relpath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(contents.utf8).write(to: url)

    return ScannedFile(
      url: url,
      relpath: relpath,
      size: Int64(Data(contents.utf8).count)
    )
  }
}
