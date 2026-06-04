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

## Schema (v1)

`src/schema/` is the source of truth for the shared SQLite contract.
`openStore(path)` opens a database with WAL mode and foreign keys enabled,
applies pending migrations, and returns the `bun:sqlite` database handle.

| Table            | Columns                                                                                                                                                                              |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `schema_version` | `version INTEGER PRIMARY KEY`, `applied_at INTEGER NOT NULL`                                                                                                                         |
| `gunks`          | `id INTEGER PRIMARY KEY AUTOINCREMENT`, `name TEXT NOT NULL`, `path TEXT NOT NULL UNIQUE`, `dropped_at INTEGER NOT NULL`, `removed_at INTEGER`                                       |
| `files`          | `id INTEGER PRIMARY KEY AUTOINCREMENT`, `gunk_id INTEGER NOT NULL` referencing `gunks(id)` with cascade delete, `relpath TEXT NOT NULL`, `size INTEGER`, unique `(gunk_id, relpath)` |
| `tags`           | `name TEXT PRIMARY KEY`, `description TEXT NOT NULL`                                                                                                                                 |
| `gunk_tags`      | `gunk_id INTEGER NOT NULL` referencing `gunks(id)`, `tag TEXT NOT NULL` referencing `tags(name)`, `confidence REAL NOT NULL`, `source TEXT NOT NULL`, `tagged_at INTEGER NOT NULL`   |

Fresh databases start at version `-1`; applying migrations records each schema
version with a Unix epoch millisecond timestamp. Re-running migrations is a
no-op.

## Store Reader

The typed store reader in `src/store/` is the database boundary used by future
MCP tools. It returns camel-case `Gunk` and `GunkFile` records while keeping SQL
and schema column names inside the store layer.

| Function                   | Behavior                                                    |
| -------------------------- | ----------------------------------------------------------- |
| `listGunks(db)`            | Returns active gunks ordered by newest `droppedAt` first.   |
| `getGunk(db, id)`          | Returns the matching gunk or `null` when the ID is unknown. |
| `getGunkFiles(db, gunkId)` | Returns files for one gunk ordered by `relpath`.            |
| `listTags(db)`             | Returns the seeded classifier tag taxonomy.                 |
| `listGunkTags(db, gunkId)` | Returns one gunk's tags ordered by confidence.              |

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

Lists the user's active gunks (folders dropped onto `gunk.app`) in newest-first
order. The tool takes no input. On each call, it opens `~/.gunk/store.db`
through the schema opener, excludes soft-removed gunks, and returns JSON as MCP
text content:

```json
{
  "gunks": [
    {
      "id": 2,
      "name": "newer-project",
      "path": "/Users/example/code/newer-project",
      "droppedAt": 200,
      "removedAt": null
    }
  ]
}
```

### `get_gunk`

Returns one active gunk's metadata, root README content, and shallow file tree.
Call it with an integer `id` returned by `list_gunks`:

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
  "name": "newer-project",
  "path": "/Users/example/code/newer-project",
  "droppedAt": 200,
  "readme": "# Newer project\n",
  "tree": [
    { "name": "README.md", "type": "file", "size": 16 },
    { "name": "src", "type": "dir" }
  ]
}
```

Unknown or removed IDs return an MCP tool error with `Gunk not found: <id>`.

## Context

- Root README: [../README.md](../README.md)
- Runtime decision: [../docs/adr/0002-stack-and-runtime.md](../docs/adr/0002-stack-and-runtime.md)
- Schema decision: [../docs/adr/0006-sqlite-schema-v0.md](../docs/adr/0006-sqlite-schema-v0.md)
