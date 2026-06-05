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
      at: sourceURL.appendingPathComponent("src/routes"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: sourceURL.appendingPathComponent("src/services"),
      withIntermediateDirectories: true
    )
    try Data(
      """
      import { login } from "../services/auth";

      export async function authCallback(req, res) {
        res.json(await login(req.query.code));
      }

      router.get("/auth/google", authCallback);
      """.utf8
    )
    .write(to: sourceURL.appendingPathComponent("src/routes/auth.ts"))
    try Data(
      """
      export async function login(code: string) {
        return { code };
      }
      """.utf8
    )
    .write(to: sourceURL.appendingPathComponent("src/services/auth.ts"))

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
      return FakeRunnerLLMClient(
        responses: [
          .object([
            "hypotheses": .array([
              .object([
                "name": .string("auth-module"),
                "rationale": .string("Route and service form an auth capability."),
                "anchors": .array([.string("/auth/google")]),
                "seedFiles": .array([.string("src/routes/auth.ts")]),
                "expectedCollaborators": .array([.string("src/services/auth.ts")]),
                "granularity": .string("feature")
              ])
            ])
          ]),
          .object([
            "module": .object([
              "name": .string("auth-module"),
              "purpose": .string("Handles sign in"),
              "tags": .array([.string("auth"), .string("api")]),
              "language": .string("TypeScript"),
              "ownedFiles": .array([
                .string("src/routes/auth.ts"),
                .string("src/services/auth.ts")
              ]),
              "sharedDependencies": .array([]),
              "entrypoints": .array([
                .object([
                  "path": .string("src/routes/auth.ts"),
                  "symbol": .string("authCallback")
                ])
              ]),
              "anchors": .array([.string("/auth/google")]),
              "confidence": .number(0.91)
            ]),
            "qualityGateHints": .object([
              "externalFacingCapability": .bool(true),
              "multiFileCohesion": .bool(true),
              "anchorPresent": .bool(true),
              "rightGranularity": .bool(true)
            ]),
            "reject": .null
          ])
        ],
        usages: [
          LLMTokenUsage(inputTokens: 120, outputTokens: 40),
          LLMTokenUsage(inputTokens: 140, outputTokens: 50)
        ]
      )
    }

    await runner.process(source: source)

    let gunk = try XCTUnwrap(try store.gunksForSource(sourceId: source.id).first)
    XCTAssertEqual(gunk.name, "auth-module")
    XCTAssertEqual(gunk.bundlePath, gunkHome.appendingPathComponent("modules/1").path)
    XCTAssertEqual(try store.filesForGunk(gunkId: gunk.id).map(\.relpath), [
      "src/routes/auth.ts",
      "src/services/auth.ts"
    ])
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: gunkHome.appendingPathComponent("modules/1/gunk.yml").path
      )
    )
    XCTAssertFalse(processingModel.isProcessing)

    let runs = try store.llmRunsForSource(sourceId: source.id)
    XCTAssertEqual(runs.map(\.inputTokens), [120, 140])
    XCTAssertEqual(runs.map(\.outputTokens), [40, 50])
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

private final class FakeRunnerLLMClient: LLMClient {
  private var responses: [JSONValue]
  private var usages: [LLMTokenUsage]

  init(responses: [JSONValue], usages: [LLMTokenUsage]) {
    self.responses = responses
    self.usages = usages
  }

  func complete(request: LLMRequest) async throws -> LLMResponse {
    _ = request
    return LLMResponse(json: responses.removeFirst(), usage: usages.removeFirst())
  }
}
