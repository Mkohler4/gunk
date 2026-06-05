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

  func testStreamsEngineProgressAndCompletes() async throws {
    let databaseURL = temporaryDirectory.appendingPathComponent("store.db")
    let store = try Store(path: databaseURL, now: timestamps(100, 200, 300))
    let source = try store.insertSource(name: "fixture", path: "/tmp/fixture")
    let processingModel = makeProcessingModel(store: store)
    let userDefaults = try temporaryUserDefaults()
    userDefaults.set(LLMProvider.openAI.rawValue, forKey: "llm.provider")
    userDefaults.set("gpt-fixture", forKey: "llm.model")

    let launcher = FakeEngineLauncher(events: [
      .stage(stage: "scan", phase: "started", durationMs: nil, counts: [:]),
      .progress(stage: "scan", fraction: 0.1, modulesFound: nil),
      .progress(stage: "refine", fraction: 0.78, modulesFound: 2),
      .result(runId: "r1", gunkIds: [1, 2], accepted: 2, needsApproval: 0, rejected: 0, tracePath: nil),
    ])

    let runner = SourceProcessingRunner(
      store: store,
      processingModel: processingModel,
      secretStore: FakeSecretStore(secrets: [LLMProvider.openAI.secretAccount: "sk-test"]),
      userDefaults: userDefaults,
      gunkHome: temporaryDirectory.appendingPathComponent("gunk-home"),
      launcher: launcher
    )

    await runner.process(source: source)

    XCTAssertFalse(processingModel.isProcessing)
    XCTAssertNil(processingModel.errorMessage)

    let arguments = try XCTUnwrap(launcher.lastArguments)
    XCTAssertEqual(arguments.first, "/tmp/fixture")
    XCTAssertTrue(arguments.contains("--json"))
    XCTAssertTrue(arguments.contains("--trace"))
    assertFlag(arguments, "--provider", "openai")
    assertFlag(arguments, "--model", "gpt-fixture")
    assertFlag(arguments, "--source-id", String(source.id))
    assertFlag(arguments, "--db", databaseURL.path)
    XCTAssertEqual(launcher.lastEnvironment?["GUNK_API_KEY"], "sk-test")
  }

  func testEngineErrorEventFailsRun() async throws {
    let databaseURL = temporaryDirectory.appendingPathComponent("store.db")
    let store = try Store(path: databaseURL)
    let source = try store.insertSource(name: "fixture", path: "/tmp/fixture")
    let processingModel = makeProcessingModel(store: store)
    let userDefaults = try temporaryUserDefaults()

    let launcher = FakeEngineLauncher(events: [
      .progress(stage: "survey", fraction: 0.58, modulesFound: nil),
      .error(message: "LLM request failed with HTTP 401.", stage: "survey"),
    ])

    let runner = SourceProcessingRunner(
      store: store,
      processingModel: processingModel,
      secretStore: FakeSecretStore(secrets: [:]),
      userDefaults: userDefaults,
      gunkHome: temporaryDirectory.appendingPathComponent("gunk-home"),
      launcher: launcher
    )

    await runner.process(source: source)

    XCTAssertFalse(processingModel.isProcessing)
    XCTAssertEqual(processingModel.errorMessage, "LLM request failed with HTTP 401.")
  }

  func testMissingResultFailsRun() async throws {
    let databaseURL = temporaryDirectory.appendingPathComponent("store.db")
    let store = try Store(path: databaseURL)
    let source = try store.insertSource(name: "fixture", path: "/tmp/fixture")
    let processingModel = makeProcessingModel(store: store)
    let userDefaults = try temporaryUserDefaults()

    let launcher = FakeEngineLauncher(events: [
      .progress(stage: "scan", fraction: 0.1, modulesFound: nil),
    ])

    let runner = SourceProcessingRunner(
      store: store,
      processingModel: processingModel,
      secretStore: FakeSecretStore(secrets: [:]),
      userDefaults: userDefaults,
      gunkHome: temporaryDirectory.appendingPathComponent("gunk-home"),
      launcher: launcher
    )

    await runner.process(source: source)

    XCTAssertFalse(processingModel.isProcessing)
    XCTAssertNotNil(processingModel.errorMessage)
  }

  private func makeProcessingModel(store: Store) -> ProcessingModel {
    ProcessingModel(
      dockIconController: DockIconController(),
      gunkCount: { try store.listGunks().count }
    )
  }

  private func assertFlag(_ arguments: [String], _ flag: String, _ value: String) {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
      XCTFail("Missing flag \(flag)")
      return
    }
    XCTAssertEqual(arguments[index + 1], value)
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

private final class FakeEngineLauncher: EngineLauncher {
  private let events: [EngineEvent]
  private(set) var lastArguments: [String]?
  private(set) var lastEnvironment: [String: String]?

  init(events: [EngineEvent]) {
    self.events = events
  }

  func launch(arguments: [String], environment: [String: String]) -> AsyncThrowingStream<EngineEvent, Error> {
    lastArguments = arguments
    lastEnvironment = environment
    let events = events
    return AsyncThrowingStream { continuation in
      for event in events {
        continuation.yield(event)
      }
      continuation.finish()
    }
  }
}

private struct FakeSecretStore: SecretStore {
  var secrets: [String: String]

  func secret(for account: String) throws -> String? {
    secrets[account]
  }

  func setSecret(_ secret: String?, for account: String) throws {
    // not needed for these tests
  }
}
