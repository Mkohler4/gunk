# ADR-0010: SQLite schema v2 modules

- **Status:** Accepted
- **Date:** 2026-06-04
- **Deciders:** Mark Kohler

## Context

ADR-0008 redefines the product noun: a gunk is an extracted reusable module,
not a dropped folder. The current SQLite schema still has the Phase 2
folder-level shape: `gunks` stores dropped folders and `files` points at those
folders. ADR-0007 added a transitional v1 tag taxonomy on top of that model,
but it did not change the core noun.

SQLite is the only contract between `gunk.app` and `gunk-mcp` (ADR-0002), so
the module pivot needs an explicit migration. This ADR records schema v2 because
schema v1 already exists on `main` as the tag-taxonomy migration. It preserves
append-only migration history while implementing the T-3.2 module-level schema
intent.

## Decision

Schema v2 converts folder-level gunks into sources and introduces module-level
gunks.

The migration is portable across the SQLite versions we ship against. It does
not use `ALTER TABLE ... RENAME COLUMN`; instead it creates new tables, copies
data with `INSERT INTO ... SELECT`, drops old tables, and recreates changed
tables.

The v2 migration is:

```sql
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
  ('api'),
  ('db-layer'),
  ('email'),
  ('search');
```

## Consequences

### Positive

- Dropped folders are now represented as `sources`, which matches ADR-0008.
- `gunks` can now represent extracted modules with confidence, approval,
  bundle, and manifest metadata.
- Source file indexing and module file membership are separate contracts:
  `files` belongs to sources, while `gunk_files` belongs to module gunks.
- LLM token and cost accounting has a first-class home in `llm_runs`.
- The v0/v1 folder rows survive the migration as `sources`.

### Negative

- This is a breaking schema change for existing MCP readers and tools. The
  current reader is updated with this migration, and richer v2 tool behavior is
  completed in later Phase 3 tasks.
- v1 folder-level tag assignments are not preserved as module tags because
  there are no module rows to attach them to yet. The taxonomy itself is
  re-seeded.
- The Swift app must mirror this migration in a follow-up task before it writes
  module rows.

### Constraints this locks in

- Future schema migrations must build on version 2, not rewrite version 1.
- The MCP package remains the source of truth for SQL migrations.
- The app-side SQL must be kept byte-for-byte compatible with this migration
  when T-3.3 mirrors it.

## Supersedes / amends

- Supersedes ADR-0006's folder-level `gunks` model.
- Supersedes ADR-0007's transitional folder-level tag schema.
- Implements ADR-0008's "gunks are modules" decision at the SQLite layer.

## Related

- ADR-0002: Stack and runtime _(Accepted)_
- ADR-0006: SQLite schema v0 _(Accepted; superseded here)_
- ADR-0007: SQLite schema v1 tags _(Accepted; superseded here)_
- ADR-0008: Gunks are modules _(Accepted)_
- `mcp/src/schema/v2.sql`
