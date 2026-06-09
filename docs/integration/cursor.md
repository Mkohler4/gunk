# Cursor MCP Integration

This guide wires Cursor to `gunk-mcp` manually. Phase 5 will replace this with
one-click setup from `gunk.app`; for Phase 3, this is the demo path.

Cursor supports global MCP servers in `~/.cursor/mcp.json` and project-specific
servers in `.cursor/mcp.json`. Use the global file for gunk so Cursor can see
your dropped folders from any workspace.

## Prerequisites

- A built `gunk-mcp` binary from `mcp/dist/gunk-mcp`.
- At least one active folder dropped into `gunk.app` and at least one extracted
  module bundle, so `~/.gunk/store.db` and `~/.gunk/modules/` have data.
- Cursor installed.

Install dependencies from a repo checkout:

```bash
cd /path/to/gunk/mcp
bun install --frozen-lockfile
```

## Install the Binary

Use the one-step installer. It **always rebuilds from the current source**
before copying, so the installed binary can never lag behind the code (a stale
binary is the usual cause of MCP "Not connected" errors):

```bash
cd /path/to/gunk/mcp
bun run install:bin
```

This installs to `~/.local/bin/gunk-mcp`. For a different location (e.g. a
system-wide install), set `GUNK_MCP_INSTALL_PATH`:

```bash
GUNK_MCP_INSTALL_PATH=/usr/local/bin/gunk-mcp sudo -E bun run install:bin
```

Re-run `bun run install:bin` any time you pull new code, so the installed
binary stays in sync with the source.

Smoke-test the installed binary. It should stay running until you press
`Ctrl-C`:

```bash
~/.local/bin/gunk-mcp
```

## Configure Cursor

Back up any existing global MCP config:

```bash
mkdir -p ~/.cursor
cp ~/.cursor/mcp.json ~/.cursor/mcp.json.backup 2>/dev/null || true
```

Open `~/.cursor/mcp.json` and merge in the `gunk` server. If the file does not
exist yet, this complete file is copy-pasteable:

```json
{
  "mcpServers": {
    "gunk": {
      "type": "stdio",
      "command": "${userHome}/.local/bin/gunk-mcp",
      "args": []
    }
  }
}
```

If you installed to `/usr/local/bin`, use this command instead:

```json
"command": "/usr/local/bin/gunk-mcp"
```

Restart Cursor, or run **Developer: Reload Window** from the command palette.

## Verify

1. Open any workspace in Cursor.
2. Open Cursor chat in agent mode.
3. Ask: `What gunks do I have?`
4. Confirm the agent calls `list_gunks` and returns extracted module gunks with
   tags, language, confidence, and source IDs.
5. Ask: `Search my gunks for auth.`
6. Confirm the agent calls `search_gunks` and returns matching modules by name,
   purpose, or tag.
7. Ask: `Show me the first gunk bundle.`
8. Confirm the agent calls `get_gunk` and summarizes the bundle manifest,
   generated mini-README, and module files.
9. Ask: `What source folders has gunk seen?`
10. Confirm the agent calls `list_sources` and returns active dropped sources.

For the Phase 3 demo, capture a screenshot of Cursor showing the `list_gunks`
or `search_gunks` tool call and include it in the PR or release notes.

## Troubleshooting

- If Cursor cannot find the server, use the absolute binary path instead of
  `${userHome}`.
- If no gunks appear, open `gunk.app` and drop a folder first, then check:

  ```bash
  sqlite3 ~/.gunk/store.db \
    "SELECT id, name, bundle_path FROM gunks WHERE removed_at IS NULL AND extracted_at IS NOT NULL;"
  ```

- If `get_gunk` returns `Gunk not found`, make sure the row has a non-empty
  `bundle_path` and the corresponding bundle still exists under
  `~/.gunk/modules/`.

- If Cursor still does not reconnect, quit and reopen Cursor after editing
  `~/.cursor/mcp.json`.
- This is intentionally manual. Per ADR-0003, gunk's happy path is ambient; the
  app will own this setup flow in Phase 5.
