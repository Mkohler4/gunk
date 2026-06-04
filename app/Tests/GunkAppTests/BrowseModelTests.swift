import GRDB
import XCTest
@testable import GunkApp

@MainActor
final class BrowseModelTests: XCTestCase {
  func testGroupsByTag() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let auth = try insertGunk(
      store: store,
      source: source,
      name: "auth-module",
      tags: ["auth", "api"],
      confidence: 0.91,
      extractedAt: 200
    )
    let cli = try insertGunk(
      store: store,
      source: source,
      name: "cli-module",
      tags: ["cli"],
      confidence: 0.84,
      extractedAt: 300
    )
    let model = BrowseModel(store: store)

    model.refresh()

    let itemsBySection = Dictionary(uniqueKeysWithValues: model.sections.map { section in
      (section.tag, section.items.map(\.gunk.id))
    })

    XCTAssertEqual(itemsBySection["api"], [auth.id])
    XCTAssertEqual(itemsBySection["auth"], [auth.id])
    XCTAssertEqual(itemsBySection["cli"], [cli.id])
    XCTAssertTrue(model.approvalQueue.isEmpty)
  }

  func testApproveMarksApprovedAt() throws {
    let store = try makeStore(now: { 500 })
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let lowConfidence = try insertGunk(
      store: store,
      source: source,
      name: "maybe-auth",
      tags: ["auth"],
      confidence: 0.42
    )
    var extractedIds: [Int64] = []
    let model = BrowseModel(
      store: store,
      extractGunk: { gunk in
        extractedIds.append(gunk.id)
      }
    )

    model.refresh()
    XCTAssertEqual(model.approvalQueue.map(\.gunk.id), [lowConfidence.id])

    model.approve(gunkId: lowConfidence.id)

    XCTAssertEqual(try store.gunk(id: lowConfidence.id)?.approvedAt, 500)
    XCTAssertEqual(extractedIds, [lowConfidence.id])
    XCTAssertTrue(model.approvalQueue.isEmpty)
    XCTAssertEqual(model.sections.flatMap(\.items).map(\.gunk.id), [lowConfidence.id])
  }

  func testDeleteRemovesModule() throws {
    let store = try makeStore(now: { 700 })
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let removed = try insertGunk(
      store: store,
      source: source,
      name: "old-auth",
      tags: ["auth"],
      confidence: 0.8,
      extractedAt: 300
    )
    let active = try insertGunk(
      store: store,
      source: source,
      name: "active-cli",
      tags: ["cli"],
      confidence: 0.8,
      extractedAt: 400
    )
    let model = BrowseModel(store: store)
    model.refresh()

    model.delete(gunkId: removed.id)

    XCTAssertNil(try store.gunk(id: removed.id))
    XCTAssertEqual(try store.listGunks().map(\.id), [active.id])
    XCTAssertEqual(model.sections.flatMap(\.items).map(\.gunk.id), [active.id])
  }

  func testReclassifyTargetsSource() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    var reclassifiedSourceIds: [Int64] = []
    let model = BrowseModel(
      store: store,
      reclassifySource: { sourceId in
        reclassifiedSourceIds.append(sourceId)
      }
    )

    model.reclassify(sourceId: source.id)

    XCTAssertEqual(reclassifiedSourceIds, [source.id])
  }

  private func makeStore(now: @escaping () -> Int64 = { 100 }) throws -> Store {
    try Store(databaseQueue: DatabaseQueue(), now: now)
  }

  private func insertGunk(
    store: Store,
    source: Source,
    name: String,
    tags: [String],
    confidence: Double,
    extractedAt: Int64? = nil
  ) throws -> Gunk {
    let gunk = try store.insertGunk(
      sourceId: source.id,
      name: name,
      purpose: "\(name) purpose",
      language: "Swift",
      confidence: confidence,
      bundlePath: extractedAt.map { _ in "/tmp/modules/\(name)" },
      manifestPath: extractedAt.map { _ in "/tmp/modules/\(name)/gunk.yml" },
      extractedAt: extractedAt
    )

    for tagName in tags {
      let tag = try store.addTag(name: tagName)
      try store.addGunkTag(gunkId: gunk.id, tagId: tag.id, confidence: confidence)
    }

    return gunk
  }
}
