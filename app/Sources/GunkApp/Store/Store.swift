import Foundation
import GRDB

final class Store {
  static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".gunk/store.db")

  private let databaseQueue: DatabaseQueue
  private let now: () -> Int64

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

    try prepareDatabase()
  }

  init(
    databaseQueue: DatabaseQueue,
    now: @escaping () -> Int64 = Store.currentTimeInMilliseconds
  ) throws {
    self.databaseQueue = databaseQueue
    self.now = now

    try prepareDatabase()
  }

  func insertGunk(name: String, path: String) throws -> Gunk {
    let droppedAt = now()

    return try databaseQueue.write { db in
      try db.execute(
        sql: """
          INSERT INTO gunks (name, path, dropped_at)
          VALUES (?, ?, ?)
          """,
        arguments: [name, path, droppedAt]
      )

      return Gunk(
        id: db.lastInsertedRowID,
        name: name,
        path: path,
        droppedAt: droppedAt,
        removedAt: nil
      )
    }
  }

  func listGunks() throws -> [Gunk] {
    try databaseQueue.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT id, name, path, dropped_at, removed_at
          FROM gunks
          WHERE removed_at IS NULL
          ORDER BY dropped_at DESC
          """
      )

      return rows.map(Store.gunk(from:))
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

      guard currentVersion < Schema.version else {
        return
      }

      try db.execute(sql: Schema.v0)
      try db.execute(
        sql: "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
        arguments: [Schema.version, now()]
      )
    }
  }

  private static func gunk(from row: Row) -> Gunk {
    Gunk(
      id: row["id"],
      name: row["name"],
      path: row["path"],
      droppedAt: row["dropped_at"],
      removedAt: row["removed_at"]
    )
  }

  private static func databaseConfiguration() -> Configuration {
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    return configuration
  }

  private static func currentTimeInMilliseconds() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }
}
