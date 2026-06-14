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
            cost_usd,
            started_at,
            finished_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          sourceId,
          provider,
          model,
          inputTokens,
          outputTokens,
          costUsd,
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
        costUsd: costUsd,
        startedAt: startedAt,
        finishedAt: finishedAt
      )
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
