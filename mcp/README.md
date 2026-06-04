# gunk-mcp

`gunk-mcp` is the short-lived TypeScript MCP server for gunk. AI tools spawn
it over stdio, it reads the local gunk store, returns context, and then exits
with the parent tool.

This package is intentionally small for T-2.2: it proves the Bun + TypeScript
toolchain works before T-2.7 adds the real MCP server surface.

## Install

```bash
cd mcp
bun install
```

## Scripts

| Script              | What it does                                |
| ------------------- | ------------------------------------------- |
| `bun run start`     | Print `gunk-mcp 0.0.1` to stderr and exit.  |
| `bun test`          | Run Vitest tests.                           |
| `bun run lint`      | Run ESLint.                                 |
| `bun run typecheck` | Run TypeScript without emitting files.      |
| `bun run format`    | Check formatting with Prettier.             |
| `bun run build`     | Bundle `src/index.ts` into `dist/` for Bun. |

## Schema (v0)

`src/schema/v0.sql` is the source of truth for the shared SQLite contract.
`openStore(path)` opens a database with WAL mode and foreign keys enabled,
applies pending migrations, and returns the `bun:sqlite` database handle.

| Table            | Columns                                                                                                                                                                              |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `schema_version` | `version INTEGER PRIMARY KEY`, `applied_at INTEGER NOT NULL`                                                                                                                         |
| `gunks`          | `id INTEGER PRIMARY KEY AUTOINCREMENT`, `name TEXT NOT NULL`, `path TEXT NOT NULL UNIQUE`, `dropped_at INTEGER NOT NULL`, `removed_at INTEGER`                                       |
| `files`          | `id INTEGER PRIMARY KEY AUTOINCREMENT`, `gunk_id INTEGER NOT NULL` referencing `gunks(id)` with cascade delete, `relpath TEXT NOT NULL`, `size INTEGER`, unique `(gunk_id, relpath)` |

Fresh databases start at version `-1`; applying v0 records version `0` with a
Unix epoch millisecond timestamp. Re-running migrations is a no-op.

## Context

- Root README: [../README.md](../README.md)
- Runtime decision: [../docs/adr/0002-stack-and-runtime.md](../docs/adr/0002-stack-and-runtime.md)
- Schema decision: [../docs/adr/0006-sqlite-schema-v0.md](../docs/adr/0006-sqlite-schema-v0.md)
