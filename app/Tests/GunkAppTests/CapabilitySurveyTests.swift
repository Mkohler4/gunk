import GRDB
import XCTest
@testable import GunkApp

final class CapabilitySurveyTests: XCTestCase {
  func testParsesHypothesesWithAnchors() async throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let source = try seededSource(store: store)
    let client = FakeSurveyLLMClient(
      response: .object([
        "hypotheses": .array([
          hypothesisJSON(
            name: "Google OAuth login",
            rationale: "Route, OAuth dependency, and session collaborator form an auth capability.",
            anchors: ["route:GET /auth/google", "passport-google-oauth20[auth/google/oauth]"],
            seedFiles: ["src/auth/routes.ts"],
            expectedCollaborators: ["src/auth/service.ts"],
            granularity: "feature"
          ),
          hypothesisJSON(
            name: "Weak single file",
            rationale: "Has no explicit anchor and one seed.",
            anchors: [],
            seedFiles: ["src/auth/service.ts"],
            expectedCollaborators: [],
            granularity: "utility"
          )
        ])
      ])
    )

    let hypotheses = try await CapabilitySurvey(
      store: store,
      provider: .openAI,
      model: "survey-model",
      now: timestamps(1_000, 1_200)
    ).survey(source: source, repoMap: "repo_map_v1\nroutes: express:GET /auth/google", using: client)

    XCTAssertEqual(
      hypotheses,
      [
        CapabilityHypothesis(
          name: "Google OAuth login",
          rationale: "Route, OAuth dependency, and session collaborator form an auth capability.",
          anchors: ["route:GET /auth/google", "passport-google-oauth20[auth/google/oauth]"],
          seedFiles: ["src/auth/routes.ts"],
          expectedCollaborators: ["src/auth/service.ts"],
          granularity: "feature",
          priority: .normal
        ),
        CapabilityHypothesis(
          name: "Weak single file",
          rationale: "Has no explicit anchor and one seed.",
          anchors: [],
          seedFiles: ["src/auth/service.ts"],
          expectedCollaborators: [],
          granularity: "utility",
          priority: .low
        )
      ]
    )

    let request = try XCTUnwrap(client.requests.first)
    XCTAssertEqual(request.jsonSchemaName, "CapabilitySurvey")
    XCTAssertTrue(request.messages.first?.content.contains("Real-module rubric") == true)
    XCTAssertTrue(request.messages.last?.content.contains("repo_map_v1") == true)
  }

  func testDropsHypothesesCitingUnknownFiles() async throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let source = try seededSource(store: store)
    let client = FakeSurveyLLMClient(
      response: .object([
        "hypotheses": .array([
          hypothesisJSON(
            name: "Known capability",
            anchors: ["route:GET /auth/google"],
            seedFiles: ["src/auth/routes.ts"],
            expectedCollaborators: ["src/auth/service.ts"]
          ),
          hypothesisJSON(
            name: "Unknown seed",
            anchors: ["route:GET /ghost"],
            seedFiles: ["src/missing/routes.ts"],
            expectedCollaborators: []
          ),
          hypothesisJSON(
            name: "Unknown collaborator",
            anchors: ["route:GET /auth/google"],
            seedFiles: ["src/auth/routes.ts"],
            expectedCollaborators: ["src/missing/service.ts"]
          )
        ])
      ])
    )

    let hypotheses = try await CapabilitySurvey(
      store: store,
      provider: .anthropic,
      model: "survey-model"
    ).survey(source: source, repoMap: "repo_map_v1", using: client)

    XCTAssertEqual(hypotheses.map(\.name), ["Known capability"])
    XCTAssertEqual(hypotheses.first?.seedFiles, ["src/auth/routes.ts"])
  }

  func testRecordsLLMRun() async throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let source = try seededSource(store: store)
    let client = FakeSurveyLLMClient(
      response: .object(["hypotheses": .array([])]),
      usage: LLMTokenUsage(inputTokens: 456, outputTokens: 78)
    )

    _ = try await CapabilitySurvey(
      store: store,
      provider: .ollama,
      model: "survey-model",
      now: timestamps(2_000, 2_450)
    ).survey(source: source, repoMap: "repo_map_v1", using: client)

    let run = try XCTUnwrap(try store.llmRunsForSource(sourceId: source.id).first)
    XCTAssertEqual(run.provider, LLMProvider.ollama.rawValue)
    XCTAssertEqual(run.model, "survey-model")
    XCTAssertEqual(run.inputTokens, 456)
    XCTAssertEqual(run.outputTokens, 78)
    XCTAssertEqual(run.startedAt, 2_000)
    XCTAssertEqual(run.finishedAt, 2_450)
  }

  private func seededSource(store: Store) throws -> Source {
    let source = try store.insertSource(name: "fixture", path: "/tmp/fixture")
    try store.addSourceFile(sourceId: source.id, relpath: "src/auth/routes.ts", size: 100)
    try store.addSourceFile(sourceId: source.id, relpath: "src/auth/service.ts", size: 100)
    return source
  }

  private func hypothesisJSON(
    name: String,
    rationale: String = "Rationale",
    anchors: [String],
    seedFiles: [String],
    expectedCollaborators: [String],
    granularity: String = "feature"
  ) -> JSONValue {
    .object([
      "name": .string(name),
      "rationale": .string(rationale),
      "anchors": .array(anchors.map(JSONValue.string)),
      "seedFiles": .array(seedFiles.map(JSONValue.string)),
      "expectedCollaborators": .array(expectedCollaborators.map(JSONValue.string)),
      "granularity": .string(granularity)
    ])
  }

  private func timestamps(_ values: Int64...) -> () -> Int64 {
    var values = values
    return {
      values.removeFirst()
    }
  }
}

private final class FakeSurveyLLMClient: LLMClient {
  private let response: JSONValue
  private let usage: LLMTokenUsage
  private(set) var requests: [LLMRequest] = []

  init(
    response: JSONValue,
    usage: LLMTokenUsage = LLMTokenUsage(inputTokens: nil, outputTokens: nil)
  ) {
    self.response = response
    self.usage = usage
  }

  func complete(request: LLMRequest) async throws -> LLMResponse {
    requests.append(request)
    return LLMResponse(json: response, usage: usage)
  }
}
