import GRDB
import XCTest
@testable import GunkApp

final class DecompositionPipelineTests: XCTestCase {
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

  func testEndToEndProducesRealModules() async throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let sourceURL = try fixtureURL("express-saas")
    let source = try store.insertSource(name: "express-saas", path: sourceURL.path)
    let client = PipelineFakeLLMClient(
      responses: expressSurveyAndRefinements(
        authConfidence: 0.92,
        billingConfidence: 0.91
      )
    )

    let gunks = try await pipeline(store: store).run(source: source, using: client)

    XCTAssertEqual(gunks.map(\.name).sorted(), [
      "Google OAuth login",
      "Stripe subscription billing"
    ])
    XCTAssertEqual(gunks.filter { $0.extractedAt != nil }.count, 2)

    let stored = try store.gunksForSource(sourceId: source.id)
    XCTAssertEqual(stored.count, 2)

    let filesByName = Dictionary(
      uniqueKeysWithValues: try stored.map { gunk in
        (gunk.name, try store.filesForGunk(gunkId: gunk.id).map(\.relpath))
      }
    )
    XCTAssertEqual(filesByName["Google OAuth login"], [
      "src/config/auth.ts",
      "src/routes/auth.ts",
      "src/services/googleOAuth.ts",
      "src/types/auth.ts"
    ])
    XCTAssertEqual(filesByName["Stripe subscription billing"], [
      "src/config/stripe.ts",
      "src/routes/billing.ts",
      "src/services/stripeBilling.ts",
      "src/types/billing.ts"
    ])
  }

  func testNoTrivialModulesEmitted() async throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let sourceURL = try fixtureURL("express-saas")
    let source = try store.insertSource(name: "express-saas", path: sourceURL.path)
    let client = PipelineFakeLLMClient(
      responses: [
        surveyJSON([
          hypothesisJSON(
            name: "Shared API types",
            anchors: ["types"],
            seedFiles: ["src/types.ts"],
            expectedCollaborators: []
          )
        ]),
        refinementJSON(
          name: "Shared API types",
          purpose: "Shared API type definitions.",
          tags: ["api"],
          ownedFiles: ["src/types.ts"],
          sharedDependencies: [],
          entrypoints: [],
          anchors: ["types"],
          confidence: 0.96
        )
      ]
    )

    let gunks = try await pipeline(store: store).run(source: source, using: client)

    XCTAssertTrue(gunks.isEmpty)
    XCTAssertTrue(try store.gunksForSource(sourceId: source.id).isEmpty)
  }

  func testProgressAndLLMRunsRecorded() async throws {
    var progressEvents: [DecompositionPipelineProgress] = []
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let sourceURL = try fixtureURL("express-saas")
    let source = try store.insertSource(name: "express-saas", path: sourceURL.path)
    let client = PipelineFakeLLMClient(
      responses: expressSurveyAndRefinements(
        authConfidence: 0.55,
        billingConfidence: 0.93
      ),
      usages: [
        LLMTokenUsage(inputTokens: 300, outputTokens: 40),
        LLMTokenUsage(inputTokens: 500, outputTokens: 80),
        LLMTokenUsage(inputTokens: 450, outputTokens: 70)
      ]
    )

    let gunks = try await pipeline(
      store: store,
      progress: { progressEvents.append($0) }
    )
    .run(source: source, using: client)

    XCTAssertEqual(gunks.count, 2)
    XCTAssertEqual(client.requests.map(\.jsonSchemaName), [
      "CapabilitySurvey",
      "CapabilityRefinement",
      "CapabilityRefinement"
    ])
    XCTAssertEqual(progressEvents.map(\.stage), [
      .scan,
      .symbols,
      .graph,
      .fingerprints,
      .repoMap,
      .survey,
      .expansion,
      .refine,
      .qualityGates,
      .persist,
      .extract
    ])
    XCTAssertEqual(progressEvents.last?.fraction, 1)
    XCTAssertTrue(progressEvents.map(\.fraction).isSortedAscending())

    let runs = try store.llmRunsForSource(sourceId: source.id)
    XCTAssertEqual(runs.count, 3)
    XCTAssertEqual(runs.map(\.inputTokens), [300, 500, 450])
    XCTAssertEqual(runs.map(\.outputTokens), [40, 80, 70])

    let stored = try store.gunksForSource(sourceId: source.id)
    let pending = try XCTUnwrap(stored.first { $0.name == "Google OAuth login" })
    let accepted = try XCTUnwrap(stored.first { $0.name == "Stripe subscription billing" })
    XCTAssertNil(pending.extractedAt)
    XCTAssertNil(pending.approvedAt)
    XCTAssertNotNil(accepted.extractedAt)
  }

  private func pipeline(
    store: Store,
    progress: @escaping DecompositionPipeline.ProgressHandler = { _ in }
  ) -> DecompositionPipeline {
    DecompositionPipeline(
      store: store,
      provider: .openAI,
      model: "pipeline-model",
      options: DecompositionPipelineOptions(
        contextBudgetTokens: 4_000,
        confidenceThreshold: 0.7
      ),
      gunkHome: temporaryDirectory.appendingPathComponent("gunk-home"),
      progress: progress
    )
  }

  private func fixtureURL(_ name: String) throws -> URL {
    try XCTUnwrap(
      Bundle.module.url(
        forResource: name,
        withExtension: nil,
        subdirectory: "Fixtures"
      )
    )
  }

  private func expressSurveyAndRefinements(
    authConfidence: Double,
    billingConfidence: Double
  ) -> [JSONValue] {
    [
      surveyJSON([
        hypothesisJSON(
          name: "Google OAuth login",
          anchors: ["google-auth-library", "GOOGLE_CLIENT_ID"],
          seedFiles: ["src/routes/auth.ts"],
          expectedCollaborators: [
            "src/services/googleOAuth.ts",
            "src/config/auth.ts",
            "src/types/auth.ts"
          ]
        ),
        hypothesisJSON(
          name: "Stripe subscription billing",
          anchors: ["stripe", "STRIPE_SECRET_KEY"],
          seedFiles: ["src/routes/billing.ts"],
          expectedCollaborators: [
            "src/services/stripeBilling.ts",
            "src/config/stripe.ts",
            "src/types/billing.ts"
          ]
        )
      ]),
      refinementJSON(
        name: "Google OAuth login",
        purpose: "Authenticates users with Google OAuth and creates a session.",
        tags: ["auth", "api"],
        ownedFiles: [
          "src/routes/auth.ts",
          "src/services/googleOAuth.ts"
        ],
        sharedDependencies: [
          "src/config/auth.ts",
          "src/types/auth.ts"
        ],
        entrypoints: [["path": "src/routes/auth.ts", "symbol": "authCallback"]],
        anchors: ["google-auth-library", "GOOGLE_CLIENT_ID"],
        confidence: authConfidence
      ),
      refinementJSON(
        name: "Stripe subscription billing",
        purpose: "Creates Stripe subscription checkout sessions.",
        tags: ["payments", "api"],
        ownedFiles: [
          "src/routes/billing.ts",
          "src/services/stripeBilling.ts"
        ],
        sharedDependencies: [
          "src/config/stripe.ts",
          "src/types/billing.ts"
        ],
        entrypoints: [["path": "src/routes/billing.ts", "symbol": "billingCheckout"]],
        anchors: ["stripe", "STRIPE_SECRET_KEY"],
        confidence: billingConfidence
      )
    ]
  }

  private func surveyJSON(_ hypotheses: [JSONValue]) -> JSONValue {
    .object(["hypotheses": .array(hypotheses)])
  }

  private func hypothesisJSON(
    name: String,
    anchors: [String],
    seedFiles: [String],
    expectedCollaborators: [String]
  ) -> JSONValue {
    .object([
      "name": .string(name),
      "rationale": .string("\(name) has a concrete route, service, config, and types closure."),
      "anchors": .array(anchors.map(JSONValue.string)),
      "seedFiles": .array(seedFiles.map(JSONValue.string)),
      "expectedCollaborators": .array(expectedCollaborators.map(JSONValue.string)),
      "granularity": .string("feature")
    ])
  }

  private func refinementJSON(
    name: String,
    purpose: String,
    tags: [String],
    ownedFiles: [String],
    sharedDependencies: [String],
    entrypoints: [[String: String]],
    anchors: [String],
    confidence: Double,
    language: String = "TypeScript"
  ) -> JSONValue {
    .object([
      "module": .object([
        "name": .string(name),
        "purpose": .string(purpose),
        "tags": .array(tags.map(JSONValue.string)),
        "language": .string(language),
        "ownedFiles": .array(ownedFiles.map(JSONValue.string)),
        "sharedDependencies": .array(sharedDependencies.map(JSONValue.string)),
        "entrypoints": .array(entrypoints.map { entrypoint in
          .object([
            "path": .string(entrypoint["path"] ?? ""),
            "symbol": .string(entrypoint["symbol"] ?? "")
          ])
        }),
        "anchors": .array(anchors.map(JSONValue.string)),
        "confidence": .number(confidence)
      ]),
      "qualityGateHints": .object([
        "externalFacingCapability": .bool(true),
        "multiFileCohesion": .bool(true),
        "anchorPresent": .bool(true),
        "rightGranularity": .bool(true)
      ]),
      "reject": .null
    ])
  }
}

private final class PipelineFakeLLMClient: LLMClient {
  private var responses: [JSONValue]
  private var usages: [LLMTokenUsage]
  private(set) var requests: [LLMRequest] = []

  init(
    responses: [JSONValue],
    usages: [LLMTokenUsage]? = nil
  ) {
    self.responses = responses
    self.usages = usages ?? Array(
      repeating: LLMTokenUsage(inputTokens: nil, outputTokens: nil),
      count: responses.count
    )
  }

  func complete(request: LLMRequest) async throws -> LLMResponse {
    requests.append(request)
    return LLMResponse(
      json: responses.removeFirst(),
      usage: usages.removeFirst()
    )
  }
}

private extension Array where Element: Comparable {
  func isSortedAscending() -> Bool {
    zip(self, dropFirst()).allSatisfy { $0 <= $1 }
  }
}
