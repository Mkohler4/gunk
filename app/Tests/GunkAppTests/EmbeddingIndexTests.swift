import GRDB
import XCTest
@testable import GunkApp

final class EmbeddingIndexTests: XCTestCase {
  func testCosineRanksParaphraseMatch() async throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let source = try store.insertSource(name: "source", path: "/code/source")
    let auth = try store.insertGunk(
      sourceId: source.id,
      name: "Google OAuth login",
      purpose: "Authenticates users with Google OAuth and creates a session.",
      language: "TypeScript",
      confidence: 0.92,
      extractedAt: 200
    )
    let cli = try store.insertGunk(
      sourceId: source.id,
      name: "Maintenance CLI",
      purpose: "Runs command line maintenance tasks.",
      language: "TypeScript",
      confidence: 0.9,
      extractedAt: 210
    )
    let authTag = try store.addTag(name: "auth")
    let cliTag = try store.addTag(name: "cli")
    try store.addGunkTag(gunkId: auth.id, tagId: authTag.id, confidence: 0.92)
    try store.addGunkTag(gunkId: cli.id, tagId: cliTag.id, confidence: 0.9)
    try store.addGunkFile(gunkId: auth.id, relpath: "src/routes/auth.ts", size: 100)
    try store.addGunkFile(gunkId: cli.id, relpath: "src/cli/maintenance.ts", size: 100)

    let index = EmbeddingIndex(store: store, embedder: KeywordEmbeddingProvider())
    try await index.index(gunk: auth)
    try await index.index(gunk: cli)

    let results = try await index.search(query: "sign in with google", limit: 2)

    XCTAssertEqual(results.map(\.gunk.id), [auth.id])
    XCTAssertEqual(try XCTUnwrap(results.first).score, 1, accuracy: 0.0001)
  }
}

private struct KeywordEmbeddingProvider: EmbeddingProvider {
  let model = "keyword-test"

  func embed(text: String) async throws -> [Double] {
    let normalized = text.lowercased()

    if normalized.contains("google")
      || normalized.contains("oauth")
      || normalized.contains("auth")
      || normalized.contains("sign in") {
      return [1, 0]
    }

    if normalized.contains("cli")
      || normalized.contains("command")
      || normalized.contains("maintenance") {
      return [0, 1]
    }

    return [0, 0]
  }
}
