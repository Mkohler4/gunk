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
    userDefaults.set(0.85, forKey: LLMSettings.confidenceThresholdKey)
    userDefaults.set(true, forKey: LLMSettings.monthlyCostCapEnabledKey)
    userDefaults.set(0.01, forKey: LLMSettings.monthlyCostCapUSDKey)

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
    assertFlag(arguments, "--confidence", "0.85")
    assertFlag(arguments, "--source-id", String(source.id))
    assertFlag(arguments, "--db", databaseURL.path)
    XCTAssertEqual(launcher.lastEnvironment?["GUNK_API_KEY"], "sk-test")
    XCTAssertFalse(arguments.contains("--monthly-cost-cap"))
  }

  func testPersistsProvenanceForExtractedModules() async throws {
    let databaseURL = temporaryDirectory.appendingPathComponent("store.db")
    let store = try Store(path: databaseURL)
    let source = try store.insertSource(name: "fixture", path: "/tmp/fixture")
    // The engine writes the gunk rows directly; stand them in here so the
    // result ids reference real rows the runner can attribute.
    let first = try store.insertGunk(sourceId: source.id, name: "module-a", confidence: 0.9, extractedAt: 1)
    let second = try store.insertGunk(sourceId: source.id, name: "module-b", confidence: 0.9, extractedAt: 2)
    let processingModel = makeProcessingModel(store: store)
    let userDefaults = try temporaryUserDefaults()
    userDefaults.set(LLMProvider.anthropic.rawValue, forKey: "llm.provider")
    userDefaults.set("claude-sonnet-4", forKey: "llm.model")

    let launcher = FakeEngineLauncher(events: [
      .progress(stage: "refine", fraction: 0.8, modulesFound: 2),
      .result(runId: "r1", gunkIds: [first.id, second.id], accepted: 2, needsApproval: 0, rejected: 0, tracePath: nil),
    ])

    let runner = SourceProcessingRunner(
      store: store,
      processingModel: processingModel,
      secretStore: FakeSecretStore(secrets: [LLMProvider.anthropic.secretAccount: "sk-test"]),
      userDefaults: userDefaults,
      gunkHome: temporaryDirectory.appendingPathComponent("gunk-home"),
      launcher: launcher
    )

    await runner.process(source: source)

    XCTAssertNil(processingModel.errorMessage)
    // Stored provenance matches the strings the engine was launched with
    // (the cli provider name + the selected model).
    let storedFirst = try XCTUnwrap(try store.gunk(id: first.id))
    XCTAssertEqual(storedFirst.provider, "anthropic")
    XCTAssertEqual(storedFirst.model, "claude-sonnet-4")
    let storedSecond = try XCTUnwrap(try store.gunk(id: second.id))
    XCTAssertEqual(storedSecond.provider, "anthropic")
    XCTAssertEqual(storedSecond.model, "claude-sonnet-4")
  }

  func testEnqueueRunsSourcesStrictlyOneAtATime() async throws {
    let databaseURL = temporaryDirectory.appendingPathComponent("store.db")
    let store = try Store(path: databaseURL)
    let first = try store.insertSource(name: "first", path: "/tmp/first")
    let second = try store.insertSource(name: "second", path: "/tmp/second")
    let processingModel = makeProcessingModel(store: store)
    let userDefaults = try temporaryUserDefaults()

    // A gated launcher: each run blocks at its result until the gate opens, so
    // the test can observe the queue mid-flight. If runs were concurrent, both
    // sources would launch before the gate opens.
    let gate = LaunchGate()
    let launcher = GatedEngineLauncher(
      gate: gate,
      events: [
        .progress(stage: "refine", fraction: 0.5, modulesFound: 1),
        .result(runId: "r", gunkIds: [], accepted: 0, needsApproval: 0, rejected: 0, tracePath: nil),
      ]
    )

    let runner = SourceProcessingRunner(
      store: store,
      processingModel: processingModel,
      secretStore: FakeSecretStore(secrets: [:]),
      userDefaults: userDefaults,
      gunkHome: temporaryDirectory.appendingPathComponent("gunk-home"),
      launcher: launcher
    )

    runner.enqueue(source: first)
    runner.enqueue(source: second)

    // Once the first run is in flight, exactly one source has launched and the
    // second is reported as waiting (queue depth, library-v2 §2).
    await waitUntil { launcher.launchedSourceIds.count == 1 && processingModel.isProcessing }
    XCTAssertEqual(launcher.launchedSourceIds, [first.id])
    XCTAssertEqual(processingModel.waitingCount, 1)
    XCTAssertEqual(processingModel.nextWaitingName, "second")

    await gate.open()

    // Both run, in drop order, and the queue drains to empty.
    await waitUntil { launcher.launchedSourceIds.count == 2 && !processingModel.isProcessing }
    XCTAssertEqual(launcher.launchedSourceIds, [first.id, second.id])
    XCTAssertEqual(processingModel.waitingCount, 0)
    XCTAssertNil(processingModel.nextWaitingName)
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

  /// Polls a main-actor condition until it holds or the timeout elapses,
  /// sleeping (not busy-spinning) so the gated launch task can make progress.
  private func waitUntil(
    timeout: Duration = .seconds(5),
    _ condition: @MainActor () -> Bool
  ) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(5))
    }
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

/// A one-shot gate the gated launcher awaits before completing a run, so a
/// test can hold the active run open and inspect the queue mid-flight.
private actor LaunchGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen {
      return
    }
    await withCheckedContinuation { waiters.append($0) }
  }

  func open() {
    isOpen = true
    let pending = waiters
    waiters = []
    for waiter in pending {
      waiter.resume()
    }
  }
}

/// Records the order in which sources launch and blocks each run at the gate,
/// so serialization (one launch at a time) and queue depth are observable.
private final class GatedEngineLauncher: EngineLauncher, @unchecked Sendable {
  private let gate: LaunchGate
  private let events: [EngineEvent]
  private let lock = NSLock()
  private var _launchedSourceIds: [Int64] = []

  var launchedSourceIds: [Int64] {
    lock.lock()
    defer { lock.unlock() }
    return _launchedSourceIds
  }

  init(gate: LaunchGate, events: [EngineEvent]) {
    self.gate = gate
    self.events = events
  }

  func launch(arguments: [String], environment: [String: String]) -> AsyncThrowingStream<EngineEvent, Error> {
    if let index = arguments.firstIndex(of: "--source-id"),
       index + 1 < arguments.count,
       let sourceId = Int64(arguments[index + 1]) {
      lock.lock()
      _launchedSourceIds.append(sourceId)
      lock.unlock()
    }

    let events = events
    let gate = gate
    return AsyncThrowingStream { continuation in
      Task {
        await gate.wait()
        for event in events {
          continuation.yield(event)
        }
        continuation.finish()
      }
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
