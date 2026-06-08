enum Schema {
  static let version = 4

  static let migrations = [
    (version: 0, sql: v0),
    (version: 1, sql: v1),
    (version: 2, sql: v2),
    (version: 3, sql: v3),
    (version: 4, sql: v4)
  ]

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

  // Keep byte-for-byte identical to mcp/src/schema/v1.sql. See ADR-0007.
  static let v1 = """
CREATE TABLE tags (
  name TEXT PRIMARY KEY,
  description TEXT NOT NULL
);

CREATE TABLE gunk_tags (
  gunk_id INTEGER NOT NULL REFERENCES gunks(id) ON DELETE CASCADE,
  tag TEXT NOT NULL REFERENCES tags(name) ON DELETE RESTRICT,
  confidence REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
  source TEXT NOT NULL CHECK (source IN ('llm', 'manual', 'heuristic')),
  tagged_at INTEGER NOT NULL,
  PRIMARY KEY (gunk_id, tag)
);

INSERT INTO tags (name, description) VALUES
  ('auth', 'Authentication and authorization flows'),
  ('payments', 'Billing, checkout, and payment integrations'),
  ('ui-kit', 'Reusable UI components and design systems'),
  ('scraper', 'Crawlers, scrapers, and data collection jobs'),
  ('dashboard', 'Admin, analytics, and reporting dashboards'),
  ('cli', 'Command-line tools and developer utilities'),
  ('mobile', 'Mobile app features, screens, and native integrations'),
  ('api', 'HTTP APIs, RPC services, and backend routes'),
  ('db-layer', 'Database models, migrations, and persistence code'),
  ('email', 'Email templates, delivery, and notification flows'),
  ('search', 'Search, indexing, ranking, and retrieval code');
""" + "\n"

  // Keep byte-for-byte identical to mcp/src/schema/v2.sql. See ADR-0010.
  // schema:v2:begin
  static let v2 = """
CREATE TABLE sources (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  path TEXT NOT NULL UNIQUE,
  dropped_at INTEGER NOT NULL,
  removed_at INTEGER
);

INSERT INTO sources (id, name, path, dropped_at, removed_at)
SELECT id, name, path, dropped_at, removed_at
FROM gunks;

CREATE TEMP TABLE _gunk_v2_files AS
SELECT id, gunk_id AS source_id, relpath, size
FROM files;

DROP TABLE gunk_tags;
DROP TABLE files;
DROP TABLE gunks;
DROP TABLE tags;

CREATE TABLE files (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  relpath TEXT NOT NULL,
  size INTEGER,
  UNIQUE(source_id, relpath)
);

INSERT INTO files (id, source_id, relpath, size)
SELECT id, source_id, relpath, size
FROM _gunk_v2_files;

DROP TABLE _gunk_v2_files;

CREATE TABLE gunks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  purpose TEXT,
  language TEXT,
  confidence REAL,
  bundle_path TEXT,
  manifest_path TEXT,
  extracted_at INTEGER,
  approved_at INTEGER,
  removed_at INTEGER
);

CREATE TABLE tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE gunk_tags (
  gunk_id INTEGER NOT NULL REFERENCES gunks(id) ON DELETE CASCADE,
  tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  confidence REAL,
  PRIMARY KEY (gunk_id, tag_id)
);

CREATE TABLE gunk_files (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  gunk_id INTEGER NOT NULL REFERENCES gunks(id) ON DELETE CASCADE,
  relpath TEXT NOT NULL,
  size INTEGER,
  UNIQUE(gunk_id, relpath)
);

CREATE TABLE llm_runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_id INTEGER REFERENCES sources(id) ON DELETE SET NULL,
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  input_tokens INTEGER,
  output_tokens INTEGER,
  cost_usd REAL,
  started_at INTEGER NOT NULL,
  finished_at INTEGER
);

INSERT INTO tags (name) VALUES
  ('auth'),
  ('payments'),
  ('ui-kit'),
  ('scraper'),
  ('dashboard'),
  ('cli'),
  ('mobile'),
  ('api'),
  ('db-layer'),
  ('email'),
  ('search');
""" + "\n"
  // schema:v2:end

  // Keep byte-for-byte identical to mcp/src/schema/v3.sql.
  // schema:v3:begin
  static let v3 = """
CREATE TABLE gunk_embeddings (
  gunk_id INTEGER PRIMARY KEY REFERENCES gunks(id) ON DELETE CASCADE,
  vector BLOB NOT NULL,
  dim INTEGER NOT NULL CHECK (dim > 0),
  model TEXT NOT NULL
);

CREATE TABLE gunk_clusters (
  member_gunk_id INTEGER PRIMARY KEY REFERENCES gunks(id) ON DELETE CASCADE,
  canonical_gunk_id INTEGER NOT NULL REFERENCES gunks(id) ON DELETE CASCADE,
  similarity REAL NOT NULL CHECK (similarity >= 0 AND similarity <= 1)
);

CREATE INDEX gunk_clusters_canonical_idx
ON gunk_clusters(canonical_gunk_id);
""" + "\n"
  // schema:v3:end

  // Keep byte-for-byte identical to mcp/src/schema/v4.sql.
  // schema:v4:begin
  static let v4 = """
INSERT INTO tags (name) VALUES ('mobile')
ON CONFLICT(name) DO NOTHING;
""" + "\n"
  // schema:v4:end
}
