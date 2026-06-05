import GRDB
import XCTest
@testable import GunkApp

final class DecompositionEvalTests: XCTestCase {
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

  private func baselineScorecard(fixtureName: String, response: JSONValue) async throws -> Scorecard {
    let fixture = fixtureURL(fixtureName)
    let expected = try ExpectedDecomposition.load(from: fixture.appendingPathComponent("expected.json"))
    let modules = try await runBaselinePipeline(fixture: fixture, response: response)
    return DecompositionEval.score(actual: modules, expected: expected)
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
