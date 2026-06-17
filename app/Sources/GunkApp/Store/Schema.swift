enum Schema {
  static let version = 7

  static let migrations = [
    (version: 0, sql: v0),
    (version: 1, sql: v1),
    (version: 2, sql: v2),
    (version: 3, sql: v3),
    (version: 4, sql: v4),
    (version: 5, sql: v5),
    (version: 6, sql: v6),
    (version: 7, sql: v7)
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

  // Durable model attribution (T-9.2, audit finding D9). The one sanctioned
  // schema change of Phase 9: a module records the provider/model that created
  // it so its `via <model>` provenance survives `RunTrace` pruning and no
  // longer depends on a view-time trace lookup. Two nullable, additive columns
  // — old stores open unchanged and pre-existing rows read NULL until backfill.
  //
  // APP-ONLY — intentionally has NO mcp/src/schema/v5.sql counterpart. mcp/ is
  // off-limits this phase, and it doesn't need these columns: the gunk-mcp
  // migrator early-returns once a store is at/above its latest known version,
  // so it never trips on a v5 store, and every MCP read uses an explicit column
  // list, so the extra columns are invisible to it.
  static let v5 = """
ALTER TABLE gunks ADD COLUMN provider TEXT;
ALTER TABLE gunks ADD COLUMN model TEXT;
""" + "\n"

  // The proof loop's durable storage (T-10.3, CP-H). Two new tables back
  // everything T-10.2's runner produces and the coverage ledger (module-run-v2)
  // describes. Additive + nullable: old stores open unchanged, the new tables
  // start empty.
  //
  // Representation decision (the ADR-adjacent write-up the task asks for,
  // recorded here instead of a standalone ADR because nothing below is
  // hard-to-reverse — it is two additive tables):
  //
  // • `module_examples` is the developer's fixture library — the named cases
  //   the coverage ledger lists. Each row carries an `input_class`
  //   (`happy`/`yours`/`edge`/`adversarial`, the four coverage axes from CP-F
  //   open question #1), so a "pinned failing case" and a "known limit" are
  //   not new tables: a failing case is an example with `expected_output` +
  //   `note` set (CP-F open question #10, capture-and-queue), and a known
  //   limit is an adversarial example with a `note`. `is_golden` marks the
  //   canonical example a future run diffs against; it is exclusive **per
  //   (gunk, input_class)** rather than per module, because v2 coverage spans
  //   classes (each class has at most one golden to diff against). The task
  //   sanctioned either rule ("or per the CP-F decision").
  //
  // • `smoke_runs` is the receipt — one row per execution (or refusal). It
  //   stores the CP-F receipt fields verbatim: the `runnability` class and the
  //   `origin` (`human`/`agent`, open question #8 — agent volume must never
  //   read as human-checked), plus exit/duration/output-artifact/log. `passed`
  //   is the run's clean-exit *fact* (nullable when the module was not actually
  //   executed — a not-runnable-here class); `verdict` is the developer's
  //   separate `right`/`wrong` judgement (nullable until they judge). These are
  //   deliberately distinct columns: a clean exit is evidence, not a verdict.
  //   `example_id` is the nullable input ref (`ON DELETE SET NULL` so deleting
  //   an example never erases its receipts). `output_artifact_path` stores the
  //   **path** into the run dir, never the bytes — it prunes with the run dir.
  //
  // The Tested/coverage state stays **derived** (count of passing examples,
  // distinct brought inputs, recency) in the model layer per CP-F — T-10.11
  // owns that rule; this migration only stores the inputs it reads. Nothing is
  // denormalized here.
  //
  // APP-ONLY — intentionally has NO mcp/src/schema/v6.sql counterpart. Both the
  // gunk-mcp and TS-engine migrators pin `LATEST_VERSION = 4` and early-return
  // on any store at/above it, so neither trips on a v6 store; every MCP/engine
  // read uses an explicit column list, so these tables are invisible to them.
  // T-10.12 (the MCP run tool) will read/write these tables explicitly when it
  // lands — that dependency is noted, not pre-built here.
  static let v6 = """
CREATE TABLE module_examples (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  gunk_id INTEGER NOT NULL REFERENCES gunks(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  input TEXT NOT NULL,
  input_class TEXT NOT NULL,
  is_golden INTEGER NOT NULL DEFAULT 0,
  verdict TEXT,
  expected_output TEXT,
  note TEXT,
  created_at INTEGER NOT NULL
);

CREATE INDEX module_examples_gunk_idx ON module_examples(gunk_id);

CREATE TABLE smoke_runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  gunk_id INTEGER NOT NULL REFERENCES gunks(id) ON DELETE CASCADE,
  example_id INTEGER REFERENCES module_examples(id) ON DELETE SET NULL,
  command TEXT,
  runnability TEXT NOT NULL,
  origin TEXT NOT NULL,
  exit_code INTEGER,
  passed INTEGER,
  timed_out INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  output_artifact_path TEXT,
  log TEXT NOT NULL DEFAULT '',
  verdict TEXT,
  created_at INTEGER NOT NULL
);

CREATE INDEX smoke_runs_gunk_idx ON smoke_runs(gunk_id, created_at DESC);
""" + "\n"

  // The "How this works" cache (T-10.14). One row per module holds the
  // long-form, AI-written design analysis (the long form of the T-10.8 input
  // signature) so opening the disclosure reads the cache and is instant — a
  // live model call never happens at view time. `content` is the JSON of the
  // structured analysis (summary, data flow, key functions, what it touches,
  // its limits); `model` records which model wrote it for the honesty footer;
  // `generated_at` is when. `gunk_id` is the primary key so generating again
  // upserts in place (one analysis per module).
  //
  // Decision (recorded here rather than as a standalone ADR — nothing below is
  // hard to reverse, it is one additive table): the analysis is generated
  // **app-side and cached on first request**, not at engine extraction. The
  // engine extractor (`engine/src/extract/extractor.ts`) makes no LLM call, and
  // the manual-approve path is pure Swift with no engine at all — so an
  // "engine-only at extraction" cache would leave every manually-approved and
  // every older module permanently unanalyzed. Generating in the app (where the
  // user's chosen provider/model and key already live) is one mechanism that
  // covers every module uniformly, satisfies "generated once + cached + instant
  // on open", and lets older modules generate on demand (the refining-loop
  // rule) instead of auto-summoning a model on every page open.
  //
  // APP-ONLY — intentionally has NO mcp/src/schema/v7.sql counterpart, exactly
  // like v5/v6: both the gunk-mcp and TS-engine migrators pin
  // `LATEST_VERSION = 4` and early-return on any store at/above it, so neither
  // trips on a v7 store; every MCP/engine read uses an explicit column list, so
  // this table is invisible to them.
  static let v7 = """
CREATE TABLE module_analyses (
  gunk_id INTEGER PRIMARY KEY REFERENCES gunks(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  model TEXT,
  generated_at INTEGER NOT NULL
);
""" + "\n"
}
