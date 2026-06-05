# gunk-mcp

`gunk-mcp` is the short-lived TypeScript MCP server for gunk. AI tools spawn
it over stdio, it reads the local gunk store, returns context, and then exits
with the parent tool.

This package runs an MCP server over stdio. AI tools start the process, complete
the MCP handshake, and keep it alive while they need access to the local gunk
store.

## Install

```bash
cd mcp
bun install
```

## Scripts

| Script              | What it does                                   |
| ------------------- | ---------------------------------------------- |
| `bun run start`     | Start the MCP server over stdio.               |
| `bun test`          | Run Vitest tests.                              |
| `bun run lint`      | Run ESLint.                                    |
| `bun run typecheck` | Run TypeScript without emitting files.         |
| `bun run format`    | Check formatting with Prettier.                |
| `bun run build`     | Compile the standalone `dist/gunk-mcp` binary. |

## Schema (v2)

`src/schema/` is the source of truth for the shared SQLite contract.
`openStore(path)` opens a database with WAL mode and foreign keys enabled,
applies pending migrations, and returns the `bun:sqlite` database handle.

| Table            | Columns                                                                                                                                                        |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `schema_version` | `version INTEGER PRIMARY KEY`, `applied_at INTEGER NOT NULL`                                                                                                   |
| `sources`        | Dropped folders: `id`, `name`, `path TEXT NOT NULL UNIQUE`, `dropped_at`, `removed_at`                                                                         |
| `files`          | Source file index: `id`, `source_id` referencing `sources(id)` with cascade delete, `relpath`, `size`, unique `(source_id, relpath)`                           |
| `gunks`          | Extracted modules: `id`, `source_id`, `name`, `purpose`, `language`, `confidence`, `bundle_path`, `manifest_path`, `extracted_at`, `approved_at`, `removed_at` |
| `tags`           | Module taxonomy: `id INTEGER PRIMARY KEY AUTOINCREMENT`, `name TEXT NOT NULL UNIQUE`                                                                           |
| `gunk_tags`      | Module tags: `gunk_id` referencing `gunks(id)`, `tag_id` referencing `tags(id)`, `confidence`, primary key `(gunk_id, tag_id)`                                 |
| `gunk_files`     | Module file membership: `id`, `gunk_id` referencing `gunks(id)` with cascade delete, `relpath`, `size`, unique `(gunk_id, relpath)`                            |
| `llm_runs`       | LLM accounting: `id`, optional `source_id`, `provider`, `model`, `input_tokens`, `output_tokens`, `cost_usd`, `started_at`, `finished_at`                      |

Fresh databases start at version `-1`; applying migrations records each schema
version with a Unix epoch millisecond timestamp. Re-running migrations is a
no-op. Version 2 migrates the Phase 2 folder-level `gunks` rows into `sources`
and re-points `files` at `sources`.

## Store Reader

The typed store reader in `src/store/` is the database boundary used by MCP
tools. It returns camel-case `Source`, module `Gunk`, `Tag`, and `GunkFile`
records while keeping SQL and schema column names inside the store layer.
Module rows include their tag names.

The reader only exposes visible modules: rows with `removed_at IS NULL` and an
`extracted_at` or `approved_at` value. Unextracted approval-queue modules stay
app-side until the user approves/extracts them.

| Function                   | Behavior                                                              |
| -------------------------- | --------------------------------------------------------------------- |
| `listSources(db)`          | Returns active dropped sources ordered by newest `droppedAt` first.   |
| `listGunks(db)`            | Returns visible module gunks with `tags`, ordered by newest ID first. |
| `searchGunks(db, query)`   | Case-insensitive match over module name, purpose, and tag names.      |
| `getGunk(db, id)`          | Returns one visible module with `tags` and `files`, or `null`.        |
| `getGunkFiles(db, gunkId)` | Returns module files for one gunk ordered by `relpath`.               |
| `listTags(db)`             | Returns the seeded classifier tag taxonomy.                           |
| `listGunkTags(db, gunkId)` | Returns one module gunk's tags ordered by confidence.                 |

## MCP Entrypoint

`src/index.ts` starts the `gunk-mcp` server using the standard MCP stdio
transport. The server advertises the tools capability and registers its tools
through `src/server/registerTools.ts`.

Run `bun run start` from `mcp/` to start the server. It stays alive while stdin
is open and exits when its parent MCP client closes the connection or the
process receives `Ctrl-C`.

## Standalone Binary

Run `bun run build` from `mcp/` to compile `dist/gunk-mcp`. The resulting
executable includes the Bun runtime, so an MCP client can launch it without Bun
installed:

```bash
/absolute/path/to/gunk/mcp/dist/gunk-mcp
```

The binary communicates over stdio and waits for MCP messages while stdin
remains open.

## Tools

### `list_gunks`

Lists the user's visible module gunks in newest-ID-first order. The tool takes
no input. On each call, it opens `~/.gunk/store.db` through the schema opener,
excludes soft-removed and unextracted gunks, and returns JSON as MCP text
content:

```json
{
  "gunks": [
    {
      "id": 2,
      "sourceId": 1,
      "name": "auth-module",
      "purpose": "Google OAuth flow",
      "language": "TypeScript",
      "confidence": 0.91,
      "tags": ["auth", "api"],
      "bundlePath": "/Users/example/.gunk/modules/2",
      "manifestPath": "/Users/example/.gunk/modules/2/gunk.yml",
      "extractedAt": 200,
      "approvedAt": null,
      "removedAt": null
    }
  ]
}
```

### `get_gunk`

Returns one active extracted module gunk's metadata, bundle README content, and
shallow bundle file tree. Call it with an integer `id` returned by `list_gunks`:

```json
{
  "id": 2
}
```

The tool checks for a root README, caps its content at 64 KiB, and returns at
most 200 root entries while skipping `.git`, `node_modules`, and `.DS_Store`:

```json
{
  "id": 2,
  "sourceId": 1,
  "name": "auth-module",
  "purpose": "Google OAuth flow",
  "language": "TypeScript",
  "confidence": 0.91,
  "bundlePath": "/Users/example/.gunk/modules/2",
  "manifestPath": "/Users/example/.gunk/modules/2/gunk.yml",
  "extractedAt": 200,
  "approvedAt": null,
  "readme": "# Auth module\n",
  "tree": [
    { "name": "README.md", "type": "file", "size": 14 },
    { "name": "src", "type": "dir" }
  ]
}
```

Unknown, removed, or not-yet-extracted IDs return an MCP tool error with
`Gunk not found: <id>`.

## Context

- Root README: [../README.md](../README.md)
- Runtime decision: [../docs/adr/0002-stack-and-runtime.md](../docs/adr/0002-stack-and-runtime.md)
- Schema decisions:
  [../docs/adr/0006-sqlite-schema-v0.md](../docs/adr/0006-sqlite-schema-v0.md),
  [../docs/adr/0010-sqlite-schema-v2-modules.md](../docs/adr/0010-sqlite-schema-v2-modules.md)
