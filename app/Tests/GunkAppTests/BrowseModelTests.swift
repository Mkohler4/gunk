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
    let model = BrowseModel(
      store: store,
      extractGunk: { _ in }
    )

    model.refresh()

    let itemsBySection = Dictionary(uniqueKeysWithValues: model.sections.map { section in
      (section.tag, section.items.map(\.gunk.id))
    })

    XCTAssertEqual(itemsBySection["api"], [auth.id])
    XCTAssertEqual(itemsBySection["auth"], [auth.id])
    XCTAssertEqual(itemsBySection["cli"], [cli.id])
    XCTAssertTrue(model.approvalQueue.isEmpty)
  }

  func testFiltersModulesBySourceTagLanguageAndApproval() throws {
    let store = try makeStore()
    let apiSource = try store.insertSource(name: "api", path: "/tmp/api")
    let cliSource = try store.insertSource(name: "cli", path: "/tmp/cli")
    let apiModule = try insertGunk(
      store: store,
      source: apiSource,
      name: "api-auth",
      tags: ["auth", "sessions"],
      language: "Swift",
      confidence: 0.92,
      extractedAt: 200
    )
    _ = try insertGunk(
      store: store,
      source: cliSource,
      name: "cli-reports",
      tags: ["reports"],
      language: "Go",
      confidence: 0.81,
      extractedAt: 300
    )
    let model = BrowseModel(store: store)

    model.refresh()
    model.filters.sourceId = apiSource.id
    model.filters.tag = "auth"
    model.filters.language = "Swift"
    model.filters.approval = .autoAccepted
    model.filters.group = .source

    XCTAssertEqual(model.sections.flatMap(\.items).map(\.gunk.id), [apiModule.id])
    XCTAssertEqual(model.availableTags, ["auth", "reports", "sessions"])
    XCTAssertEqual(model.availableLanguages, ["Go", "Swift"])
    XCTAssertEqual(model.availableSources.map(\.name), ["api", "cli"])
  }

  func testGroupsModulesBySourceLanguageAndApproval() throws {
    let store = try makeStore(now: { 500 })
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let approved = try insertGunk(
      store: store,
      source: source,
      name: "approved-module",
      tags: ["auth"],
      language: "Swift",
      confidence: 0.42
    )
    let extracted = try insertGunk(
      store: store,
      source: source,
      name: "extracted-module",
      tags: ["auth"],
      language: "Go",
      confidence: 0.93,
      extractedAt: 300
    )
    let pending = try insertGunk(
      store: store,
      source: source,
      name: "pending-module",
      tags: ["queue"],
      language: nil,
      confidence: 0.35
    )
    let model = BrowseModel(store: store)

    model.approve(gunkId: approved.id)
    model.refresh()

    model.filters.group = .language
    XCTAssertEqual(
      Dictionary(uniqueKeysWithValues: model.sections.map { ($0.tag, $0.items.map(\.gunk.id)) }),
      [
        "Go": [extracted.id],
        "Swift": [approved.id],
        "Unknown language": [pending.id],
      ]
    )

    model.filters.group = .approval
    XCTAssertEqual(
      Dictionary(uniqueKeysWithValues: model.sections.map { ($0.tag, $0.items.map(\.gunk.id)) }),
      [
        "Approved": [approved.id],
        "Auto accepted": [extracted.id],
        "Needs approval": [pending.id],
      ]
    )
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
    language: String? = "Swift",
    confidence: Double,
    extractedAt: Int64? = nil
  ) throws -> Gunk {
    let gunk = try store.insertGunk(
      sourceId: source.id,
      name: name,
      purpose: "\(name) purpose",
      language: language,
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
