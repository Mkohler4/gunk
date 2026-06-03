# gunk roadmap

> Honest version: this is a plan, not a promise. Phases will reorder, slip, or
> get cut as we learn from real users. The point of writing it down is to make
> trade-offs visible — not to lock the future.

We ship in **weekly increments** (the build-in-public cadence) and group them
into **phases**, each with a tangible demo. A phase is "done" when we can show
its demo to a stranger and they understand what gunk is.

The architecture is set in [ADR-0001](adr/0001-what-is-gunk.md) and
[ADR-0002](adr/0002-stack-and-runtime.md): a Swift macOS menubar app
(`gunk.app`) and a short-lived TypeScript MCP server (`gunk-mcp`), sharing a
local SQLite store at `~/.gunk/store.db`. No daemon. The product principles
are set in [ADR-0003](adr/0003-ambient-over-invoked.md) and
[ADR-0004](adr/0004-drag-in-over-file-watch.md): ambient, not invoked;
drag-in, not file-watch.

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
- [ ] CI: GitHub Actions running lint + typecheck + test on every PR
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
- [ ] A single window with a drop zone ("Drag folders here")
- [ ] Drop handler: copy folder *path* (not contents) into `~/.gunk/store.db`
- [ ] List view: dropped folders, with name, path, file count, drop date
- [ ] Delete affordance: remove a folder from gunk
- [ ] SQLite schema v0 (using GRDB or sqlite3): `gunks`, `files`

### MCP server side

- [ ] `gunk-mcp` skeleton using `@modelcontextprotocol/sdk`
- [ ] `bun:sqlite` reader of `~/.gunk/store.db`
- [ ] MCP tools: `list_gunks`, `get_gunk` (returns name, path, README content,
      shallow file tree)
- [ ] Bun-compiled single binary; manual MCP config snippet for one tool
      (Cursor) in docs

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
- [ ] Tag taxonomy v0: `auth`, `payments`, `ui-kit`, `scraper`, `dashboard`,
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

## Phase 5 — AI-tool wiring (Weeks 5–6)

**Demo:** First-run experience: app launches, sees Cursor + Claude Code +
Codex + OpenCode installed, offers a single button: *"Wire them all to gunk."*
One click. From that moment, every one of those tools knows about your gunk.

- [ ] AI tool detectors:
  - Cursor: writes `.cursor/rules/gunk.mdc` and global MCP config
  - Claude Code: writes `~/.claude/mcp_servers.json`
  - Codex: writes `~/.codex/config.toml`
  - OpenCode: writes the appropriate config file
  - Claude Desktop: writes `claude_desktop_config.json`
- [ ] One-click "wire all" button in the app's onboarding
- [ ] Per-tool toggle in settings (don't wire OpenCode if user doesn't want)
- [ ] Idempotent: re-running detection doesn't duplicate config entries
- [ ] Usage telemetry: every time an AI tool calls gunk, log it locally

---

## Phase 6 — Polish (Weeks 6–7)

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

## Phase 7 — Friend alpha (Week 8)

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

## Phase 8 — Public alpha (Week 9)

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

## Beyond Phase 8 (speculative — not committed)

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
