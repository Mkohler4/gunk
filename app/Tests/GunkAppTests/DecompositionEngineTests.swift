import GRDB
import XCTest
@testable import GunkApp

final class DecompositionEngineTests: XCTestCase {
  func testPersistsModulesWithTagsAndFiles() async throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let source = try store.insertSource(name: "fixture", path: "/tmp/fixture")
    try store.addSourceFile(sourceId: source.id, relpath: "README.md", size: 10)
    try store.addSourceFile(sourceId: source.id, relpath: "Sources/Auth.swift", size: 42)
    let engine = DecompositionEngine(
      store: store,
      provider: .openAI,
      model: "fixture-model",
      now: timestamps(1_000, 1_250)
    )

    let modules = try await engine.decompose(
      source: source,
      context: "File tree:\n- README.md\n- Sources/Auth.swift\n",
      using: FakeLLMClient(
        json: modulesJSON([
          moduleJSON(
            name: "auth-module",
            purpose: "Handles sign in",
            tags: ["auth", "api"],
            files: ["README.md", "Sources/Auth.swift"],
            language: "Swift",
            confidence: 0.91
          )
        ]),
        usage: LLMTokenUsage(inputTokens: 123, outputTokens: 45)
      )
    )

    XCTAssertEqual(
      modules,
      [
        Module(
          name: "auth-module",
          purpose: "Handles sign in",
          tags: ["auth", "api"],
          files: ["README.md", "Sources/Auth.swift"],
          language: "Swift",
          confidence: 0.91
        )
      ]
    )

    let gunk = try XCTUnwrap(try store.gunksForSource(sourceId: source.id).first)
    XCTAssertEqual(gunk.name, "auth-module")
    XCTAssertEqual(gunk.purpose, "Handles sign in")
    XCTAssertEqual(gunk.language, "Swift")
    XCTAssertEqual(gunk.confidence, 0.91)
    XCTAssertEqual(try store.listGunkTags(gunkId: gunk.id).map(\.tag), ["api", "auth"])
    XCTAssertEqual(
      try store.filesForGunk(gunkId: gunk.id).map(\.relpath),
      ["README.md", "Sources/Auth.swift"]
    )
  }

  func testDropsModulesWithUnknownFiles() async throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let source = try store.insertSource(name: "fixture", path: "/tmp/fixture")
    try store.addSourceFile(sourceId: source.id, relpath: "Sources/Auth.swift", size: 42)
    let engine = DecompositionEngine(
      store: store,
      provider: .anthropic,
      model: "fixture-model",
      now: timestamps(1_000, 1_250)
    )

    let modules = try await engine.decompose(
      source: source,
      context: "File tree:\n- Sources/Auth.swift\n",
      using: FakeLLMClient(
        json: modulesJSON([
          moduleJSON(
            name: "valid-module",
            tags: ["auth"],
            files: ["Sources/Auth.swift"]
          ),
          moduleJSON(
            name: "phantom-module",
            tags: ["api"],
            files: ["Sources/Missing.swift"]
          )
        ])
      )
    )

    XCTAssertEqual(modules.map(\.name), ["valid-module"])
    XCTAssertEqual(try store.gunksForSource(sourceId: source.id).map(\.name), ["valid-module"])
  }

  func testClampsConfidence() async throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let source = try store.insertSource(name: "fixture", path: "/tmp/fixture")
    try store.addSourceFile(sourceId: source.id, relpath: "Sources/Auth.swift", size: 42)
    let engine = DecompositionEngine(
      store: store,
      provider: .ollama,
      model: "fixture-model",
      now: timestamps(1_000, 1_250)
    )

    _ = try await engine.decompose(
      source: source,
      context: "File tree:\n- Sources/Auth.swift\n",
      using: FakeLLMClient(
        json: modulesJSON([
          moduleJSON(name: "low", files: ["Sources/Auth.swift"], confidence: -0.2),
          moduleJSON(name: "high", files: ["Sources/Auth.swift"], confidence: 1.7)
        ])
      )
    )

    let confidenceByName = Dictionary(
      uniqueKeysWithValues: try store.gunksForSource(sourceId: source.id).map { ($0.name, $0.confidence) }
    )
    XCTAssertEqual(confidenceByName["low"] ?? nil, 0)
    XCTAssertEqual(confidenceByName["high"] ?? nil, 1)
  }

  func testRecordsLLMRun() async throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let source = try store.insertSource(name: "fixture", path: "/tmp/fixture")
    let engine = DecompositionEngine(
      store: store,
      provider: .openAI,
      model: "fixture-model",
      now: timestamps(2_000, 2_500)
    )

    _ = try await engine.decompose(
      source: source,
      context: "File tree:\n",
      using: FakeLLMClient(
        json: modulesJSON([]),
        usage: LLMTokenUsage(inputTokens: 321, outputTokens: 67)
      )
    )

    let run = try XCTUnwrap(try store.llmRunsForSource(sourceId: source.id).first)
    XCTAssertEqual(run.provider, LLMProvider.openAI.rawValue)
    XCTAssertEqual(run.model, "fixture-model")
    XCTAssertEqual(run.inputTokens, 321)
    XCTAssertEqual(run.outputTokens, 67)
    XCTAssertEqual(run.startedAt, 2_000)
    XCTAssertEqual(run.finishedAt, 2_500)
  }

  private func moduleJSON(
    name: String,
    purpose: String = "Purpose",
    tags: [String] = ["auth"],
    files: [String],
    language: String = "Swift",
    confidence: Double = 0.8
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

private struct FakeLLMClient: LLMClient {
  let json: JSONValue
  var usage = LLMTokenUsage(inputTokens: nil, outputTokens: nil)

  func complete(request: LLMRequest) async throws -> LLMResponse {
    LLMResponse(json: json, usage: usage)
  }
}
