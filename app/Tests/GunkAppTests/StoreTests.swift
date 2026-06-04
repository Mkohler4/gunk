import Foundation
import GRDB
import XCTest
@testable import GunkApp

final class StoreTests: XCTestCase {
  func testInsertGunkPersists() throws {
    let (store, _) = try makeStore(now: 100)

    let inserted = try store.insertGunk(name: "fixture", path: "/code/fixture")

    XCTAssertEqual(
      try store.listGunks(),
      [
        Gunk(
          id: inserted.id,
          name: "fixture",
          path: "/code/fixture",
          droppedAt: 100,
          removedAt: nil
        )
      ]
    )
  }

  func testListGunksReturnsInDroppedAtDescOrder() throws {
    var timestamp: Int64 = 100
    let queue = try DatabaseQueue()
    let store = try Store(databaseQueue: queue) {
      defer { timestamp += 100 }
      return timestamp
    }

    _ = try store.insertGunk(name: "oldest", path: "/code/oldest")
    _ = try store.insertGunk(name: "middle", path: "/code/middle")
    _ = try store.insertGunk(name: "newest", path: "/code/newest")

    XCTAssertEqual(try store.listGunks().map(\.name), ["newest", "middle", "oldest"])
  }

  func testRemoveGunkSetsRemovedAt() throws {
    let (store, queue) = try makeStore(now: 500)
    let gunk = try store.insertGunk(name: "fixture", path: "/code/fixture")

    try store.removeGunk(id: gunk.id)

    let removedAt = try queue.read { db in
      try Int64.fetchOne(
        db,
        sql: "SELECT removed_at FROM gunks WHERE id = ?",
        arguments: [gunk.id]
      )
    }

    XCTAssertEqual(removedAt, 500)
  }

  func testListGunksExcludesRemoved() throws {
    let (store, _) = try makeStore(now: 500)
    let removed = try store.insertGunk(name: "removed", path: "/code/removed")
    _ = try store.insertGunk(name: "active", path: "/code/active")

    try store.removeGunk(id: removed.id)

    XCTAssertEqual(try store.listGunks().map(\.name), ["active"])
  }

  func testMigrationsAreIdempotent() throws {
    let queue = try DatabaseQueue()

    _ = try Store(databaseQueue: queue, now: { 100 })
    _ = try Store(databaseQueue: queue, now: { 200 })

    let versions = try queue.read { db in
      try Int.fetchAll(db, sql: "SELECT version FROM schema_version")
    }

    XCTAssertEqual(versions, [0, 1])
  }

  func testMigratesExistingV0StoreToV1() throws {
    let queue = try DatabaseQueue()

    try queue.write { db in
      try db.execute(sql: Schema.v0)
      try db.execute(
        sql: "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
        arguments: [0, 100]
      )
    }

    _ = try Store(databaseQueue: queue, now: { 200 })

    let versions = try queue.read { db in
      try Int.fetchAll(db, sql: "SELECT version FROM schema_version")
    }

    let tagCount = try queue.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tags")
    }

    XCTAssertEqual(versions, [0, 1])
    XCTAssertEqual(tagCount, 10)
  }

  func testFileBackedStoreUsesWALMode() throws {
    let folderURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    let storeURL = folderURL.appendingPathComponent("store.db")
    defer { try? FileManager.default.removeItem(at: folderURL) }

    _ = try Store(path: storeURL, now: { 100 })

    let queue = try DatabaseQueue(path: storeURL.path)
    let journalMode = try queue.read { db in
      try String.fetchOne(db, sql: "PRAGMA journal_mode")
    }

    XCTAssertEqual(journalMode, "wal")
  }

  func testMCPListQueryReadsInsertedGunk() throws {
    let (store, queue) = try makeStore(now: 123)
    let inserted = try store.insertGunk(name: "fixture", path: "/code/fixture")

    let row = try queue.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT
            id,
            name,
            path,
            dropped_at AS droppedAt,
            removed_at AS removedAt
          FROM gunks
          WHERE removed_at IS NULL
          ORDER BY dropped_at DESC
          """
      )
    }

    XCTAssertEqual(row?["id"], inserted.id)
    XCTAssertEqual(row?["name"], "fixture")
    XCTAssertEqual(row?["path"], "/code/fixture")
    XCTAssertEqual(row?["droppedAt"], 123)
    XCTAssertNil(row?["removedAt"] as Int64?)
  }

  func testListTagsReturnsTaxonomy() throws {
    let (store, _) = try makeStore(now: 100)

    XCTAssertEqual(
      try store.listTags().map(\.name),
      [
        "api",
        "auth",
        "cli",
        "dashboard",
        "db-layer",
        "email",
        "payments",
        "scraper",
        "search",
        "ui-kit"
      ]
    )
  }

  func testSetGunkTagsReplacesTagsAndRecordsTimestamp() throws {
    var timestamp: Int64 = 100
    let queue = try DatabaseQueue()
    let store = try Store(databaseQueue: queue) {
      defer { timestamp += 100 }
      return timestamp
    }
    let gunk = try store.insertGunk(name: "fixture", path: "/code/fixture")

    try store.setGunkTags(
      gunkId: gunk.id,
      tags: [
        GunkTagInput(tag: "api", confidence: 0.7, source: "heuristic"),
        GunkTagInput(tag: "auth", confidence: 0.9, source: "manual")
      ]
    )
    try store.setGunkTags(
      gunkId: gunk.id,
      tags: [
        GunkTagInput(tag: "payments", confidence: 0.8, source: "llm")
      ]
    )

    XCTAssertEqual(
      try store.listGunkTags(gunkId: gunk.id),
      [
        GunkTag(
          gunkId: gunk.id,
          tag: "payments",
          confidence: 0.8,
          source: "llm",
          taggedAt: 500
        )
      ]
    )
  }

  func testListGunkTagsReturnsTagsOrderedByConfidence() throws {
    let (store, _) = try makeStore(now: 500)
    let gunk = try store.insertGunk(name: "fixture", path: "/code/fixture")

    try store.setGunkTags(
      gunkId: gunk.id,
      tags: [
        GunkTagInput(tag: "api", confidence: 0.7, source: "heuristic"),
        GunkTagInput(tag: "auth", confidence: 0.9, source: "manual")
      ]
    )

    XCTAssertEqual(try store.listGunkTags(gunkId: gunk.id).map(\.tag), [
      "auth",
      "api"
    ])
  }

  func testSchemaMatchesMCPSourceOfTruthByteForByte() throws {
    let schemaDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("mcp/src/schema")

    XCTAssertEqual(
      Data(Schema.v0.utf8),
      try Data(contentsOf: schemaDirectory.appendingPathComponent("v0.sql"))
    )
    XCTAssertEqual(
      Data(Schema.v1.utf8),
      try Data(contentsOf: schemaDirectory.appendingPathComponent("v1.sql"))
    )
  }

  private func makeStore(now: Int64) throws -> (Store, DatabaseQueue) {
    let queue = try DatabaseQueue()
    return (try Store(databaseQueue: queue, now: { now }), queue)
  }
}
