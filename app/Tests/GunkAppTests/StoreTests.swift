import Foundation
import GRDB
import XCTest
@testable import GunkApp

final class StoreTests: XCTestCase {
  func testInsertSourcePersists() throws {
    let (store, _) = try makeStore(now: 100)

    let inserted = try store.insertSource(name: "fixture", path: "/code/fixture")

    XCTAssertEqual(
      try store.listSources(),
      [
        Source(
          id: inserted.id,
          name: "fixture",
          path: "/code/fixture",
          droppedAt: 100,
          removedAt: nil
        )
      ]
    )
  }

  func testListSourcesReturnsInDroppedAtDescOrder() throws {
    var timestamp: Int64 = 100
    let queue = try DatabaseQueue()
    let store = try Store(databaseQueue: queue) {
      defer { timestamp += 100 }
      return timestamp
    }

    _ = try store.insertSource(name: "oldest", path: "/code/oldest")
    _ = try store.insertSource(name: "middle", path: "/code/middle")
    _ = try store.insertSource(name: "newest", path: "/code/newest")

    XCTAssertEqual(try store.listSources().map(\.name), ["newest", "middle", "oldest"])
  }

  func testRemoveSourceSetsRemovedAt() throws {
    let (store, queue) = try makeStore(now: 500)
    let source = try store.insertSource(name: "fixture", path: "/code/fixture")

    try store.removeSource(id: source.id)

    let removedAt = try queue.read { db in
      try Int64.fetchOne(
        db,
        sql: "SELECT removed_at FROM sources WHERE id = ?",
        arguments: [source.id]
      )
    }

    XCTAssertEqual(removedAt, 500)
  }

  func testListSourcesExcludesRemoved() throws {
    let (store, _) = try makeStore(now: 500)
    let removed = try store.insertSource(name: "removed", path: "/code/removed")
    _ = try store.insertSource(name: "active", path: "/code/active")

    try store.removeSource(id: removed.id)

    XCTAssertEqual(try store.listSources().map(\.name), ["active"])
  }

  func testMigrationsAreIdempotentThroughV5() throws {
    let queue = try DatabaseQueue()

    _ = try Store(databaseQueue: queue, now: { 100 })
    _ = try Store(databaseQueue: queue, now: { 200 })

    let versions = try queue.read { db in
      try Int.fetchAll(db, sql: "SELECT version FROM schema_version")
    }

    XCTAssertEqual(versions, [0, 1, 2, 3, 4, 5])
  }

  func testV0ToV5UpgradePreservesSources() throws {
    let queue = try DatabaseQueue()

    try queue.write { db in
      try db.execute(sql: Schema.v0)
      try db.execute(
        sql: "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
        arguments: [0, 100]
      )
      try db.execute(
        sql: """
          INSERT INTO gunks (id, name, path, dropped_at, removed_at)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [1, "fixture-source", "/code/fixture-source", 150, nil]
      )
      try db.execute(
        sql: """
          INSERT INTO files (id, gunk_id, relpath, size)
          VALUES (?, ?, ?, ?)
          """,
        arguments: [1, 1, "README.md", 42]
      )
    }

    _ = try Store(databaseQueue: queue, now: { 200 })

    let versions = try queue.read { db in
      try Int.fetchAll(db, sql: "SELECT version FROM schema_version")
    }
    let source = try queue.read { db in
      try Row.fetchOne(db, sql: "SELECT id, name, path, dropped_at, removed_at FROM sources")
        .map(StoreTests.source(from:))
    }
    let file = try queue.read { db in
      try Row.fetchOne(db, sql: "SELECT source_id, relpath, size FROM files")
    }

    XCTAssertEqual(versions, [0, 1, 2, 3, 4, 5])
    XCTAssertEqual(
      source,
      Source(
        id: 1,
        name: "fixture-source",
        path: "/code/fixture-source",
        droppedAt: 150,
        removedAt: nil
      )
    )
    XCTAssertEqual(file?["source_id"] as Int64?, 1)
    XCTAssertEqual(file?["relpath"] as String?, "README.md")
    XCTAssertEqual(file?["size"] as Int64?, 42)
  }

  func testExistingV1StoreUpgradesToV4PreservingSources() throws {
    let queue = try DatabaseQueue()

    try queue.write { db in
      try db.execute(sql: Schema.v0)
      try db.execute(
        sql: "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
        arguments: [0, 100]
      )
      try db.execute(
        sql: """
          INSERT INTO gunks (id, name, path, dropped_at, removed_at)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [1, "v1-source", "/code/v1-source", 150, nil]
      )
      try db.execute(sql: Schema.v1)
      try db.execute(
        sql: "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
        arguments: [1, 125]
      )
    }

    _ = try Store(databaseQueue: queue, now: { 200 })

    let source = try queue.read { db in
      try Row.fetchOne(db, sql: "SELECT id, name, path, dropped_at, removed_at FROM sources")
        .map(StoreTests.source(from:))
    }

    XCTAssertEqual(
      source,
      Source(
        id: 1,
        name: "v1-source",
        path: "/code/v1-source",
        droppedAt: 150,
        removedAt: nil
      )
    )
  }

  func testInsertGunkPersistsWithSourceLink() throws {
    let (store, _) = try makeStore(now: 100)
    let source = try store.insertSource(name: "source", path: "/code/source")

    let gunk = try store.insertGunk(
      sourceId: source.id,
      name: "auth-module",
      purpose: "Google OAuth flow",
      language: "TypeScript",
      confidence: 0.91,
      bundlePath: "/tmp/modules/1",
      manifestPath: "/tmp/modules/1/gunk.yml",
      extractedAt: 200
    )

    XCTAssertEqual(
      try store.gunksForSource(sourceId: source.id),
      [
        Gunk(
          id: gunk.id,
          sourceId: source.id,
          name: "auth-module",
          purpose: "Google OAuth flow",
          language: "TypeScript",
          confidence: 0.91,
          bundlePath: "/tmp/modules/1",
          manifestPath: "/tmp/modules/1/gunk.yml",
          extractedAt: 200,
          approvedAt: nil,
          removedAt: nil
        )
      ]
    )
  }

  func testAddTagAndQueryByTag() throws {
    let (store, _) = try makeStore(now: 100)
    let source = try store.insertSource(name: "source", path: "/code/source")
    let gunk = try store.insertGunk(sourceId: source.id, name: "auth-module")
    let auth = try store.addTag(name: "auth")

    try store.addGunkTag(gunkId: gunk.id, tagId: auth.id, confidence: 0.9)

    XCTAssertEqual(
      try store.listGunkTags(gunkId: gunk.id),
      [
        GunkTag(
          gunkId: gunk.id,
          tagId: auth.id,
          tag: "auth",
          confidence: 0.9
        )
      ]
    )
  }

  func testAddGunkFilePersists() throws {
    let (store, _) = try makeStore(now: 100)
    let source = try store.insertSource(name: "source", path: "/code/source")
    let gunk = try store.insertGunk(sourceId: source.id, name: "auth-module")

    let file = try store.addGunkFile(gunkId: gunk.id, relpath: "auth.ts", size: 256)

    XCTAssertEqual(
      try store.filesForGunk(gunkId: gunk.id),
      [
        GunkFile(
          id: file.id,
          gunkId: gunk.id,
          relpath: "auth.ts",
          size: 256
        )
      ]
    )
  }

  func testRecordLLMRunPersists() throws {
    let (store, _) = try makeStore(now: 100)
    let source = try store.insertSource(name: "source", path: "/code/source")

    let run = try store.recordLLMRun(
      sourceId: source.id,
      provider: "openai",
      model: "gpt-5",
      inputTokens: 1000,
      outputTokens: 200,
      costUsd: 0.12,
      finishedAt: 150
    )

    XCTAssertEqual(
      run,
      LLMRun(
        id: run.id,
        sourceId: source.id,
        provider: "openai",
        model: "gpt-5",
        inputTokens: 1000,
        outputTokens: 200,
        costUsd: 0.12,
        startedAt: 100,
        finishedAt: 150
      )
    )
  }

  func testUpsertGunkEmbeddingPersistsVector() throws {
    let (store, _) = try makeStore(now: 100)
    let source = try store.insertSource(name: "source", path: "/code/source")
    let gunk = try store.insertGunk(sourceId: source.id, name: "auth-module")

    try store.upsertGunkEmbedding(
      gunkId: gunk.id,
      vector: [0.25, 0.5, 1],
      model: "test-embedding"
    )

    XCTAssertEqual(
      try store.gunkEmbedding(gunkId: gunk.id),
      GunkEmbedding(
        gunkId: gunk.id,
        vector: [0.25, 0.5, 1],
        dim: 3,
        model: "test-embedding"
      )
    )

    try store.upsertGunkEmbedding(
      gunkId: gunk.id,
      vector: [1, 0],
      model: "replacement"
    )

    XCTAssertEqual(
      try store.listGunkEmbeddings(),
      [
        GunkEmbedding(
          gunkId: gunk.id,
          vector: [1, 0],
          dim: 2,
          model: "replacement"
        )
      ]
    )
  }

  func testApproveGunkSetsApprovedAt() throws {
    let (store, queue) = try makeStore(now: 500)
    let source = try store.insertSource(name: "source", path: "/code/source")
    let gunk = try store.insertGunk(sourceId: source.id, name: "auth-module")

    try store.approveGunk(id: gunk.id)

    let approvedAt = try queue.read { db in
      try Int64.fetchOne(
        db,
        sql: "SELECT approved_at FROM gunks WHERE id = ?",
        arguments: [gunk.id]
      )
    }

    XCTAssertEqual(approvedAt, 500)
  }

  func testRemoveGunkSetsRemovedAt() throws {
    let (store, queue) = try makeStore(now: 500)
    let source = try store.insertSource(name: "source", path: "/code/source")
    let gunk = try store.insertGunk(sourceId: source.id, name: "auth-module")

    try store.removeGunk(id: gunk.id)

    let removedAt = try queue.read { db in
      try Int64.fetchOne(
        db,
        sql: "SELECT removed_at FROM gunks WHERE id = ?",
        arguments: [gunk.id]
      )
    }

    XCTAssertEqual(removedAt, 500)
    XCTAssertTrue(try store.listGunks().isEmpty)
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
        "mobile",
        "payments",
        "scraper",
        "search",
        "ui-kit"
      ]
    )
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
    XCTAssertEqual(
      Data(Schema.v2.utf8),
      try Data(contentsOf: schemaDirectory.appendingPathComponent("v2.sql"))
    )
    XCTAssertEqual(
      Data(Schema.v3.utf8),
      try Data(contentsOf: schemaDirectory.appendingPathComponent("v3.sql"))
    )
    XCTAssertEqual(
      Data(Schema.v4.utf8),
      try Data(contentsOf: schemaDirectory.appendingPathComponent("v4.sql"))
    )
  }

  func testV4StoreUpgradesToV5WithNullProvenance() throws {
    let queue = try DatabaseQueue()

    // Build a store at v4 (pre-attribution) with one module, then open it.
    try queue.write { db in
      var version = 0
      for migration in Schema.migrations where migration.version <= 4 {
        try db.execute(sql: migration.sql)
        try db.execute(
          sql: "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
          arguments: [migration.version, 100]
        )
        version = migration.version
      }
      XCTAssertEqual(version, 4)

      try db.execute(
        sql: "INSERT INTO sources (id, name, path, dropped_at) VALUES (?, ?, ?, ?)",
        arguments: [1, "legacy", "/code/legacy", 100]
      )
      try db.execute(
        sql: """
          INSERT INTO gunks (id, source_id, name, confidence, extracted_at)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [1, 1, "legacy-module", 0.9, 150]
      )
    }

    let store = try Store(databaseQueue: queue, now: { 200 })

    let versions = try queue.read { db in
      try Int.fetchAll(db, sql: "SELECT version FROM schema_version")
    }
    XCTAssertEqual(versions, [0, 1, 2, 3, 4, 5])

    // The old row opens cleanly with null attribution (it renders the neutral
    // mark) until backfill resolves it.
    let gunk = try XCTUnwrap(try store.gunk(id: 1))
    XCTAssertNil(gunk.provider)
    XCTAssertNil(gunk.model)
  }

  func testSetGunkProvenancePersists() throws {
    let (store, _) = try makeStore(now: 100)
    let source = try store.insertSource(name: "source", path: "/code/source")
    let gunk = try store.insertGunk(sourceId: source.id, name: "auth-module")
    XCTAssertNil(gunk.provider)

    try store.setGunkProvenance(gunkId: gunk.id, provider: "anthropic", model: "claude-sonnet-4")

    let stored = try XCTUnwrap(try store.gunk(id: gunk.id))
    XCTAssertEqual(stored.provider, "anthropic")
    XCTAssertEqual(stored.model, "claude-sonnet-4")
  }

  private func makeStore(now: Int64) throws -> (Store, DatabaseQueue) {
    let queue = try DatabaseQueue()
    return (try Store(databaseQueue: queue, now: { now }), queue)
  }

  private static func source(from row: Row) -> Source {
    Source(
      id: row["id"],
      name: row["name"],
      path: row["path"],
      droppedAt: row["dropped_at"],
      removedAt: row["removed_at"]
    )
  }
}
