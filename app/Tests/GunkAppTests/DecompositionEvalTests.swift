import GRDB
import XCTest
@testable import GunkApp

final class DecompositionEvalTests: XCTestCase {
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

  func testScoresFileMembershipPrecisionRecall() {
    let expected = ExpectedDecomposition(
      modules: [
        ExpectedModule(
          name: "Google OAuth login",
          tags: ["auth", "api"],
          files: ["routes/auth.ts", "services/auth.ts", "types/auth.ts"]
        )
      ],
      mustNotBeModules: []
    )

    let actual = [
      Module(
        name: "Google OAuth login",
        purpose: "Handles Google sign-in.",
        tags: ["auth"],
        files: ["routes/auth.ts", "services/auth.ts", "services/session.ts"],
        language: "TypeScript",
        confidence: 0.9
      )
    ]

    let scorecard = DecompositionEval.score(actual: actual, expected: expected)

    XCTAssertEqual(scorecard.filePrecision, 2.0 / 3.0, accuracy: 0.0001)
    XCTAssertEqual(scorecard.fileRecall, 2.0 / 3.0, accuracy: 0.0001)
    XCTAssertEqual(scorecard.tagAccuracy, 0.5, accuracy: 0.0001)
    XCTAssertEqual(scorecard.moduleCountDelta, 0)
  }

  func testCountsTrivialModuleFalsePositives() {
    let expected = ExpectedDecomposition(
      modules: [],
      mustNotBeModules: ["src/types.ts", "src/utils/"]
    )

    let actual = [
      Module(
        name: "types",
        purpose: nil,
        tags: [],
        files: ["src/types.ts"],
        language: "TypeScript",
        confidence: 0.7
      ),
      Module(
        name: "utils",
        purpose: nil,
        tags: [],
        files: ["src/utils/format.ts"],
        language: "TypeScript",
        confidence: 0.7
      ),
      Module(
        name: "auth-with-types",
        purpose: nil,
        tags: ["auth"],
        files: ["src/auth/service.ts", "src/types.ts"],
        language: "TypeScript",
        confidence: 0.8
      )
    ]

    let scorecard = DecompositionEval.score(actual: actual, expected: expected)

    XCTAssertEqual(scorecard.trivialModuleFalsePositiveCount, 2)
    XCTAssertEqual(scorecard.trivialModuleFalsePositiveRate, 1.0, accuracy: 0.0001)
  }

  func testBaselinePipelineScorecardRecorded() async throws {
    let expressScorecard = try await baselineScorecard(
      fixtureName: "express-saas",
      response: modulesJSON([
        moduleJSON(
          name: "Google OAuth login",
          purpose: "Handles Google OAuth callback and session creation.",
          tags: ["auth", "api"],
          files: [
            "src/routes/auth.ts",
            "src/services/googleOAuth.ts",
            "src/config/auth.ts",
            "src/types/auth.ts"
          ]
        ),
        moduleJSON(
          name: "types",
          purpose: "Shared TypeScript types.",
          tags: ["api"],
          files: ["src/types.ts"]
        ),
        moduleJSON(
          name: "utils",
          purpose: "Common helpers.",
          tags: ["api"],
          files: ["src/utils/format.ts"]
        )
      ])
    )

    let nextScorecard = try await baselineScorecard(
      fixtureName: "next-media",
      response: modulesJSON([
        moduleJSON(
          name: "S3 image upload",
          purpose: "Uploads images to S3.",
          tags: ["api"],
          files: [
            "app/api/upload/route.ts",
            "src/services/s3Upload.ts",
            "src/config/storage.ts",
            "src/types/upload.ts"
          ]
        ),
        moduleJSON(
          name: "types",
          purpose: "Shared TypeScript aliases.",
          tags: ["api"],
          files: ["src/types.ts"]
        )
      ])
    )

    print("\nPhase 3 baseline scorecard (express-saas)\n\(expressScorecard.summary)")
    print("\nPhase 3 baseline scorecard (next-media)\n\(nextScorecard.summary)")

    XCTAssertEqual(expressScorecard.filePrecision, 0.5, accuracy: 0.0001)
    XCTAssertEqual(expressScorecard.fileRecall, 0.5, accuracy: 0.0001)
    XCTAssertEqual(expressScorecard.tagAccuracy, 0.5, accuracy: 0.0001)
    XCTAssertEqual(expressScorecard.moduleCountDelta, 1)
    XCTAssertEqual(expressScorecard.trivialModuleFalsePositiveRate, 1.0, accuracy: 0.0001)

    XCTAssertEqual(nextScorecard.filePrecision, 0.5, accuracy: 0.0001)
    XCTAssertEqual(nextScorecard.fileRecall, 0.5, accuracy: 0.0001)
    XCTAssertEqual(nextScorecard.tagAccuracy, 0.5, accuracy: 0.0001)
    XCTAssertEqual(nextScorecard.moduleCountDelta, 0)
    XCTAssertEqual(nextScorecard.trivialModuleFalsePositiveRate, 0.5, accuracy: 0.0001)

    let baselineDoc = try String(contentsOf: retrosURL().appendingPathComponent("phase-4-eval-baseline.md"))
    XCTAssertTrue(baselineDoc.contains("express-saas"))
    XCTAssertTrue(baselineDoc.contains("next-media"))
    XCTAssertTrue(baselineDoc.contains("trivial_module_false_positive_rate: 1.00"))
    XCTAssertTrue(baselineDoc.contains("trivial_module_false_positive_rate: 0.50"))
    XCTAssertTrue(baselineDoc.contains("types.ts"))
  }

  func testNewPipelineBeatsBaseline() async throws {
    let expressBaseline = try await baselineScorecard(
      fixtureName: "express-saas",
      response: modulesJSON([
        moduleJSON(
          name: "Google OAuth login",
          purpose: "Handles Google OAuth callback and session creation.",
          tags: ["auth", "api"],
          files: [
            "src/routes/auth.ts",
            "src/services/googleOAuth.ts",
            "src/config/auth.ts",
            "src/types/auth.ts"
          ]
        ),
        moduleJSON(
          name: "types",
          purpose: "Shared TypeScript types.",
          tags: ["api"],
          files: ["src/types.ts"]
        ),
        moduleJSON(
          name: "utils",
          purpose: "Common helpers.",
          tags: ["api"],
          files: ["src/utils/format.ts"]
        )
      ])
    )
    let nextBaseline = try await baselineScorecard(
      fixtureName: "next-media",
      response: modulesJSON([
        moduleJSON(
          name: "S3 image upload",
          purpose: "Uploads images to S3.",
          tags: ["api"],
          files: [
            "app/api/upload/route.ts",
            "src/services/s3Upload.ts",
            "src/config/storage.ts",
            "src/types/upload.ts"
          ]
        ),
        moduleJSON(
          name: "types",
          purpose: "Shared TypeScript aliases.",
          tags: ["api"],
          files: ["src/types.ts"]
        )
      ])
    )

    let expressNew = try await newPipelineScorecard(fixtureName: "express-saas")
    let nextNew = try await newPipelineScorecard(fixtureName: "next-media")

    XCTAssertGreaterThan(expressNew.filePrecision, expressBaseline.filePrecision)
    XCTAssertGreaterThan(expressNew.fileRecall, expressBaseline.fileRecall)
    XCTAssertGreaterThan(expressNew.tagAccuracy, expressBaseline.tagAccuracy)
    XCTAssertEqual(expressNew.moduleCountDelta, 0)
    XCTAssertLessThan(abs(expressNew.moduleCountDelta), abs(expressBaseline.moduleCountDelta))

    XCTAssertGreaterThan(nextNew.filePrecision, nextBaseline.filePrecision)
    XCTAssertGreaterThan(nextNew.fileRecall, nextBaseline.fileRecall)
    XCTAssertGreaterThan(nextNew.tagAccuracy, nextBaseline.tagAccuracy)
    XCTAssertEqual(nextNew.moduleCountDelta, 0)
    XCTAssertEqual(abs(nextNew.moduleCountDelta), abs(nextBaseline.moduleCountDelta))
  }

  func testNewPipelineZeroTrapFalsePositives() async throws {
    let expressScorecard = try await newPipelineScorecard(fixtureName: "express-saas")
    let nextScorecard = try await newPipelineScorecard(fixtureName: "next-media")

    XCTAssertEqual(expressScorecard.trivialModuleFalsePositiveCount, 0)
    XCTAssertEqual(expressScorecard.trivialModuleFalsePositiveRate, 0, accuracy: 0.0001)
    XCTAssertEqual(nextScorecard.trivialModuleFalsePositiveCount, 0)
    XCTAssertEqual(nextScorecard.trivialModuleFalsePositiveRate, 0, accuracy: 0.0001)
  }

  private func baselineScorecard(fixtureName: String, response: JSONValue) async throws -> Scorecard {
    let fixture = fixtureURL(fixtureName)
    let expected = try ExpectedDecomposition.load(from: fixture.appendingPathComponent("expected.json"))
    let modules = try await runBaselinePipeline(fixture: fixture, response: response)
    return DecompositionEval.score(actual: modules, expected: expected)
  }

  private func newPipelineScorecard(fixtureName: String) async throws -> Scorecard {
    let fixture = fixtureURL(fixtureName)
    let expected = try ExpectedDecomposition.load(from: fixture.appendingPathComponent("expected.json"))
    let modules = try await runNewPipeline(fixture: fixture)
    return DecompositionEval.score(actual: modules, expected: expected)
  }

  private func runNewPipeline(fixture: URL) async throws -> [Module] {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let source = try store.insertSource(name: fixture.lastPathComponent, path: fixture.path)
    let pipeline = DecompositionPipeline(
      store: store,
      provider: .openAI,
      model: "phase-4-eval-fixture",
      options: DecompositionPipelineOptions(
        contextBudgetTokens: 4_000,
        confidenceThreshold: 0.7
      ),
      gunkHome: temporaryDirectory.appendingPathComponent("gunk-home-\(UUID().uuidString)")
    )

    _ = try await pipeline.run(
      source: source,
      using: NewPipelineEvalFakeLLMClient(responses: newPipelineResponses(fixtureName: fixture.lastPathComponent))
    )

    return try modulesForSource(store: store, sourceId: source.id)
  }

  private func modulesForSource(store: Store, sourceId: Int64) throws -> [Module] {
    try store.gunksForSource(sourceId: sourceId).map { gunk in
      Module(
        name: gunk.name,
        purpose: gunk.purpose,
        tags: try store.listGunkTags(gunkId: gunk.id).map(\.tag),
        files: try store.filesForGunk(gunkId: gunk.id).map(\.relpath),
        language: gunk.language,
        confidence: gunk.confidence ?? 0
      )
    }
  }

  private func runBaselinePipeline(fixture: URL, response: JSONValue) async throws -> [Module] {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let source = try store.insertSource(name: fixture.lastPathComponent, path: fixture.path)
    _ = try SourceScanner(store: store, sourceId: source.id).scan(folder: fixture)
    let engine = DecompositionEngine(
      store: store,
      provider: .openAI,
      model: "phase-3-baseline-fixture",
      now: timestamps(1_000, 1_250)
    )

    return try await engine.decompose(
      source: source,
      context: "Phase 3 chars/4 baseline fixture replay.",
      using: EvalFakeLLMClient(json: response, usage: LLMTokenUsage(inputTokens: 800, outputTokens: 200))
    )
  }

  private func fixtureURL(_ name: String) -> URL {
    Bundle.module
      .url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
  }

  private func retrosURL() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("docs")
      .appendingPathComponent("retros")
  }

  private func moduleJSON(
    name: String,
    purpose: String,
    tags: [String],
    files: [String],
    language: String = "TypeScript",
    confidence: Double = 0.82
  ) -> JSONValue {
    .object([
      "name": .string(name),
      "purpose": .string(purpose),
      "tags": .array(tags.map(JSONValue.string)),
      "files": .array(files.map(JSONValue.string)),
      "language": .string(language),
      "confidence": .number(confidence)
    ])
  }

  private func modulesJSON(_ modules: [JSONValue]) -> JSONValue {
    .object(["modules": .array(modules)])
  }

  private func newPipelineResponses(fixtureName: String) -> [JSONValue] {
    switch fixtureName {
    case "express-saas":
      return [
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
          anchors: ["google-auth-library", "GOOGLE_CLIENT_ID"]
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
          anchors: ["stripe", "STRIPE_SECRET_KEY"]
        )
      ]
    case "next-media":
      return [
        surveyJSON([
          hypothesisJSON(
            name: "S3 image upload",
            anchors: ["@aws-sdk/client-s3", "S3_BUCKET", "AWS_REGION"],
            seedFiles: ["app/api/upload/route.ts"],
            expectedCollaborators: [
              "src/services/s3Upload.ts",
              "src/config/storage.ts",
              "src/types/upload.ts"
            ]
          ),
          hypothesisJSON(
            name: "Email invite sending",
            anchors: ["nodemailer", "SMTP_URL"],
            seedFiles: ["app/api/invites/route.ts"],
            expectedCollaborators: [
              "src/services/emailInvite.ts",
              "src/config/mail.ts",
              "src/types/invite.ts"
            ]
          )
        ]),
        refinementJSON(
          name: "S3 image upload",
          purpose: "Uploads image blobs to S3 and returns bucket/key metadata.",
          tags: ["api"],
          ownedFiles: [
            "app/api/upload/route.ts",
            "src/services/s3Upload.ts"
          ],
          sharedDependencies: [
            "src/config/storage.ts",
            "src/types/upload.ts"
          ],
          entrypoints: [["path": "app/api/upload/route.ts", "symbol": "POST"]],
          anchors: ["@aws-sdk/client-s3", "S3_BUCKET", "AWS_REGION"]
        ),
        refinementJSON(
          name: "Email invite sending",
          purpose: "Sends invite emails through an SMTP transport.",
          tags: ["email", "api"],
          ownedFiles: [
            "app/api/invites/route.ts",
            "src/services/emailInvite.ts"
          ],
          sharedDependencies: [
            "src/config/mail.ts",
            "src/types/invite.ts"
          ],
          entrypoints: [["path": "app/api/invites/route.ts", "symbol": "POST"]],
          anchors: ["nodemailer", "SMTP_URL"]
        )
      ]
    default:
      return [surveyJSON([])]
    }
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
      "rationale": .string("\(name) is anchored by route, service, config, and type collaborators."),
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
    confidence: Double = 0.92,
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

  private func timestamps(_ values: Int64...) -> () -> Int64 {
    var values = values
    return {
      values.removeFirst()
    }
  }
}

private struct EvalFakeLLMClient: LLMClient {
  let json: JSONValue
  var usage = LLMTokenUsage(inputTokens: nil, outputTokens: nil)

  func complete(request: LLMRequest) async throws -> LLMResponse {
    LLMResponse(json: json, usage: usage)
  }
}

private final class NewPipelineEvalFakeLLMClient: LLMClient {
  private var responses: [JSONValue]

  init(responses: [JSONValue]) {
    self.responses = responses
  }

  func complete(request: LLMRequest) async throws -> LLMResponse {
    _ = request
    return LLMResponse(
      json: responses.removeFirst(),
      usage: LLMTokenUsage(inputTokens: nil, outputTokens: nil)
    )
  }
}
