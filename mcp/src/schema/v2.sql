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
