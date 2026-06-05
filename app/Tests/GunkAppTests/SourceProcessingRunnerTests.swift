import AppKit
import GRDB
import XCTest
@testable import GunkApp

@MainActor
final class SourceProcessingRunnerTests: XCTestCase {
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

  func testProcessesSourceIntoExtractedBundle() async throws {
    let sourceURL = temporaryDirectory.appendingPathComponent("fixture")
    try FileManager.default.createDirectory(
      at: sourceURL.appendingPathComponent("Sources"),
      withIntermediateDirectories: true
    )
    try Data("# Fixture\n".utf8)
      .write(to: sourceURL.appendingPathComponent("README.md"))
    try Data("func login() {}\n".utf8)
      .write(to: sourceURL.appendingPathComponent("Sources/Auth.swift"))

    let store = try Store(databaseQueue: DatabaseQueue(), now: timestamps(100, 200, 300))
    let source = try store.insertSource(name: "fixture", path: sourceURL.path)
    let dockIconController = DockIconController()
    let processingModel = ProcessingModel(
      dockIconController: dockIconController,
      gunkCount: { try store.listGunks().count }
    )
    let gunkHome = temporaryDirectory.appendingPathComponent("gunk-home")
    let userDefaults = try temporaryUserDefaults()
    userDefaults.set(LLMProvider.openAI.rawValue, forKey: "llm.provider")
    userDefaults.set("gpt-fixture", forKey: "llm.model")
    userDefaults.set(0.7, forKey: "llm.confidenceThreshold")

    let runner = SourceProcessingRunner(
      store: store,
      processingModel: processingModel,
      userDefaults: userDefaults,
      fileManager: .default,
      gunkHome: gunkHome,
      contextBudgetTokens: 2_000
    ) { provider, model, _ in
      XCTAssertEqual(provider, .openAI)
      XCTAssertEqual(model, "gpt-fixture")
      return FakeLLMClient(
        json: .object([
          "modules": .array([
            .object([
              "name": .string("auth-module"),
              "purpose": .string("Handles sign in"),
              "tags": .array([.string("auth")]),
              "files": .array([
                .string("README.md"),
                .string("Sources/Auth.swift")
              ]),
              "language": .string("Swift"),
              "confidence": .number(0.91)
            ])
          ])
        ]),
        usage: LLMTokenUsage(inputTokens: 120, outputTokens: 40)
      )
    }

    await runner.process(source: source)

    let gunk = try XCTUnwrap(try store.gunksForSource(sourceId: source.id).first)
    XCTAssertEqual(gunk.name, "auth-module")
    XCTAssertEqual(gunk.bundlePath, gunkHome.appendingPathComponent("modules/1").path)
    XCTAssertEqual(try store.filesForGunk(gunkId: gunk.id).map(\.relpath), [
      "README.md",
      "Sources/Auth.swift"
    ])
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: gunkHome.appendingPathComponent("modules/1/gunk.yml").path
      )
    )
    XCTAssertFalse(processingModel.isProcessing)

    let run = try XCTUnwrap(try store.llmRunsForSource(sourceId: source.id).first)
    XCTAssertEqual(run.inputTokens, 120)
    XCTAssertEqual(run.outputTokens, 40)
  }

  private func temporaryUserDefaults() throws -> UserDefaults {
    let suiteName = "SourceProcessingRunnerTests-\(UUID().uuidString)"
    return try XCTUnwrap(UserDefaults(suiteName: suiteName))
  }

  private func timestamps(_ values: Int64...) -> () -> Int64 {
    var values = values
    var last = values.last ?? 0
    return {
      guard !values.isEmpty else {
        return last
      }

      last = values.removeFirst()
      return last
    }
  }
}

private struct FakeLLMClient: LLMClient {
  let json: JSONValue
  let usage: LLMTokenUsage

  func complete(request: LLMRequest) async throws -> LLMResponse {
    _ = request
    return LLMResponse(json: json, usage: usage)
  }
}
