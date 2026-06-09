# gunk roadmap

> Honest version: this is a plan, not a promise. Phases will reorder, slip, or
> get cut as we learn from real users. The point of writing it down is to make
> trade-offs visible — not to lock the future.

We ship in **weekly increments** (the build-in-public cadence) and group them
into **phases**, each with a tangible demo. A phase is "done" when we can show
its demo to a stranger and they understand what gunk is.

The architecture is set in [ADR-0001](adr/0001-what-is-gunk.md),
[ADR-0002](adr/0002-stack-and-runtime.md), and
[ADR-0015](adr/0015-full-macos-app-first.md): a full Swift macOS app
(`gunk.app`) and a short-lived TypeScript MCP server (`gunk-mcp`), sharing a
local SQLite store at `~/.gunk/store.db`. No daemon. The product principles are
set in [ADR-0003](adr/0003-ambient-over-invoked.md) and
[ADR-0004](adr/0004-drag-in-over-file-watch.md): ambient, not invoked; drag-in,
not file-watch.

## Current focus

The next product milestone is **a legit macOS app you can open**. Engine quality
is now good enough to build around. The priority is a full windowed app with
clear source import, module browsing, module detail, approval, runs/debugging,
and settings. One-click AI-tool wiring is still useful, but it moves behind the
core app experience.

The roadmap below builds toward that, **walking-skeleton-first**: Phase 2 is
the dumbest possible end-to-end loop, and every later phase deepens it.

---

## Phase 1 — Foundation (Week 1)

**Demo:** "Here's the repo, here's the green CI badge, here's the public
roadmap, here are the ADRs explaining what we're building and why."

- [x] `README`, `LICENSE` (MIT), `CHANGELOG`, `.gitignore`
- [x] ADR-0001 (what is gunk), ADR-0002 (stack), ADR-0003 (ambient over
      invoked), ADR-0004 (drag-in over file-watch)
- [x] `docs/roadmap.md` (this file)
- [ ] `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`
- [x] Initial git commit, push to GitHub (public)
- [x] GitHub Project board with issues seeded from this roadmap
- [x] Bun + TypeScript scaffold for `gunk-mcp` (lint, typecheck, test, format)
- [x] Swift Package scaffold for `gunk.app` (mirroring AICockpit's structure)
- [x] CI: GitHub Actions running lint + typecheck + test on every PR
- [x] Conventional Commits enforced (commitlint + husky)
- [ ] First build-in-public thread: thesis + repo link + the OAuth demo concept

---

## Phase 2 — Walking skeleton (Weeks 2–3)

**Demo:** Drag one of your old repos onto `gunk.app`. It appears in a list. Open
Cursor. Cursor's agent calls `gunk-mcp`, which lists the dropped folder by name
and returns its README and file tree. Cursor can now reference it. **No
classification yet — that's Phase 3. The point is the loop is real.**

This phase delivers the smallest possible end-to-end product. No part of the
architecture is allowed to ship in isolation.

### App side

- [ ] Swift menubar app skeleton (NSStatusItem, popover or panel, Defaults)
- [x] A single window with a drop zone ("Drag folders here")
- [x] Drop handler: copy folder *path* (not contents) into `~/.gunk/store.db`
- [x] List view: dropped folders, with name, path, file count, drop date
- [x] Delete affordance: remove a folder from gunk
- [x] SQLite schema v0 (using GRDB): `gunks`, `files`

### MCP server side

- [x] `gunk-mcp` skeleton using `@modelcontextprotocol/sdk`
- [x] `bun:sqlite` reader of `~/.gunk/store.db`
- [x] MCP tool: `list_gunks`
- [x] MCP tool: `get_gunk` (returns name, path, README content, shallow file
      tree)
- [x] Bun-compiled single binary
- [x] Manual MCP config snippet for one tool (Cursor) in docs

### Demo

- [ ] Manual test: drop a folder → list it via MCP from Cursor → AI references
      it
- [ ] Friday release thread: "drop a folder, your AI sees it"

This is the moment the product becomes real. Everything after this is
deepening, not green-fielding.

---

## Phase 3 — Classifier (Weeks 3–4)

**Demo:** Same as Phase 2, but each dropped folder now has tags
(`auth`, `payments`, `ui-kit`, `scraper`, `dashboard`, `cli`, `api`, …).
`search_gunks(query: "auth")` returns the right folder. Token spend on the
"build me OAuth" demo drops noticeably because Cursor only pulls the relevant
gunk.

- [ ] Pluggable LLM client (OpenAI, Anthropic, local via Ollama) inside
      `gunk.app`
- [ ] Per-folder semantic tagging at drop-time, with confidence scores
- [x] Tag taxonomy v0: `auth`, `payments`, `ui-kit`, `scraper`, `dashboard`,
      `cli`, `api`, `db-layer`, `email`, `search`
- [ ] LLM cost meter (reuse the spend-tracking insight from AICockpit)
- [ ] Re-classify affordance per gunk
- [ ] MCP `search_gunks(query)` and tag-based filtering

---

## Phase 4 — Extractor (Weeks 4–5)

**Demo:** A tagged module surfaces as a portable folder with a `gunk.yml`
manifest, just the module-relevant files (auth-related, not the whole repo),
and a generated mini-README. The AI gets a much smaller, more relevant
context window.

- [ ] Tree-sitter-based file/symbol relevance graph per tag
- [ ] `gunk.yml` manifest spec v0 (id, name, tags, language, deps, entrypoints,
      provenance, license, source path, source commit hash if git)
- [ ] On-demand extraction triggered from the app
- [ ] License-conflict detection
- [ ] MCP `get_gunk` returns the extracted module bundle, not the whole folder

---

## Phase 5 — Multi-language evals and verification feedback (Weeks 5–6)

**Demo:** Run the engine eval gate and watch web, Flutter/Dart,
Kotlin/Android, Java service, mixed monorepo, and large-repo fixtures all meet
their floors with zero trap false positives. Every persisted module has
deterministic self-containment evidence in `trace.json`.

- [x] Dart, Kotlin, and Java tree-sitter symbol extraction
- [x] Mobile/JVM manifest and import-resolution coverage for pubspec, Gradle,
      and Maven POM-backed dependencies
- [x] Multi-language eval fixtures with golden modules and negative traps:
      Flutter, Kotlin Android, Java service, mixed monorepo, and large repo
- [x] Deterministic offline replay eval harness and CLI report
- [x] Repo-map chunking/map-reduce survey for large repositories
- [x] Self-containment verification wired into quality gates
- [x] `trace.json` verification fields for self-containment and optional build
      checks
- [x] Phase retro and updated engine architecture contract

---

## Phase 6 — Full macOS app (Weeks 6–7)

**Demo:** Open `gunk.app` like a normal Mac app. Drop a source, watch it
process, browse extracted modules, inspect a module's owned files and
self-containment status, approve/reject borderline modules, and open settings
without touching a menu-bar popover.

- [ ] Main window shell with navigation: Sources, Modules, Runs, Approval,
      Settings
- [ ] Dock/window source import flow with visible processing state
- [ ] Modules browser with source/tag/language/status filtering
- [ ] Module detail view: owned files, shared deps, entrypoints,
      self-containment, optional build verification, bundle path
- [ ] Approval queue and re-run controls
- [ ] Provider/model/store/engine status in Settings
- [ ] Packaging notes for signing, notarization, and update path

---

## Phase 7 — AI-tool wiring (Weeks 7–8)

**Demo:** The finished app sees Cursor + Claude Code + Codex + OpenCode
installed and offers one-click MCP setup from Settings or onboarding.

- [ ] AI tool detectors:
  - Cursor: writes `.cursor/rules/gunk.mdc` and global MCP config
  - Claude Code: writes `~/.claude/mcp_servers.json`
  - Codex: writes `~/.codex/config.toml`
  - OpenCode: writes the appropriate config file
  - Claude Desktop: writes `claude_desktop_config.json`
- [ ] One-click "wire all" button after app onboarding is coherent
- [ ] Per-tool toggle in settings
- [ ] Idempotent: re-running detection doesn't duplicate config entries
- [ ] Usage telemetry: every time an AI tool calls gunk, log it locally

---

## Phase 8 — Polish (Weeks 8–9)

**Demo:** App feels finished. Browse view shows your gunks grouped by tag.
Approval queue handles low-confidence classifications. Menu bar shows "Cursor
used gunk 14× today." Settings let you tune classification cost vs. quality.

- [ ] Browse view: list of gunks grouped by tag, search, filter
- [ ] Approval view: classifications below confidence threshold land here
- [ ] Usage counter: "Your AI used gunk N times today / this week"
- [ ] Settings: classification provider, cost cap, watched paths (none, by
      design — but a "remove all" affordance)
- [ ] Notarized + codesigned `.app` build (reuse AICockpit's `make app`
      pipeline)
- [ ] Auto-update via Sparkle or similar

---

## Phase 9 — Friend alpha (Week 10)

**Demo:** Five real users from the Twitter circle have gunk installed, have
seen their AI use a module from gunk at least once, and have one piece of
feedback that we shipped in response.

- [ ] Hand-onboard 5 alpha testers individually (screen-share install)
- [ ] Bug bash — fix every "this is annoying" report, mercilessly
- [ ] Opt-in telemetry: which AI tools called gunk, which tags get used, where
      things fail
- [ ] Collect 5 testimonial quotes for the public launch
- [ ] Internal retro: what surprised us about real usage?

---

## Phase 10 — Public alpha (Week 11)

**Demo:** Public download of `gunk.app`, public roadmap, demo video, Show HN
post, landing page. The launch.

- [ ] Versioned release notes via release-please
- [ ] Demo video (≤90 seconds): the OAuth side-by-side
- [ ] Landing page (single static page, OSS-friendly tone)
- [ ] Show HN + ProductHunt + Twitter launch thread
- [ ] "Thanks to" page crediting the 50 Twitter responders by name
- [ ] Linux/Windows path: `gunk-mcp` standalone binary published, manual MCP
      config docs

---

## Beyond Phase 10 (speculative — not committed)

These are ideas, not promises. Each one will get its own ADR if it advances:

- Cross-platform UI (Tauri or SwiftUI on Linux/Windows)
- Multi-language extraction beyond JS/TS (Python, Go, Rust)
- Opt-in per-folder file watching (per ADR-0004's "future revisit" path)
- Smarter incremental re-classification (only diff what changed)
- An "AI agent diff view" — visual approval of what gunk is about to inject
- A possible shared/social layer (the rejected v0 marketplace) **if and only
  if** the local product is loved first

Things explicitly **not** on this list, per ADR-0001:

- Cloud sync, accounts, billing, paid plans
- Team/org features
- Public registry as part of v0
- Filesystem-wide watching as part of v0

---

## Cadence

- **Daily-ish:** small commits, one feature thread per day max.
- **Fridays:** ship a tagged release, write the build-in-public thread, update
  CHANGELOG and roadmap checkboxes.
- **End of each phase:** retro in `docs/retros/phase-N.md` — what shipped, what
  slipped, what we learned, what we're cutting.

---

## Definition of done (per item)

A roadmap item is only ✅ when:

1. The code is on `main`.
2. CI is green.
3. There is at least one test exercising it (or a documented reason there isn't).
4. The CHANGELOG mentions it under `[Unreleased]`.
5. Either the README or `docs/` explains how a stranger uses it.
6. **For user-visible features:** the macOS app exposes it (per ADR-0003 — if
   the app can't do it, it's not really shipped).
