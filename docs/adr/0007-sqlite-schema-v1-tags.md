# ADR-0007: SQLite schema v1 tags

- **Status:** Accepted
- **Date:** 2026-06-04
- **Deciders:** Mark Kohler

## Context

Phase 3 adds classifier behavior: dropped folders need tags such as `auth`,
`payments`, and `ui-kit`, and MCP will eventually expose tag-based search.
ADR-0006 intentionally deferred classification data from schema v0, so adding
tags requires an explicit schema version shared by `gunk.app` and `gunk-mcp`.

The first classifier contract should be small. We need enough structure for the
app to persist classifier output and for MCP to read it, without locking in a
specific LLM provider or prompt format.

## Decision

Schema v1 adds two tables:

- `tags` stores the fixed v0 taxonomy by tag name and human-readable
  description.
- `gunk_tags` joins gunks to tags with `confidence`, `source`, and
  `tagged_at`.

The v0 taxonomy is:

- `auth`
- `payments`
- `ui-kit`
- `scraper`
- `dashboard`
- `cli`
- `api`
- `db-layer`
- `email`
- `search`

The v1 migration is:

```sql
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
```

The migration seeds the taxonomy into `tags`.

`confidence` is a normalized `REAL` from `0` to `1`. `source` records whether a
tag came from the eventual LLM classifier, a manual user action, or a simple
heuristic. `tagged_at` is a Unix epoch millisecond timestamp.

## Consequences

### Positive

- Tags become a first-class shared contract between the app and MCP server.
- The fixed taxonomy is queryable and inspectable from SQLite.
- Future classifier runs can replace a gunk's tags without changing the schema.
- MCP can implement `search_gunks(query)` and tag filtering on top of the same
  contract.

### Negative

- The taxonomy is intentionally small and will need evolution as real folders
  expose missing categories.
- `source` is deliberately coarse. If future classifier debugging needs prompt
  IDs, model names, or token counts per run, that belongs in a later table.
- Soft-deleted gunks keep their tag rows until hard deletion or cleanup policy
  exists, matching the existing v0 soft-delete behavior.

## Related

- ADR-0002: Stack and runtime *(Accepted)*
- ADR-0005: Monorepo layout *(Accepted)*
- ADR-0006: SQLite schema v0 *(Accepted)*
- `mcp/src/schema/v1.sql`
