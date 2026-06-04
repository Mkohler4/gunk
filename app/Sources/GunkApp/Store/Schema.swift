enum Schema {
  static let version = 0

  // Keep byte-for-byte identical to mcp/src/schema/v0.sql. See ADR-0006.
  static let v0 = """
CREATE TABLE schema_version (
  version INTEGER PRIMARY KEY,
  applied_at INTEGER NOT NULL
);

CREATE TABLE gunks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  path TEXT NOT NULL UNIQUE,
  dropped_at INTEGER NOT NULL,
  removed_at INTEGER
);

CREATE TABLE files (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  gunk_id INTEGER NOT NULL REFERENCES gunks(id) ON DELETE CASCADE,
  relpath TEXT NOT NULL,
  size INTEGER,
  UNIQUE(gunk_id, relpath)
);
""" + "\n"
}
