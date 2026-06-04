# Cursor MCP Integration

This guide wires Cursor to `gunk-mcp` manually. Phase 5 will replace this with
one-click setup from `gunk.app`; for Phase 2, this is the demo path.

Cursor supports global MCP servers in `~/.cursor/mcp.json` and project-specific
servers in `.cursor/mcp.json`. Use the global file for gunk so Cursor can see
your dropped folders from any workspace.

## Prerequisites

- A built `gunk-mcp` binary from `mcp/dist/gunk-mcp`.
- At least one active folder dropped into `gunk.app`, so
  `~/.gunk/store.db` has data.
- Cursor installed.

Build the binary from a repo checkout:

```bash
cd /path/to/gunk/mcp
bun install --frozen-lockfile
bun run build
```

## Install the Binary

Prefer a user-local install first:

```bash
mkdir -p ~/.local/bin
cp /path/to/gunk/mcp/dist/gunk-mcp ~/.local/bin/gunk-mcp
chmod +x ~/.local/bin/gunk-mcp
```

If you want a system-wide install instead:

```bash
sudo cp /path/to/gunk/mcp/dist/gunk-mcp /usr/local/bin/gunk-mcp
sudo chmod +x /usr/local/bin/gunk-mcp
```

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
4. Confirm the agent calls `list_gunks` and returns the folder you dropped into
   `gunk.app`.
5. Ask: `Show me the README of the first gunk.`
6. Confirm the agent calls `get_gunk` and summarizes or quotes the README from
   that folder.

For the Phase 2 demo, capture a screenshot of Cursor showing the `list_gunks`
tool call and include it in the PR or release notes.

## Troubleshooting

- If Cursor cannot find the server, use the absolute binary path instead of
  `${userHome}`.
- If no gunks appear, open `gunk.app` and drop a folder first, then check:

  ```bash
  sqlite3 ~/.gunk/store.db \
    "SELECT id, name, path FROM gunks WHERE removed_at IS NULL;"
  ```

- If Cursor still does not reconnect, quit and reopen Cursor after editing
  `~/.cursor/mcp.json`.
- This is intentionally manual. Per ADR-0003, gunk's happy path is ambient; the
  app will own this setup flow in Phase 5.

