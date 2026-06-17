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

  func testMigrationsAreIdempotentThroughV7() throws {
    let queue = try DatabaseQueue()

    _ = try Store(databaseQueue: queue, now: { 100 })
    _ = try Store(databaseQueue: queue, now: { 200 })

    let versions = try queue.read { db in
      try Int.fetchAll(db, sql: "SELECT version FROM schema_version")
    }

    XCTAssertEqual(versions, [0, 1, 2, 3, 4, 5, 6, 7])
  }

  func testV0ToLatestUpgradePreservesSources() throws {
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

    XCTAssertEqual(versions, [0, 1, 2, 3, 4, 5, 6, 7])
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
    XCTAssertEqual(versions, [0, 1, 2, 3, 4, 5, 6, 7])

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

  // MARK: - T-10.3 (v6): smoke-run receipts & examples

  func testV5StoreUpgradesToV6WithEmptyProofTables() throws {
    let queue = try DatabaseQueue()

    // Build a store at v5 (pre-proof-loop) with one module, then open it.
    try queue.write { db in
      for migration in Schema.migrations where migration.version <= 5 {
        try db.execute(sql: migration.sql)
        try db.execute(
          sql: "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
          arguments: [migration.version, 100]
        )
      }

      try db.execute(
        sql: "INSERT INTO sources (id, name, path, dropped_at) VALUES (?, ?, ?, ?)",
        arguments: [1, "legacy", "/code/legacy", 100]
      )
      try db.execute(
        sql: "INSERT INTO gunks (id, source_id, name) VALUES (?, ?, ?)",
        arguments: [1, 1, "legacy-module"]
      )
    }

    let store = try Store(databaseQueue: queue, now: { 200 })

    let versions = try queue.read { db in
      try Int.fetchAll(db, sql: "SELECT version FROM schema_version")
    }
    XCTAssertEqual(versions, [0, 1, 2, 3, 4, 5, 6, 7])

    // The new tables exist and start empty on an upgraded store.
    XCTAssertEqual(try store.smokeRuns(gunkId: 1), [])
    XCTAssertEqual(try store.listExamples(gunkId: 1), [])
    XCTAssertNil(try store.mostRecentSmokeRun(gunkId: 1))
  }

  // MARK: - T-10.14 (v7): "How this works" analysis cache

  func testV6StoreUpgradesToV7WithEmptyAnalyses() throws {
    let queue = try DatabaseQueue()

    // Build a store at v6 (pre-analysis) with one module, then open it.
    try queue.write { db in
      for migration in Schema.migrations where migration.version <= 6 {
        try db.execute(sql: migration.sql)
        try db.execute(
          sql: "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
          arguments: [migration.version, 100]
        )
      }

      try db.execute(
        sql: "INSERT INTO sources (id, name, path, dropped_at) VALUES (?, ?, ?, ?)",
        arguments: [1, "legacy", "/code/legacy", 100]
      )
      try db.execute(
        sql: "INSERT INTO gunks (id, source_id, name) VALUES (?, ?, ?)",
        arguments: [1, 1, "legacy-module"]
      )
    }

    let store = try Store(databaseQueue: queue, now: { 200 })

    let versions = try queue.read { db in
      try Int.fetchAll(db, sql: "SELECT version FROM schema_version")
    }
    XCTAssertEqual(versions, [0, 1, 2, 3, 4, 5, 6, 7])

    // The cache exists and starts empty on an upgraded store.
    XCTAssertNil(try store.moduleAnalysis(gunkId: 1))
    XCTAssertEqual(try store.listModuleAnalyses().count, 0)
  }

  func testUpsertModuleAnalysisPersistsAndReadsBack() throws {
    let (store, _) = try makeStore(now: 555)
    let source = try store.insertSource(name: "source", path: "/code/source")
    let gunk = try store.insertGunk(sourceId: source.id, name: "module")

    let content = ModuleAnalysisContent(
      summary: "Slugifies a string.",
      dataFlow: ["Reads text.", "Lowercases and hyphenates."],
      keyFunctions: [AnalysisFunction(name: "slugify(_:)", role: "The entrypoint.")],
      touches: ["No I/O."],
      limits: ["ASCII only."]
    )

    let stored = try store.upsertModuleAnalysis(gunkId: gunk.id, content: content, model: "gpt-4.1-mini")
    XCTAssertEqual(stored.content, content)
    XCTAssertEqual(stored.model, "gpt-4.1-mini")
    XCTAssertEqual(stored.generatedAt, 555)

    let read = try XCTUnwrap(try store.moduleAnalysis(gunkId: gunk.id))
    XCTAssertEqual(read, stored)

    let all = try store.listModuleAnalyses()
    XCTAssertEqual(all[gunk.id], stored)
  }

  func testUpsertModuleAnalysisReplacesInPlace() throws {
    let (store, _) = try makeStore(now: 100)
    let source = try store.insertSource(name: "source", path: "/code/source")
    let gunk = try store.insertGunk(sourceId: source.id, name: "module")

    let first = ModuleAnalysisContent(
      summary: "First.", dataFlow: [], keyFunctions: [], touches: [], limits: []
    )
    let second = ModuleAnalysisContent(
      summary: "Second.", dataFlow: ["Step."], keyFunctions: [], touches: [], limits: []
    )

    try store.upsertModuleAnalysis(gunkId: gunk.id, content: first, model: "a")
    try store.upsertModuleAnalysis(gunkId: gunk.id, content: second, model: "b")

    let read = try XCTUnwrap(try store.moduleAnalysis(gunkId: gunk.id))
    XCTAssertEqual(read.content, second)
    XCTAssertEqual(read.model, "b")
    XCTAssertEqual(try store.listModuleAnalyses().count, 1)
  }

  func testInsertSmokeRunRoundTrips() throws {
    let (store, gunk) = try makeStoreWithGunk(now: 100)

    let run = try store.insertSmokeRun(
      gunkId: gunk.id,
      command: "python parser.py:parse_epub",
      runnability: .terminalRunnable,
      origin: .human,
      exitCode: 0,
      passed: true,
      durationMs: 412,
      outputArtifactPath: "/tmp/run/out.json",
      log: "parsed 12 chapters"
    )

    XCTAssertEqual(try store.mostRecentSmokeRun(gunkId: gunk.id), run)
    XCTAssertEqual(
      run,
      SmokeRunRecord(
        id: run.id,
        gunkId: gunk.id,
        exampleId: nil,
        command: "python parser.py:parse_epub",
        runnability: .terminalRunnable,
        origin: .human,
        exitCode: 0,
        passed: true,
        timedOut: false,
        durationMs: 412,
        outputArtifactPath: "/tmp/run/out.json",
        log: "parsed 12 chapters",
        verdict: nil,
        createdAt: 100
      )
    )
  }

  func testRecordSmokeRunFromResultStoresNilPassedWhenNotExecuted() throws {
    let (store, gunk) = try makeStoreWithGunk(now: 100)

    let notRun = SmokeRunResult(
      runnability: .needsNetwork,
      command: nil,
      exitCode: nil,
      stdout: "",
      stderr: "",
      durationMs: 0,
      timedOut: false,
      outputArtifacts: [],
      startedAt: Date(timeIntervalSince1970: 0),
      isolation: .notRun,
      origin: .agent
    )

    let receipt = try store.recordSmokeRun(gunkId: gunk.id, result: notRun)

    XCTAssertEqual(receipt.runnability, .needsNetwork)
    XCTAssertEqual(receipt.origin, .agent)
    XCTAssertNil(receipt.passed)
  }

  func testRecordSmokeRunFromResultJoinsOutputAndExecutedPass() throws {
    let (store, gunk) = try makeStoreWithGunk(now: 100)

    let ran = SmokeRunResult(
      runnability: .terminalRunnable,
      command: "node index.js",
      exitCode: 0,
      stdout: "hello",
      stderr: "warn: deprecated",
      durationMs: 90,
      timedOut: false,
      outputArtifacts: [URL(fileURLWithPath: "/tmp/run/a.txt")],
      startedAt: Date(timeIntervalSince1970: 0),
      isolation: .sandboxExec,
      origin: .human
    )

    let receipt = try store.recordSmokeRun(gunkId: gunk.id, result: ran)

    XCTAssertEqual(receipt.passed, true)
    XCTAssertEqual(receipt.log, "hello\nwarn: deprecated")
    XCTAssertEqual(receipt.outputArtifactPath, "/tmp/run/a.txt")
  }

  func testSmokeRunsReturnNewestFirstAndRespectLimit() throws {
    var timestamp: Int64 = 100
    let queue = try DatabaseQueue()
    let store = try Store(databaseQueue: queue) {
      defer { timestamp += 100 }
      return timestamp
    }
    let source = try store.insertSource(name: "source", path: "/code/source")
    let gunk = try store.insertGunk(sourceId: source.id, name: "mod")

    for index in 0..<3 {
      _ = try store.insertSmokeRun(
        gunkId: gunk.id,
        command: "run \(index)",
        runnability: .terminalRunnable,
        origin: .human
      )
    }

    XCTAssertEqual(
      try store.smokeRuns(gunkId: gunk.id).map(\.command),
      ["run 2", "run 1", "run 0"]
    )
    XCTAssertEqual(
      try store.smokeRuns(gunkId: gunk.id, limit: 2).map(\.command),
      ["run 2", "run 1"]
    )
  }

  func testAttachVerdictToRun() throws {
    let (store, gunk) = try makeStoreWithGunk(now: 100)
    let run = try store.insertSmokeRun(
      gunkId: gunk.id,
      command: "python main.py",
      runnability: .terminalRunnable,
      origin: .human,
      exitCode: 0,
      passed: true
    )
    XCTAssertNil(run.verdict)

    try store.attachVerdict(smokeRunId: run.id, verdict: .right)

    XCTAssertEqual(try store.mostRecentSmokeRun(gunkId: gunk.id)?.verdict, .right)
  }

  func testInsertExampleRoundTrips() throws {
    let (store, gunk) = try makeStoreWithGunk(now: 100)

    let example = try store.insertExample(
      gunkId: gunk.id,
      name: "Footnote-heavy EPUB",
      input: "--in footnotes.epub",
      inputClass: .yours,
      verdict: .right
    )

    XCTAssertEqual(
      try store.listExamples(gunkId: gunk.id),
      [
        ModuleExample(
          id: example.id,
          gunkId: gunk.id,
          name: "Footnote-heavy EPUB",
          input: "--in footnotes.epub",
          inputClass: .yours,
          isGolden: false,
          verdict: .right,
          expectedOutput: nil,
          note: nil,
          createdAt: 100
        )
      ]
    )
  }

  func testPinnedFailingCaseStoresExpectedOutputAndNote() throws {
    let (store, gunk) = try makeStoreWithGunk(now: 100)

    let failing = try store.insertExample(
      gunkId: gunk.id,
      name: "Empty file",
      input: "--in empty.epub",
      inputClass: .adversarial,
      verdict: .wrong,
      expectedOutput: "{\"chapters\": []}",
      note: "crashed instead of returning an empty result"
    )

    let stored = try XCTUnwrap(try store.listExamples(gunkId: gunk.id).first)
    XCTAssertEqual(stored, failing)
    XCTAssertEqual(stored.verdict, .wrong)
    XCTAssertEqual(stored.expectedOutput, "{\"chapters\": []}")
    XCTAssertEqual(stored.note, "crashed instead of returning an empty result")
  }

  func testGoldenIsExclusivePerInputClass() throws {
    let (store, gunk) = try makeStoreWithGunk(now: 100)

    let firstHappy = try store.insertExample(
      gunkId: gunk.id,
      name: "demo-a",
      input: "a",
      inputClass: .happy,
      isGolden: true
    )
    let yours = try store.insertExample(
      gunkId: gunk.id,
      name: "mine",
      input: "b",
      inputClass: .yours,
      isGolden: true
    )

    // A second golden in the *same* class displaces the first.
    let secondHappy = try store.insertExample(
      gunkId: gunk.id,
      name: "demo-b",
      input: "c",
      inputClass: .happy,
      isGolden: true
    )

    let golden = try store.listExamples(gunkId: gunk.id)
      .filter(\.isGolden)
      .map(\.id)

    // One golden per class: the newest happy + the lone yours; the first
    // happy was displaced.
    XCTAssertEqual(Set(golden), [secondHappy.id, yours.id])
    XCTAssertFalse(golden.contains(firstHappy.id))
  }

  func testMarkExampleGoldenClearsClassSiblings() throws {
    let (store, gunk) = try makeStoreWithGunk(now: 100)
    let a = try store.insertExample(
      gunkId: gunk.id, name: "a", input: "a", inputClass: .edge, isGolden: true
    )
    let b = try store.insertExample(
      gunkId: gunk.id, name: "b", input: "b", inputClass: .edge
    )

    try store.markExampleGolden(id: b.id)

    let goldenIds = try store.listExamples(gunkId: gunk.id)
      .filter(\.isGolden)
      .map(\.id)
    XCTAssertEqual(goldenIds, [b.id])
    XCTAssertFalse(goldenIds.contains(a.id))
  }

  func testDeletingExampleNullsRunInputRef() throws {
    let (store, queue) = try makeStore(now: 100)
    let source = try store.insertSource(name: "source", path: "/code/source")
    let gunk = try store.insertGunk(sourceId: source.id, name: "module")
    let example = try store.insertExample(
      gunkId: gunk.id, name: "case", input: "x", inputClass: .yours
    )
    let run = try store.insertSmokeRun(
      gunkId: gunk.id,
      exampleId: example.id,
      command: "run",
      runnability: .terminalRunnable,
      origin: .human
    )
    XCTAssertEqual(run.exampleId, example.id)

    // Deleting an example must not erase its receipts — the FK is
    // ON DELETE SET NULL, so the run survives with a null input ref.
    try queue.write { db in
      try db.execute(
        sql: "DELETE FROM module_examples WHERE id = ?",
        arguments: [example.id]
      )
    }

    XCTAssertNil(try store.mostRecentSmokeRun(gunkId: gunk.id)?.exampleId)
  }

  private func makeStoreWithGunk(now: Int64) throws -> (Store, Gunk) {
    let (store, _) = try makeStore(now: now)
    let source = try store.insertSource(name: "source", path: "/code/source")
    let gunk = try store.insertGunk(sourceId: source.id, name: "module")
    return (store, gunk)
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
