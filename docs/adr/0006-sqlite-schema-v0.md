# ADR-0006: SQLite schema v0

- **Status:** Accepted
- **Date:** 2026-06-03
- **Deciders:** Mark Kohler

## Context

ADR-0002 makes SQLite the only contract between `gunk.app`, which writes the
local store, and `gunk-mcp`, which reads it. Both processes need one explicit,
versioned schema so they cannot silently drift as the walking skeleton grows.

Phase 2 only needs to remember dropped folders and their files. Classification,
extraction, tags, and usage data are intentionally deferred until later schema
versions.

## Decision

The MCP package owns the source-of-truth migrations. Schema v0 contains three
tables:

- `schema_version` records each applied schema version and its application
  timestamp in Unix epoch milliseconds.
- `gunks` records user-dropped folders. Removal is soft through `removed_at`.
- `files` records paths relative to a gunk and optional file sizes. Deleting a
  gunk cascades to its files.

The v0 migration is:

```sql
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
```

A database without `schema_version` is treated as version `-1`. Applying v0
creates the tables and records version `0`. Running migrations again is a
no-op. Database openers enable WAL mode and foreign-key enforcement before
returning the handle.

## Consequences

### Positive

- The app and MCP server share a small, explicit contract.
- Migration state is inspectable and idempotent.
- Unique folder paths prevent duplicate ingestion.
- Relative file paths are unique within each gunk.
- Foreign-key cascades prevent orphaned file rows.

### Negative

- The app must implement compatible migration behavior or rely on a shared
  migration path before it writes to the store.
- Schema changes now require explicit, sequential migrations and a new ADR when
  they materially change the contract.
- Soft-deleted gunks remain in the database until a future cleanup policy is
  defined.

## Related

- ADR-0002: Stack and runtime *(Accepted)*
- ADR-0005: Monorepo layout *(Accepted)*
- `mcp/src/schema/v0.sql`
