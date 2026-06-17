import Foundation
import GRDB

final class Store {
  static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".gunk/store.db")

  private let databaseQueue: DatabaseQueue
  private let now: () -> Int64

  /// On-disk path of the SQLite file, or `nil` for in-memory stores. The
  /// `gunk-engine` subprocess needs this to write into the same database.
  let databasePath: String?

  init(
    path: URL,
    now: @escaping () -> Int64 = Store.currentTimeInMilliseconds
  ) throws {
    try FileManager.default.createDirectory(
      at: path.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    self.databaseQueue = try DatabaseQueue(
      path: path.path,
      configuration: Store.databaseConfiguration()
    )
    self.now = now
    self.databasePath = path.path

    try prepareDatabase()
  }

  init(
    databaseQueue: DatabaseQueue,
    now: @escaping () -> Int64 = Store.currentTimeInMilliseconds
  ) throws {
    self.databaseQueue = databaseQueue
    self.now = now
    self.databasePath = nil

    try prepareDatabase()
  }

  func insertSource(name: String, path: String) throws -> Source {
    let droppedAt = now()

    return try databaseQueue.write { db in
      if let existing = try Row.fetchOne(
        db,
        sql: """
          SELECT id, name, path, dropped_at, removed_at
          FROM sources
          WHERE path = ?
          """,
        arguments: [path]
      ) {
        let source = Store.source(from: existing)

        if (existing["removed_at"] as Int64?) != nil {
          try db.execute(
            sql: "UPDATE sources SET removed_at = NULL WHERE id = ?",
            arguments: [source.id]
          )

          return Source(
            id: source.id,
            name: source.name,
            path: source.path,
            droppedAt: source.droppedAt,
            removedAt: nil
          )
        }

        return source
      }

      try db.execute(
        sql: """
          INSERT INTO sources (name, path, dropped_at)
          VALUES (?, ?, ?)
          """,
        arguments: [name, path, droppedAt]
      )

      return Source(
        id: db.lastInsertedRowID,
        name: name,
        path: path,
        droppedAt: droppedAt,
        removedAt: nil
      )
    }
  }

  func listSources() throws -> [Source] {
    try databaseQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT id, name, path, dropped_at, removed_at
          FROM sources
          WHERE removed_at IS NULL
          ORDER BY dropped_at DESC
          """
      )

      return rows.map(Store.source(from:))
    }
  }

  func source(id: Int64) throws -> Source? {
    try databaseQueue.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT id, name, path, dropped_at, removed_at
          FROM sources
          WHERE id = ? AND removed_at IS NULL
          """,
        arguments: [id]
      )
      .map(Store.source(from:))
    }
  }

  func removeSource(id: Int64) throws {
    let removedAt = now()

    try databaseQueue.write { db in
      try db.execute(
        sql: """
          UPDATE sources
          SET removed_at = ?
          WHERE id = ? AND removed_at IS NULL
          """,
        arguments: [removedAt, id]
      )
    }
  }

  func insertGunk(
    sourceId: Int64,
    name: String,
    purpose: String? = nil,
    language: String? = nil,
    confidence: Double? = nil,
    bundlePath: String? = nil,
    manifestPath: String? = nil,
    extractedAt: Int64? = nil,
    approvedAt: Int64? = nil,
    provider: String? = nil,
    model: String? = nil
  ) throws -> Gunk {
    try databaseQueue.write { db in
      try db.execute(
        sql: """
          INSERT INTO gunks (
            source_id,
            name,
            purpose,
            language,
            confidence,
            bundle_path,
            manifest_path,
            extracted_at,
            approved_at,
            provider,
            model
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          sourceId,
          name,
          purpose,
          language,
          confidence,
          bundlePath,
          manifestPath,
          extractedAt,
          approvedAt,
          provider,
          model
        ]
      )

      return Gunk(
        id: db.lastInsertedRowID,
        sourceId: sourceId,
        name: name,
        purpose: purpose,
        language: language,
        confidence: confidence,
        bundlePath: bundlePath,
        manifestPath: manifestPath,
        extractedAt: extractedAt,
        approvedAt: approvedAt,
        removedAt: nil,
        provider: provider,
        model: model
      )
    }
  }

  /// Durable model attribution (T-9.2): record which provider/model created a
  /// set of modules. Called at extraction time (`SourceProcessingRunner`, once
  /// the engine reports its `gunkIds`) and by the one-time backfill. Writes are
  /// unconditional for the given ids — the most recent run is the attribution.
  func setGunkProvenance(gunkIds: [Int64], provider: String, model: String) throws {
    guard !gunkIds.isEmpty else {
      return
    }

    try databaseQueue.write { db in
      for id in gunkIds {
        try db.execute(
          sql: "UPDATE gunks SET provider = ?, model = ? WHERE id = ?",
          arguments: [provider, model, id]
        )
      }
    }
  }

  func setGunkProvenance(gunkId: Int64, provider: String, model: String) throws {
    try setGunkProvenance(gunkIds: [gunkId], provider: provider, model: model)
  }

  func listGunks() throws -> [Gunk] {
    try databaseQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT
            id,
            source_id,
            name,
            purpose,
            language,
            confidence,
            bundle_path,
            manifest_path,
            extracted_at,
            approved_at,
            removed_at,
            provider,
            model
          FROM gunks
          WHERE removed_at IS NULL
          ORDER BY id DESC
          """
      )

      return rows.map(Store.gunk(from:))
    }
  }

  func gunk(id: Int64) throws -> Gunk? {
    try databaseQueue.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT
            id,
            source_id,
            name,
            purpose,
            language,
            confidence,
            bundle_path,
            manifest_path,
            extracted_at,
            approved_at,
            removed_at,
            provider,
            model
          FROM gunks
          WHERE id = ? AND removed_at IS NULL
          """,
        arguments: [id]
      )
      .map(Store.gunk(from:))
    }
  }

  func gunksForSource(sourceId: Int64) throws -> [Gunk] {
    try databaseQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT
            id,
            source_id,
            name,
            purpose,
            language,
            confidence,
            bundle_path,
            manifest_path,
            extracted_at,
            approved_at,
            removed_at,
            provider,
            model
          FROM gunks
          WHERE source_id = ? AND removed_at IS NULL
          ORDER BY id DESC
          """,
        arguments: [sourceId]
      )

      return rows.map(Store.gunk(from:))
    }
  }

  func approveGunk(id: Int64) throws {
    let approvedAt = now()

    try databaseQueue.write { db in
      try db.execute(
        sql: """
          UPDATE gunks
          SET approved_at = ?
          WHERE id = ? AND removed_at IS NULL
          """,
        arguments: [approvedAt, id]
      )
    }
  }

  func removeGunk(id: Int64) throws {
    let removedAt = now()

    try databaseQueue.write { db in
      try db.execute(
        sql: """
          UPDATE gunks
          SET removed_at = ?
          WHERE id = ? AND removed_at IS NULL
          """,
        arguments: [removedAt, id]
      )
    }
  }

  func updateGunkExtraction(
    id: Int64,
    bundlePath: String,
    manifestPath: String,
    extractedAt: Int64
  ) throws {
    try databaseQueue.write { db in
      try db.execute(
        sql: """
          UPDATE gunks
          SET bundle_path = ?, manifest_path = ?, extracted_at = ?
          WHERE id = ? AND removed_at IS NULL
          """,
        arguments: [bundlePath, manifestPath, extractedAt, id]
      )
    }
  }

  @discardableResult
  func addTag(name: String) throws -> Tag {
    try databaseQueue.write { db in
      try db.execute(
        sql: "INSERT OR IGNORE INTO tags (name) VALUES (?)",
        arguments: [name]
      )

      let row = try Row.fetchOne(
        db,
        sql: "SELECT id, name FROM tags WHERE name = ?",
        arguments: [name]
      )!

      return Store.tag(from: row)
    }
  }

  func listTags() throws -> [Tag] {
    try databaseQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT id, name
          FROM tags
          ORDER BY name ASC
          """
      )

      return rows.map(Store.tag(from:))
    }
  }

  func addGunkTag(gunkId: Int64, tagId: Int64, confidence: Double?) throws {
    try databaseQueue.write { db in
      try db.execute(
        sql: """
          INSERT INTO gunk_tags (gunk_id, tag_id, confidence)
          VALUES (?, ?, ?)
          ON CONFLICT(gunk_id, tag_id) DO UPDATE
          SET confidence = excluded.confidence
          """,
        arguments: [gunkId, tagId, confidence]
      )
    }
  }

  func listGunkTags(gunkId: Int64) throws -> [GunkTag] {
    try databaseQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT
            gunk_tags.gunk_id,
            gunk_tags.tag_id,
            tags.name AS tag,
            gunk_tags.confidence
          FROM gunk_tags
          JOIN tags ON tags.id = gunk_tags.tag_id
          WHERE gunk_tags.gunk_id = ?
          ORDER BY gunk_tags.confidence DESC, tags.name ASC
          """,
        arguments: [gunkId]
      )

      return rows.map(Store.gunkTag(from:))
    }
  }

  @discardableResult
  func addGunkFile(gunkId: Int64, relpath: String, size: Int64?) throws -> GunkFile {
    try databaseQueue.write { db in
      try db.execute(
        sql: """
          INSERT INTO gunk_files (gunk_id, relpath, size)
          VALUES (?, ?, ?)
          """,
        arguments: [gunkId, relpath, size]
      )

      return GunkFile(
        id: db.lastInsertedRowID,
        gunkId: gunkId,
        relpath: relpath,
        size: size
      )
    }
  }

  func filesForGunk(gunkId: Int64) throws -> [GunkFile] {
    try databaseQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT id, gunk_id, relpath, size
          FROM gunk_files
          WHERE gunk_id = ?
          ORDER BY relpath ASC
          """,
        arguments: [gunkId]
      )

      return rows.map(Store.gunkFile(from:))
    }
  }

  @discardableResult
  func recordLLMRun(
    sourceId: Int64?,
    provider: String,
    model: String,
    inputTokens: Int64? = nil,
    outputTokens: Int64? = nil,
    costUsd: Double? = nil,
    startedAt: Int64? = nil,
    finishedAt: Int64? = nil
  ) throws -> LLMRun {
    let startedAt = startedAt ?? now()

    return try databaseQueue.write { db in
      try db.execute(
        sql: """
          INSERT INTO llm_runs (
            source_id,
            provider,
            model,
            input_tokens,
            output_tokens,
            started_at,
            finished_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          sourceId,
          provider,
          model,
          inputTokens,
          outputTokens,
          startedAt,
          finishedAt
        ]
      )

      return LLMRun(
        id: db.lastInsertedRowID,
        sourceId: sourceId,
        provider: provider,
        model: model,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        costUsd: nil,
        startedAt: startedAt,
        finishedAt: finishedAt
      )
    }
  }

  func listLLMRuns() throws -> [LLMRun] {
    try databaseQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT
            id,
            source_id,
            provider,
            model,
            input_tokens,
            output_tokens,
            started_at,
            finished_at
          FROM llm_runs
          ORDER BY started_at ASC, id ASC
          """
      )

      return rows.map(Store.llmRun(from:))
    }
  }

  func llmRunsForSource(_ sourceId: Int64) throws -> [LLMRun] {
    try databaseQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT
            id,
            source_id,
            provider,
            model,
            input_tokens,
            output_tokens,
            started_at,
            finished_at
          FROM llm_runs
          WHERE source_id = ?
          ORDER BY started_at ASC, id ASC
          """,
        arguments: [sourceId]
      )

      return rows.map(Store.llmRun(from:))
    }
  }

  func llmRunAggregatesByModel() throws -> [LLMRunAggregate] {
    try databaseQueue.read { db in
      try Store.llmRunAggregatesByModel(db)
    }
  }

  func llmRunAggregatesByModel(sourceId: Int64) throws -> [LLMRunAggregate] {
    try databaseQueue.read { db in
      try Store.llmRunAggregatesByModel(db, sourceId: sourceId)
    }
  }

  @discardableResult
  func upsertGunkEmbedding(gunkId: Int64, vector: [Double], model: String) throws -> GunkEmbedding {
    let dim = vector.count
    let data = Store.encodeEmbeddingVector(vector)

    return try databaseQueue.write { db in
      try db.execute(
        sql: """
          INSERT INTO gunk_embeddings (gunk_id, vector, dim, model)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(gunk_id) DO UPDATE
          SET vector = excluded.vector,
              dim = excluded.dim,
              model = excluded.model
          """,
        arguments: [gunkId, data, dim, model]
      )

      return GunkEmbedding(
        gunkId: gunkId,
        vector: vector,
        dim: dim,
        model: model
      )
    }
  }

  func gunkEmbedding(gunkId: Int64) throws -> GunkEmbedding? {
    try databaseQueue.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT gunk_id, vector, dim, model
          FROM gunk_embeddings
          WHERE gunk_id = ?
          """,
        arguments: [gunkId]
      )
      .map(Store.gunkEmbedding(from:))
    }
  }

  func listGunkEmbeddings() throws -> [GunkEmbedding] {
    try databaseQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT gunk_id, vector, dim, model
          FROM gunk_embeddings
          ORDER BY gunk_id ASC
          """
      )

      return rows.map(Store.gunkEmbedding(from:))
    }
  }

  // MARK: - Smoke-run receipts & examples (T-10.3, v6)

  /// Insert a smoke-run receipt. Persistence the runner deliberately does not
  /// do (T-10.2 returns a value); the console (T-10.7) and the MCP tool
  /// (T-10.12) call this to make the proof durable.
  @discardableResult
  func insertSmokeRun(
    gunkId: Int64,
    exampleId: Int64? = nil,
    command: String?,
    runnability: Runnability,
    origin: RunOrigin,
    exitCode: Int32? = nil,
    passed: Bool? = nil,
    timedOut: Bool = false,
    durationMs: Int = 0,
    outputArtifactPath: String? = nil,
    log: String = "",
    verdict: RunVerdict? = nil
  ) throws -> SmokeRunRecord {
    let createdAt = now()

    return try databaseQueue.write { db in
      try db.execute(
        sql: """
          INSERT INTO smoke_runs (
            gunk_id,
            example_id,
            command,
            runnability,
            origin,
            exit_code,
            passed,
            timed_out,
            duration_ms,
            output_artifact_path,
            log,
            verdict,
            created_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          gunkId,
          exampleId,
          command,
          runnability.rawValue,
          origin.rawValue,
          exitCode,
          passed,
          timedOut,
          durationMs,
          outputArtifactPath,
          log,
          verdict?.rawValue,
          createdAt
        ]
      )

      return SmokeRunRecord(
        id: db.lastInsertedRowID,
        gunkId: gunkId,
        exampleId: exampleId,
        command: command,
        runnability: runnability,
        origin: origin,
        exitCode: exitCode,
        passed: passed,
        timedOut: timedOut,
        durationMs: durationMs,
        outputArtifactPath: outputArtifactPath,
        log: log,
        verdict: verdict,
        createdAt: createdAt
      )
    }
  }

  /// Convenience over `insertSmokeRun` that maps a runner result into a
  /// receipt. `passed` is recorded only when the module was actually executed
  /// (a `.terminalRunnable` class) — a not-runnable-here refusal stores `nil`,
  /// not a fabricated failure.
  @discardableResult
  func recordSmokeRun(
    gunkId: Int64,
    exampleId: Int64? = nil,
    result: SmokeRunResult,
    verdict: RunVerdict? = nil
  ) throws -> SmokeRunRecord {
    let executed = result.runnability == .terminalRunnable
    let log = [result.stdout, result.stderr]
      .filter { !$0.isEmpty }
      .joined(separator: "\n")

    return try insertSmokeRun(
      gunkId: gunkId,
      exampleId: exampleId,
      command: result.command,
      runnability: result.runnability,
      origin: result.origin,
      exitCode: result.exitCode,
      passed: executed ? result.passed : nil,
      timedOut: result.timedOut,
      durationMs: result.durationMs,
      outputArtifactPath: result.outputArtifacts.first?.path,
      log: log,
      verdict: verdict
    )
  }

  func mostRecentSmokeRun(gunkId: Int64) throws -> SmokeRunRecord? {
    try databaseQueue.read { db in
      try Row.fetchOne(
        db,
        sql: """
          \(Store.smokeRunColumns)
          FROM smoke_runs
          WHERE gunk_id = ?
          ORDER BY created_at DESC, id DESC
          LIMIT 1
          """,
        arguments: [gunkId]
      )
      .map(Store.smokeRun(from:))
    }
  }

  /// A module's receipt history, newest first and **capped** — these are
  /// receipts, not a history table feeding a chart (explicitly out of scope).
  func smokeRuns(gunkId: Int64, limit: Int = 50) throws -> [SmokeRunRecord] {
    try databaseQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          \(Store.smokeRunColumns)
          FROM smoke_runs
          WHERE gunk_id = ?
          ORDER BY created_at DESC, id DESC
          LIMIT ?
          """,
        arguments: [gunkId, limit]
      )

      return rows.map(Store.smokeRun(from:))
    }
  }

  /// Attach the developer's `right`/`wrong` verdict to a run after they judge
  /// its output.
  func attachVerdict(smokeRunId: Int64, verdict: RunVerdict) throws {
    try databaseQueue.write { db in
      try db.execute(
        sql: "UPDATE smoke_runs SET verdict = ? WHERE id = ?",
        arguments: [verdict.rawValue, smokeRunId]
      )
    }
  }

  /// Insert a saved example / pinned case. Marking it golden is exclusive per
  /// `(gunkId, inputClass)`.
  @discardableResult
  func insertExample(
    gunkId: Int64,
    name: String,
    input: String,
    inputClass: ExampleInputClass,
    isGolden: Bool = false,
    verdict: RunVerdict? = nil,
    expectedOutput: String? = nil,
    note: String? = nil
  ) throws -> ModuleExample {
    let createdAt = now()

    return try databaseQueue.write { db in
      try db.execute(
        sql: """
          INSERT INTO module_examples (
            gunk_id,
            name,
            input,
            input_class,
            is_golden,
            verdict,
            expected_output,
            note,
            created_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          gunkId,
          name,
          input,
          inputClass.rawValue,
          isGolden,
          verdict?.rawValue,
          expectedOutput,
          note,
          createdAt
        ]
      )

      let id = db.lastInsertedRowID

      if isGolden {
        try Store.enforceGoldenExclusivity(
          db,
          id: id,
          gunkId: gunkId,
          inputClass: inputClass
        )
      }

      return ModuleExample(
        id: id,
        gunkId: gunkId,
        name: name,
        input: input,
        inputClass: inputClass,
        isGolden: isGolden,
        verdict: verdict,
        expectedOutput: expectedOutput,
        note: note,
        createdAt: createdAt
      )
    }
  }

  func listExamples(gunkId: Int64) throws -> [ModuleExample] {
    try databaseQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          \(Store.moduleExampleColumns)
          FROM module_examples
          WHERE gunk_id = ?
          ORDER BY created_at ASC, id ASC
          """,
        arguments: [gunkId]
      )

      return rows.map(Store.moduleExample(from:))
    }
  }

  /// Mark one example as the golden of its class, clearing any sibling golden
  /// in the same `(gunkId, inputClass)` in a single statement.
  func markExampleGolden(id: Int64) throws {
    try databaseQueue.write { db in
      guard
        let row = try Row.fetchOne(
          db,
          sql: "SELECT gunk_id, input_class FROM module_examples WHERE id = ?",
          arguments: [id]
        )
      else {
        return
      }

      let gunkId: Int64 = row["gunk_id"]
      let inputClass: String = row["input_class"]

      try db.execute(
        sql: """
          UPDATE module_examples
          SET is_golden = (id = ?)
          WHERE gunk_id = ? AND input_class = ?
          """,
        arguments: [id, gunkId, inputClass]
      )
    }
  }

  private static func enforceGoldenExclusivity(
    _ db: Database,
    id: Int64,
    gunkId: Int64,
    inputClass: ExampleInputClass
  ) throws {
    try db.execute(
      sql: """
        UPDATE module_examples
        SET is_golden = (id = ?)
        WHERE gunk_id = ? AND input_class = ?
        """,
      arguments: [id, gunkId, inputClass.rawValue]
    )
  }

  // MARK: - "How this works" analysis cache (T-10.14, v7)

  /// Read the cached analysis for a module, or `nil` when none was generated
  /// yet (older/just-extracted modules). The view reads this synchronously, so
  /// opening the disclosure never blocks on a model call.
  func moduleAnalysis(gunkId: Int64) throws -> ModuleAnalysis? {
    try databaseQueue.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT gunk_id, content, model, generated_at
          FROM module_analyses
          WHERE gunk_id = ?
          """,
        arguments: [gunkId]
      )
      .flatMap(Store.moduleAnalysis(from:))
    }
  }

  /// All cached analyses, keyed by module — the bulk read the model loads once
  /// per refresh so `analysis(for:)` is a pure dictionary lookup.
  func listModuleAnalyses() throws -> [Int64: ModuleAnalysis] {
    try databaseQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: "SELECT gunk_id, content, model, generated_at FROM module_analyses"
      )

      return rows.reduce(into: [:]) { result, row in
        if let analysis = Store.moduleAnalysis(from: row) {
          result[row["gunk_id"] as Int64] = analysis
        }
      }
    }
  }

  /// Cache (or replace) a module's analysis. Keyed by `gunk_id`, so generating
  /// again upserts in place — one analysis per module.
  @discardableResult
  func upsertModuleAnalysis(
    gunkId: Int64,
    content: ModuleAnalysisContent,
    model: String?
  ) throws -> ModuleAnalysis {
    let generatedAt = now()
    let encoded = String(decoding: try JSONEncoder().encode(content), as: UTF8.self)

    try databaseQueue.write { db in
      try db.execute(
        sql: """
          INSERT INTO module_analyses (gunk_id, content, model, generated_at)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(gunk_id) DO UPDATE
          SET content = excluded.content,
              model = excluded.model,
              generated_at = excluded.generated_at
          """,
        arguments: [gunkId, encoded, model, generatedAt]
      )
    }

    return ModuleAnalysis(content: content, model: model, generatedAt: generatedAt)
  }

  private static func moduleAnalysis(from row: Row) -> ModuleAnalysis? {
    let raw: String = row["content"]
    guard let data = raw.data(using: .utf8),
          let content = try? JSONDecoder().decode(ModuleAnalysisContent.self, from: data)
    else {
      return nil
    }

    return ModuleAnalysis(
      content: content,
      model: row["model"],
      generatedAt: row["generated_at"]
    )
  }

  private static let smokeRunColumns = """
    SELECT
      id,
      gunk_id,
      example_id,
      command,
      runnability,
      origin,
      exit_code,
      passed,
      timed_out,
      duration_ms,
      output_artifact_path,
      log,
      verdict,
      created_at
    """

  private static let moduleExampleColumns = """
    SELECT
      id,
      gunk_id,
      name,
      input,
      input_class,
      is_golden,
      verdict,
      expected_output,
      note,
      created_at
    """

  private func prepareDatabase() throws {
    try databaseQueue.writeWithoutTransaction { db in
      try db.execute(sql: "PRAGMA journal_mode = WAL")
      try db.execute(sql: "PRAGMA foreign_keys = ON")
    }

    try runMigrations()
  }

  private func runMigrations() throws {
    try databaseQueue.write { db in
      let currentVersion: Int

      if try db.tableExists("schema_version") {
        currentVersion =
          try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_version") ?? -1
      } else {
        currentVersion = -1
      }

      for migration in Schema.migrations where migration.version > currentVersion {
        try db.execute(sql: migration.sql)
        try db.execute(
          sql: "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
          arguments: [migration.version, now()]
        )
      }
    }
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

  private static func gunk(from row: Row) -> Gunk {
    Gunk(
      id: row["id"],
      sourceId: row["source_id"],
      name: row["name"],
      purpose: row["purpose"],
      language: row["language"],
      confidence: row["confidence"],
      bundlePath: row["bundle_path"],
      manifestPath: row["manifest_path"],
      extractedAt: row["extracted_at"],
      approvedAt: row["approved_at"],
      removedAt: row["removed_at"],
      provider: row["provider"],
      model: row["model"]
    )
  }

  private static func tag(from row: Row) -> Tag {
    Tag(
      id: row["id"],
      name: row["name"]
    )
  }

  private static func gunkTag(from row: Row) -> GunkTag {
    GunkTag(
      gunkId: row["gunk_id"],
      tagId: row["tag_id"],
      tag: row["tag"],
      confidence: row["confidence"]
    )
  }

  private static func gunkFile(from row: Row) -> GunkFile {
    GunkFile(
      id: row["id"],
      gunkId: row["gunk_id"],
      relpath: row["relpath"],
      size: row["size"]
    )
  }

  private static func llmRun(from row: Row) -> LLMRun {
    LLMRun(
      id: row["id"],
      sourceId: row["source_id"],
      provider: row["provider"],
      model: row["model"],
      inputTokens: row["input_tokens"],
      outputTokens: row["output_tokens"],
      costUsd: nil,
      startedAt: row["started_at"],
      finishedAt: row["finished_at"]
    )
  }

  private static func llmRunAggregate(from row: Row) -> LLMRunAggregate {
    LLMRunAggregate(
      provider: row["provider"],
      model: row["model"],
      inputTokens: row["input_tokens"],
      outputTokens: row["output_tokens"],
      runCount: row["run_count"],
      hasUnknownTokens: row["has_unknown_tokens"]
    )
  }

  private static func llmRunAggregatesByModel(
    _ db: Database,
    sourceId: Int64? = nil
  ) throws -> [LLMRunAggregate] {
    let whereClause = sourceId == nil ? "" : "WHERE source_id = ?"
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT
          provider,
          model,
          SUM(COALESCE(input_tokens, 0)) AS input_tokens,
          SUM(COALESCE(output_tokens, 0)) AS output_tokens,
          COUNT(id) AS run_count,
          CASE
            WHEN SUM(
              CASE
                WHEN input_tokens IS NULL OR output_tokens IS NULL THEN 1
                ELSE 0
              END
            ) > 0 THEN 1
            ELSE 0
          END AS has_unknown_tokens
        FROM llm_runs
        \(whereClause)
        GROUP BY provider, model
        ORDER BY provider ASC, model ASC
        """,
      arguments: sourceId.map { [$0] } ?? []
    )

    return rows.map(Store.llmRunAggregate(from:))
  }

  private static func smokeRun(from row: Row) -> SmokeRunRecord {
    SmokeRunRecord(
      id: row["id"],
      gunkId: row["gunk_id"],
      exampleId: row["example_id"],
      command: row["command"],
      runnability: Runnability(rawValue: row["runnability"]) ?? .cannotDetermine,
      origin: RunOrigin(rawValue: row["origin"]) ?? .human,
      exitCode: row["exit_code"],
      passed: row["passed"],
      timedOut: row["timed_out"],
      durationMs: row["duration_ms"],
      outputArtifactPath: row["output_artifact_path"],
      log: row["log"],
      verdict: (row["verdict"] as String?).flatMap(RunVerdict.init(rawValue:)),
      createdAt: row["created_at"]
    )
  }

  private static func moduleExample(from row: Row) -> ModuleExample {
    ModuleExample(
      id: row["id"],
      gunkId: row["gunk_id"],
      name: row["name"],
      input: row["input"],
      inputClass: ExampleInputClass(rawValue: row["input_class"]) ?? .happy,
      isGolden: row["is_golden"],
      verdict: (row["verdict"] as String?).flatMap(RunVerdict.init(rawValue:)),
      expectedOutput: row["expected_output"],
      note: row["note"],
      createdAt: row["created_at"]
    )
  }

  private static func gunkEmbedding(from row: Row) -> GunkEmbedding {
    let dim: Int = row["dim"]
    let data: Data = row["vector"]

    return GunkEmbedding(
      gunkId: row["gunk_id"],
      vector: decodeEmbeddingVector(data, dim: dim),
      dim: dim,
      model: row["model"]
    )
  }

  private static func encodeEmbeddingVector(_ vector: [Double]) -> Data {
    var data = Data()
    data.reserveCapacity(vector.count * MemoryLayout<UInt32>.size)

    for component in vector {
      let value = component.isFinite ? Float32(component) : 0
      var bits = value.bitPattern.littleEndian
      withUnsafeBytes(of: &bits) { bytes in
        data.append(contentsOf: bytes)
      }
    }

    return data
  }

  private static func decodeEmbeddingVector(_ data: Data, dim: Int) -> [Double] {
    let bytes = [UInt8](data)
    guard dim > 0, bytes.count >= dim * MemoryLayout<UInt32>.size else {
      return []
    }

    return (0..<dim).map { index in
      let offset = index * MemoryLayout<UInt32>.size
      let bits = UInt32(bytes[offset])
        | UInt32(bytes[offset + 1]) << 8
        | UInt32(bytes[offset + 2]) << 16
        | UInt32(bytes[offset + 3]) << 24

      return Double(Float32(bitPattern: bits))
    }
  }

  private static func databaseConfiguration() -> Configuration {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    return configuration
  }

  static func currentTimeInMilliseconds() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }
}
