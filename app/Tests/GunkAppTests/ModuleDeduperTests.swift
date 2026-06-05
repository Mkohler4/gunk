import GRDB
import XCTest
@testable import GunkApp

final class ModuleDeduperTests: XCTestCase {
  func testClustersNearDuplicateAuthModules() throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let firstSource = try store.insertSource(name: "first", path: "/code/first")
    let secondSource = try store.insertSource(name: "second", path: "/code/second")
    let firstAuth = try gunk(
      store: store,
      source: firstSource,
      name: "Google OAuth login",
      confidence: 0.91,
      tags: ["auth", "api"],
      vector: [1, 0]
    )
    let secondAuth = try gunk(
      store: store,
      source: secondSource,
      name: "Social sign-in",
      confidence: 0.88,
      tags: ["auth", "api"],
      vector: [0.98, 0.02]
    )

    let cluster = try XCTUnwrap(ModuleDeduper(store: store).dedupe(gunk: secondAuth))

    XCTAssertEqual(cluster.canonicalGunkId, firstAuth.id)
    XCTAssertEqual(cluster.memberGunkIds, [firstAuth.id, secondAuth.id])
    XCTAssertEqual(cluster.variantCount, 2)
    XCTAssertEqual(
      try store.gunkClusterMembership(memberGunkId: secondAuth.id)?.canonicalGunkId,
      firstAuth.id
    )
  }

  func testChoosesCanonicalAndCountsVariants() throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let firstSource = try store.insertSource(name: "first", path: "/code/first")
    let secondSource = try store.insertSource(name: "second", path: "/code/second")
    let thirdSource = try store.insertSource(name: "third", path: "/code/third")
    let lowerConfidence = try gunk(
      store: store,
      source: firstSource,
      name: "OAuth login",
      confidence: 0.8,
      tags: ["auth"],
      vector: [1, 0]
    )
    let highestConfidence = try gunk(
      store: store,
      source: secondSource,
      name: "Google auth",
      confidence: 0.96,
      tags: ["auth"],
      vector: [0.99, 0.01]
    )
    let thirdAuth = try gunk(
      store: store,
      source: thirdSource,
      name: "SSO login",
      confidence: 0.9,
      tags: ["auth"],
      vector: [0.97, 0.03]
    )

    _ = try ModuleDeduper(store: store).dedupe(gunk: highestConfidence)
    let cluster = try XCTUnwrap(ModuleDeduper(store: store).dedupe(gunk: thirdAuth))

    XCTAssertEqual(cluster.canonicalGunkId, highestConfidence.id)
    XCTAssertEqual(cluster.memberGunkIds, [
      lowerConfidence.id,
      highestConfidence.id,
      thirdAuth.id
    ])
    XCTAssertEqual(cluster.variantCount, 3)
    XCTAssertEqual(try store.gunkClusterMembers(canonicalGunkId: highestConfidence.id).count, 3)
  }

  private func gunk(
    store: Store,
    source: Source,
    name: String,
    confidence: Double,
    tags: [String],
    vector: [Double]
  ) throws -> Gunk {
    let gunk = try store.insertGunk(
      sourceId: source.id,
      name: name,
      purpose: "\(name) purpose",
      language: "TypeScript",
      confidence: confidence,
      extractedAt: 200
    )

    for tagName in tags {
      let tag = try store.addTag(name: tagName)
      try store.addGunkTag(gunkId: gunk.id, tagId: tag.id, confidence: confidence)
    }

    try store.upsertGunkEmbedding(gunkId: gunk.id, vector: vector, model: "test")
    return gunk
  }
}
