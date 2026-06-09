# ADR-0002: Stack and runtime

- **Status:** Accepted
- **Date:** 2026-06-01
- **Deciders:** Mark Kohler

## Context

ADR-0001 commits us to building two processes and a shared local store:

1. **`gunk.app`** — a macOS menubar app. Drop zone for folders, in-process
   classifier and extractor, browse UI, one-click AI-tool wiring.
2. **`gunk-mcp`** — a short-lived MCP server, spawned by AI tools (Cursor,
   Claude Code, Codex, OpenCode, Claude Desktop, Cline, etc.) using the
   standard MCP stdio pattern. Reads from the local store; exits with its
   parent.
3. **`~/.gunk/`** — a SQLite database plus a directory of extracted module
   files.

There is **no long-running daemon** and **no IPC socket**. The app and MCP
server communicate exclusively through the shared SQLite store. SQLite's
write-ahead log handles concurrency: the app writes when the user drops a
folder; multiple short-lived MCP server instances read whenever AI tools want
context. This is the standard MCP architecture and it removes a whole class of
"why is the daemon not running?" support burden.

## Options considered

### For `gunk-mcp` (the MCP server)

- **Pros:** Most mature MCP SDK in any language (`@modelcontextprotocol/sdk`);
  best LLM-provider SDK ecosystem; largest contributor pool for OSS; Bun gives
  fast startup (essential — this process is spawned every time an AI tool
  starts), single-binary distribution via `bun build --compile`, and
  first-class SQLite support; the audience is JS-fluent and expects this stack.
- **Cons:** Compiled binary is ~50MB; we ship it inside the macOS app bundle
  rather than via `npm`, which sidesteps the size complaint.

#### Not yet evaluated (deliberately deferred)

We did **not** assess these for v0. They are parked, not rejected — each has a
trigger for when it would earn a real spike:

- **Node.js (vs. Bun)** — largest ecosystem, but slower cold start and no
  built-in single-binary compile. Revisit if Bun blocks us on a dependency or
  target platform.
- **Deno** — first-class TS and a permissions model; not evaluated for MCP SDK
  maturity or single-binary distribution. Revisit if Bun's tooling regresses.
- **Python engine/MCP** — strongest tree-sitter/LLM familiarity, but heavier
  distribution. Revisit only if the TS engine hits a real capability wall.
- **Alternative local stores** (DuckDB, embedded Postgres, plain JSON/Parquet)
  vs. SQLite — not evaluated. SQLite stays the default until a query or
  concurrency need forces the question.

### For `gunk.app` (the menubar app)

Swift / SwiftUI / AppKit is the obvious choice. Native polish, latest macOS
APIs, and Mark already has fresh muscle memory from AICockpit (menubar /
side-panel patterns, NSPanel configuration, Defaults bindings). Electron is
rejected on principle for a menubar utility.

### For app ↔ MCP-server communication

**No direct communication.** Both processes read and write the same SQLite
database at `~/.gunk/store.db`. The MCP server is purely a reader at v0
(reads modules, returns them to the AI tool). The app is the only writer.
SQLite WAL mode handles any future concurrent-write scenarios cleanly.

We considered (and rejected) running a long-lived `gunkd` daemon with a Unix
domain socket between the app and the daemon. That model adds complexity (a
process to supervise, restart, and version-skew against the app) without
giving us anything the standard MCP-spawned-by-client pattern doesn't already
provide. See "Why we rejected the daemon model" below.

## Decision

| Component   | Language    | Runtime                   | Distribution            |
|-------------|-------------|---------------------------|-------------------------|
| `gunk.app`  | Swift       | SwiftUI / AppKit          | macOS 14+, signed `.app` |
| `gunk-mcp`  | TypeScript  | Bun (single binary)       | shipped inside `gunk.app`; standalone for Linux/Windows users |
| Local store | SQLite      | `bun:sqlite` (MCP side); GRDB or sqlite3 (app side) | `~/.gunk/store.db` |
| App ↔ MCP   | shared SQLite store | —                 | local-only              |

The macOS app classifies and extracts in-process when the user drops a folder.
The MCP server is invoked by AI tools (not by the app) using the standard
stdio MCP pattern.

## Why we rejected the daemon model

Earlier drafts of this ADR proposed a long-lived `gunkd` daemon. That model
has these costs:

- A process the macOS app must spawn, supervise, restart on crash, and
  version-skew against.
- An IPC layer (Unix socket + JSON-RPC) and the schema discipline that goes
  with it.
- A "Why isn't gunk working?" support failure mode where the daemon has
  silently died.
- A second long-running thing on the user's machine to worry about.

It buys us nothing. Classification work happens **once per drop**, in-process
in the app, and writes the result to SQLite. AI tools spawn the MCP server
on demand. There is no continuous background work that requires a daemon.

If a future feature genuinely needs a daemon (e.g., a real-time
file-watcher across many ingested folders), we'll write a new ADR superseding
this one and add it then. Until then: no daemon.

## Consequences

### Positive

- **Fewer moving parts.** Two processes, one store. Easier to reason about,
  easier to debug, easier to ship.
- **Standard MCP pattern.** AI tools already know how to spawn stdio MCP
  servers. We get integration "for free" with every MCP-compatible client.
- **Best AI-tooling integration.** The MCP TS SDK is the most mature; LLM
  client SDKs all ship TS first.
- **Native macOS polish.** Swift menubar app reuses Mark's AICockpit muscle
  memory; the user-visible product feels like a real Mac app.
- **No supervisor logic.** No "is the daemon up?" checks, no restart-on-crash
  logic, no version-skew bugs.
- **Cross-platform path is clean.** `gunk-mcp` is already cross-platform TS,
  so Linux/Windows users get the AI integration today (manual MCP config) and
  a UI later.

### Negative

- **Two languages.** Bug-fixing the app and the MCP server require different
  skills. Acceptable for a solo project.
- **Schema discipline matters.** The SQLite schema is the contract between
  app and MCP server. We'll version it explicitly and write migrations.
- **Long-running classification.** When the user drops a 500-MB repo, the
  app's classifier may run for a while. We'll make it cancellable, show
  progress in the menu bar, and let the AI tool see the partial result.

## Revisit triggers

This ADR should be reopened if:

- The MCP TS SDK falls behind another language's SDK in capability or
  reliability.
- We add a feature that genuinely requires continuous background work
  (e.g., real-time watching of every ingested folder across all sessions).
  At that point, *that* feature gets its own ADR proposing a daemon.
- We need to ship a Windows-native UI; we'd evaluate Tauri vs. SwiftUI port
  vs. Electron at that point.

**Plan to revisit the deferred options.** At the start of each phase, spend ~15
minutes scanning the "Not yet evaluated" list above. Promote an item to a full
spike + superseding ADR only when a concrete need appears — a blocker, a new
target platform, or a measured performance ceiling. No such need exists today,
so all deferred options remain parked.

## Related

- ADR-0001: What is gunk? *(Accepted)*
- ADR-0003: Ambient over invoked *(Accepted)*
- ADR-0004: Drag-in over file-watch *(Accepted)*
