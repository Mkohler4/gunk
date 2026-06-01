# ADR-0001: What is gunk?

- **Status:** Accepted
- **Date:** 2026-06-01
- **Deciders:** Mark Kohler

## Context

The AI coding boom has created a new class of waste. Developers (and their friends,
on Twitter, every day) ship throwaway projects at unprecedented rates. Each project
re-implements the same primitives — auth flows, payment handlers, dashboard
scaffolds, scrapers, settings panes. Almost none of this work is reused.

Three observable symptoms:

1. **Sprawl.** Even on GitHub, developers lose track of their own projects within
   months. There is no working index of "what have I built?"
2. **Reinvention.** A typical developer has implemented Google OAuth dozens of times
   across throwaway repos. None of it is reused; all of it is regenerated.
3. **Tool fragmentation.** Developers now use ~7 AI tools concurrently (Cursor,
   Claude Code, Codex, OpenCode, ChatGPT, Cline, Aider, others). None of those
   tools know what code the others have already produced for the same user.

The result is **token waste, time waste, and code drift.** Each "build me a login
page" prompt regenerates work that already exists locally — at real dollar cost,
real latency cost, and real divergence cost (the new auth implementation is subtly
different from the previous four).

A 50-follower Twitter post asking "what's everyone building?" returned 55 replies
referencing 50 distinct abandoned products in under a day. The signal is loud:
people *want* their existing work to be useful. There is no tool for it.

## Decision

**Gunk is a local-only library of user-curated code, exposed to AI tools.**

> Reframe, don't recode. Less tokens, more shipping.

### Two processes, one store

1. **`gunk.app` (macOS menubar).** The product. The user drops folders onto it;
   it ingests them, classifies their reusable modules (auth, payments, ui-kit,
   scraper, dashboard…), and writes the result to a local store. It also wires
   the user's installed AI tools to gunk via MCP, in one click.
2. **`gunk-mcp` (TypeScript, short-lived).** Spawned by AI tools (Cursor, Claude
   Code, Codex, OpenCode, Claude Desktop, Cline, etc.) using the standard MCP
   stdio pattern. Reads from the local store and exposes `list_gunks`,
   `search_gunks`, `get_gunk`, etc. Exits when its parent AI tool exits.
3. **`~/.gunk/`.** SQLite metadata + extracted module files. Owned by the user.
   Never leaves the machine.

There is **no daemon**. There is **no filesystem watcher** over arbitrary paths.
The app does work in-process when the user drops a folder; the MCP server is
stateless and short-lived. See ADR-0002 for the runtime details and ADR-0004 for
why we don't watch the filesystem.

### The user experience contract

- The user **types zero commands** in the happy path.
- The user installs the macOS app, drags whatever folders they want gunk to know
  about onto it, clicks "wire up my AI tools," and is done.
- The user can drag more folders in at any time. Removing them is also explicit.
- All future value (less tokens, less waste, more shipping) flows from their AI
  tools transparently consuming gunk via MCP. The user does not change their
  workflow.

### Explicitly NOT in v0

- **No public/shared registry.** No marketplace where users publish to others.
  Too complicated; deferred indefinitely until the local experience is loved.
- **No filesystem-wide watching.** Gunk only knows about folders the user has
  explicitly dropped on it. See ADR-0004.
- **No long-running daemon.** Two processes max: the app, and the MCP server
  spawned by AI tools as needed.
- **No cloud component.** No accounts, no servers, no telemetry by default.
- **No monetization.** Free, open-source, MIT.
- **No team/org features.**
- **No CLI as a primary surface.** A CLI exists for power users and scripts,
  but it is plumbing, not product.
- **No non-code artifacts.** Prompts, eval suites, dataset snippets are out.

## Consequences

### Positive

- **Sharp scope.** "Drop a folder, your AI uses it." No feature creep into
  community/social/registry territory.
- **Zero-friction UX.** No commands to learn. No mental model to internalize.
  Install once, drag folders, get value forever.
- **Universal AI integration via MCP.** One protocol covers Cursor, Claude Code,
  Codex, OpenCode, Claude Desktop, Cline, and every future MCP-compatible tool.
  We don't have to ship a per-IDE plugin.
- **Demoable in 90 seconds.** Drag one of your old repos onto the app, open
  Cursor, ask for OAuth — Cursor references your dropped folder instead of
  regenerating. That's the launch video.
- **Privacy by default.** No file-system scanning means no permission prompt,
  no Full Disk Access, no surprise "why is this app reading my Documents?".
  The user knows exactly what's in gunk because they put it there.

### Negative / open risks

- **Module boundaries are fuzzy.** "What is an auth module?" inside a dropped
  folder is partly a research question. Iterative classification heuristics +
  LLM-assisted tagging will need tuning over real corpora.
- **Auto-detection of AI tools** must be reliable across user setups (different
  install paths, different OS versions). The "wire up my tools" button is a
  delight when it works and a disaster when it silently fails.
- **macOS-first** narrows the v0 audience. The MCP server is cross-platform TS,
  so a Linux/Windows user can manually point their AI tool at it once we
  publish a binary, but they don't get the drop-zone UI yet.
- **No social validation loop.** Without a public registry, there's no built-in
  growth flywheel. Adoption depends on word-of-mouth and the build-in-public
  cadence. We accept this — focus is the point.

### Constraints this locks in

- **MCP is mandatory.** The product makes no sense without it.
- **Drop-only ingestion.** No path config, no watched roots, no auto-discovery.
- **The macOS app must be able to do everything the user needs to do.** If the
  app can't do it, it's not really shipped (per ADR-0003).
- **OSS core.** App and MCP server both ship under MIT.
- **Build-in-public cadence.** Visible weekly progress is part of the strategy.

## Out of scope for v0 (explicit non-goals)

- Public/shared registry of any kind
- Cloud sync between user devices
- Team or org accounts
- Paid plans, billing, monetization
- Cross-device sync (one machine = one gunk)
- File-system watching beyond the explicit drop event
- Browser extension
- Web app
- IDE plugins beyond what MCP provides for free
- Non-code artifacts (prompts, datasets, eval suites)

These may return in a later ADR. They are not banned forever — they are banned
**until the v0 drop-and-use product is loved**.

## Related

- ADR-0002: Stack and runtime *(Accepted)*
- ADR-0003: Ambient over invoked *(Accepted)*
- ADR-0004: Drag-in over file-watch *(Accepted)*
- `docs/roadmap.md`
