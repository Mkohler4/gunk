import GRDB
import XCTest
@testable import GunkApp

final class CapabilityRefinerTests: XCTestCase {
  func testFinalizesMembershipFromRealFiles() async throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let source = try store.insertSource(name: "fixture", path: "/tmp/fixture")
    let expansion = expansion(
      name: "Google OAuth login",
      ownedFiles: ["src/auth/route.ts", "src/auth/service.ts"],
      sharedDependencyFiles: ["src/lib/db.ts"]
    )
    let client = FakeRefinerLLMClient(
      responses: [
        refinementJSON(
          name: "Google OAuth login",
          purpose: "Authenticates users with Google OAuth and stores the session.",
          tags: ["auth", "api"],
          ownedFiles: [
            "src/auth/route.ts",
            "src/auth/service.ts",
            "src/auth/missing.ts"
          ],
          sharedDependencies: ["src/lib/db.ts", "src/lib/missing.ts"],
          entrypoints: [
            ["path": "src/auth/route.ts", "symbol": "GET"],
            ["path": "src/auth/missing.ts", "symbol": "POST"]
          ],
          anchors: ["route:GET /auth/google"],
          confidence: 1.4
        )
      ]
    )

    let modules = try await CapabilityRefiner(
      store: store,
      provider: .openAI,
      model: "refine-model",
      now: timestamps(1_000, 1_250)
    ).refine(
      source: source,
      expansions: [expansion],
      contentsByPath: [
        "src/auth/route.ts": "export async function GET() { return login(); }",
        "src/auth/service.ts": "export function login() {}",
        "src/lib/db.ts": "export const db = {}"
      ],
      using: client
    )

    XCTAssertEqual(
      modules,
      [
        Module(
          name: "Google OAuth login",
          purpose: "Authenticates users with Google OAuth and stores the session.",
          tags: ["auth", "api"],
          files: ["src/auth/route.ts", "src/auth/service.ts", "src/lib/db.ts"],
          language: "TypeScript",
          confidence: 1,
          ownedFiles: ["src/auth/route.ts", "src/auth/service.ts"],
          sharedDeps: ["src/lib/db.ts"],
          surface: [ModuleSurface(path: "src/auth/route.ts", symbol: "GET")],
          anchors: ["route:GET /auth/google"]
        )
      ]
    )

    let request = try XCTUnwrap(client.requests.first)
    XCTAssertEqual(request.jsonSchemaName, "CapabilityRefinement")
    XCTAssertTrue(request.messages.last?.content.contains("src/auth/route.ts") == true)
    XCTAssertTrue(request.messages.last?.content.contains("export async function GET") == true)
  }

  func testTagsConstrainedToTaxonomy() async throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let source = try store.insertSource(name: "fixture", path: "/tmp/fixture")
    let client = FakeRefinerLLMClient(
      responses: [
        refinementJSON(
          tags: ["auth", "invented", "api"],
          ownedFiles: ["src/auth/route.ts"],
          sharedDependencies: []
        )
      ]
    )

    let modules = try await CapabilityRefiner(
      store: store,
      provider: .anthropic,
      model: "refine-model"
    ).refine(
      source: source,
      expansions: [
        expansion(name: "Auth route", ownedFiles: ["src/auth/route.ts"])
      ],
      contentsByPath: ["src/auth/route.ts": "export function GET() {}"],
      using: client
    )

    XCTAssertEqual(modules.first?.tags, ["auth", "api"])
  }

  func testRecordsLLMRunPerCandidate() async throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let source = try store.insertSource(name: "fixture", path: "/tmp/fixture")
    let client = FakeRefinerLLMClient(
      responses: [
        refinementJSON(
          name: "Auth route",
          ownedFiles: ["src/auth/route.ts"],
          sharedDependencies: []
        ),
        refinementJSON(
          name: "Billing route",
          ownedFiles: ["src/billing/route.ts"],
          sharedDependencies: []
        )
      ],
      usages: [
        LLMTokenUsage(inputTokens: 101, outputTokens: 11),
        LLMTokenUsage(inputTokens: 202, outputTokens: 22)
      ]
    )

    _ = try await CapabilityRefiner(
      store: store,
      provider: .ollama,
      model: "refine-model",
      now: timestamps(2_000, 2_100, 2_500, 2_650)
    ).refine(
      source: source,
      expansions: [
        expansion(name: "Auth route", ownedFiles: ["src/auth/route.ts"]),
        expansion(name: "Billing route", ownedFiles: ["src/billing/route.ts"])
      ],
      contentsByPath: [
        "src/auth/route.ts": "export function GET() {}",
        "src/billing/route.ts": "export function POST() {}"
      ],
      using: client
    )

    let runs = try store.llmRunsForSource(sourceId: source.id).sorted { $0.startedAt < $1.startedAt }
    XCTAssertEqual(client.requests.count, 2)
    XCTAssertEqual(runs.count, 2)
    XCTAssertEqual(runs.map(\.provider), [LLMProvider.ollama.rawValue, LLMProvider.ollama.rawValue])
    XCTAssertEqual(runs.map(\.model), ["refine-model", "refine-model"])
    XCTAssertEqual(runs.map(\.inputTokens), [101, 202])
    XCTAssertEqual(runs.map(\.outputTokens), [11, 22])
    XCTAssertEqual(runs.map(\.startedAt), [2_000, 2_500])
    XCTAssertEqual(runs.map(\.finishedAt), [2_100, 2_650])
  }

  private func expansion(
    name: String,
    ownedFiles: [String],
    sharedDependencyFiles: [String] = []
  ) -> CapabilityExpansion {
    let closureFiles = (ownedFiles + sharedDependencyFiles).sorted()

    return CapabilityExpansion(
      hypothesis: CapabilityHypothesis(
        name: name,
        rationale: "\(name) rationale",
        anchors: ["route"],
        seedFiles: [ownedFiles[0]],
        expectedCollaborators: [],
        granularity: "feature",
        priority: .normal
      ),
      closureFiles: closureFiles,
      ownedFiles: ownedFiles.sorted(),
      sharedDependencyFiles: sharedDependencyFiles.sorted(),
      excludedFiles: [],
      edgeEvidence: []
    )
  }

  private func refinementJSON(
    name: String = "Refined capability",
    purpose: String = "Refined purpose.",
    tags: [String] = ["auth"],
    ownedFiles: [String],
    sharedDependencies: [String],
    entrypoints: [[String: String]] = [],
    anchors: [String] = ["route"],
    confidence: Double = 0.8,
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

private final class FakeRefinerLLMClient: LLMClient {
  private var responses: [JSONValue]
  private var usages: [LLMTokenUsage]
  private(set) var requests: [LLMRequest] = []

  init(
    responses: [JSONValue],
    usages: [LLMTokenUsage]? = nil
  ) {
    self.responses = responses
    self.usages = usages ?? Array(repeating: LLMTokenUsage(inputTokens: nil, outputTokens: nil), count: responses.count)
  }

  func complete(request: LLMRequest) async throws -> LLMResponse {
    requests.append(request)
    return LLMResponse(json: responses.removeFirst(), usage: usages.removeFirst())
  }
}
