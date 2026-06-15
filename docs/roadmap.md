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

The windowed app exists and works end-to-end, and Phase 7 gave it a real
design system (brand tokens, glass components, wordmark, Dock tile) with the
shell, Sources, and Modules pages re-skinned. But the layout is still
confusing to use, two pages (Approval, Runs) never got re-skinned, and the
product's actual selling point — modules as capabilities your agent uses
through MCP — is buried.

The next milestone is **the redesign arc (Phases 8–13)**: restructure the IA
around a Library, put the model switcher and MCP status front and center,
make folder processing feel alive, let users run and test modules, surface
token/cost spend, stub the marketplace UI, and finish with an onboarding
walkthrough. Ground truth for the redesign lives in
[docs/design/feature-report/](design/feature-report/README.md) (a per-page
audit of every front-end feature) and
[docs/design/ux-architecture.md](design/ux-architecture.md).

## How we actually got here (non-linear path)

The phases below keep their original planned numbering, but we did **not** build
them in that order. Engine quality was the riskiest, highest-leverage part of the
product, so we front-loaded it: the classification, extraction, and
multi-language eval work (the heart of Phases 3–5) was built first as a
cross-platform TypeScript engine (`gunk-engine`, per ADR-0013/0014). The macOS
app shell (Phase 6) and the design system + re-skin (Phase 7) are built, and
the product glue and launch work (cost meter UI, in-app reclassify,
`list_tags`, AI-tool auto-wiring, packaging, alpha/launch) still trails — it
is folded into the redesign phases below.

So the checkboxes below reflect **real status, not the original week order**: an
item is checked if it actually exists today, wherever it was built. Note that
several Phase 6 component views already exist from earlier app work even though
the unified windowed shell does not yet.

---

## Phase 1 — Foundation (Week 1)

**Demo:** "Here's the repo, here's the green CI badge, here's the public
roadmap, here are the ADRs explaining what we're building and why."

- [x] `README`, `LICENSE` (MIT), `CHANGELOG`, `.gitignore`
- [x] ADR-0001 (what is gunk), ADR-0002 (stack), ADR-0003 (ambient over
      invoked), ADR-0004 (drag-in over file-watch)
- [x] `docs/roadmap.md` (this file)
- [x] `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`
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

- [x] Swift menubar app skeleton (NSStatusItem, popover or panel, Defaults)
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

- [x] Pluggable LLM client (OpenAI, Anthropic, local via Ollama) inside
      `gunk.app` (`LLM/{OpenAI,Anthropic,Ollama}Client.swift` + secret store)
- [x] Per-folder semantic tagging at drop-time, with confidence scores
      — evolved into engine-driven module decomposition with per-module
      confidence (richer than the original per-folder tag)
- [x] Tag taxonomy v0: `auth`, `payments`, `ui-kit`, `scraper`, `dashboard`,
      `cli`, `api`, `db-layer`, `email`, `search` (now a *seed*; tags are
      AI-derived and open — see ADR/CHANGELOG dynamic tags)
- [ ] LLM cost meter — partial: per-run `cost_usd` + token usage are tracked in
      the store, but no in-app meter UI yet
- [ ] Re-classify affordance per gunk — engine can re-run, but the app
      `reclassify` hook is still a no-op (tracked in T-6.8)
- [x] MCP `search_gunks(query)` and tag-based filtering

---

## Phase 4 — Extractor (Weeks 4–5)

**Demo:** A tagged module surfaces as a portable folder with a `gunk.yml`
manifest, just the module-relevant files (auth-related, not the whole repo),
and a generated mini-README. The AI gets a much smaller, more relevant
context window.

- [x] Tree-sitter-based file/symbol relevance graph per tag (engine symbol
      extraction + code graph + capability closures)
- [x] `gunk.yml` manifest spec v0 (id, name, tags, language, deps, entrypoints,
      provenance, license, source path, source commit hash if git)
- [x] On-demand extraction triggered from the app (engine `extract/*`, driven by
      the app's `SourceProcessingRunner`)
- [x] License-conflict detection (`LicenseDetector`, engine + app)
- [x] MCP `get_gunk` returns the extracted module bundle, not the whole folder

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

- [x] Main window shell with navigation: Sources, Modules, Runs, Approval,
      Settings
- [x] Dock/window source import flow with visible processing state
- [x] Modules browser with source/tag/language/status filtering
- [x] Module detail view: owned files, shared deps, entrypoints,
      self-containment, optional build verification, bundle path
- [x] Approval queue and re-run controls
- [x] Provider/model/store/engine status in Settings
- [ ] Packaging notes for signing, notarization, and update path

---

## Phase 7 — Design & branding (Weeks 8–10) — done

**Demo:** The app has an identity: brand tokens, glass components, wordmark,
and Dock tile — and the shell, Sources, and Modules pages wear them.

> Note: this phase replaced the originally planned "AI-tool wiring" phase —
> the design debt was blocking everything else. AI-tool wiring (multi-client
> MCP config writers, one-click setup) moves into Phase 8 and the Phase 13
> onboarding. The originally planned "Polish" phase dissolved into Phases
> 8–13 below.

- [x] Design tokens (colors, typography, metrics, motion) + component kit
      (glass cards, status badges, tag chips, brand buttons, empty states,
      wordmark)
- [x] UX architecture audit and placement contract
      ([docs/design/ux-architecture.md](design/ux-architecture.md))
- [x] Shell re-skin: fixed sidebar, journey ordering, badges, status strip,
      landing rules
- [x] Sources re-skin: hero drop zone, per-row status/outcome, arrival
      highlight
- [x] Modules re-skin: pinned filter bar, module rows, detail pane,
      Agent-ready line
- [x] Brand Dock tile (empty / full / processing) + branded launch-failure
      view
- [ ] Approval and Runs re-skins (deferred — absorbed by Phases 8–9)
- [ ] Dock badge render bug (B2) and threshold bug (B1) (carried to Phases 9
      and 11). B2 **fixed** in Phase 9 (T-9.5 #167); B1 (the threshold
      slider) still open for Phase 11

---

## Phase 8 — Shell & IA restructure (Weeks 11–12)

**Demo:** Open the app and the layout makes sense without explanation. The
model switcher and MCP status are the first things you see, not buried in
Settings.

> Task breakdown:
> [docs/tasks/phase-8-shell-and-ia-restructure.md](tasks/phase-8-shell-and-ia-restructure.md)
> (T-8.1 – T-8.11, with checkpoints CP-A/B/C).

- [x] New top-level IA: **Library**, **Marketplace** (placeholder tab),
      **Settings**. Sources merges into Library (the drop zone lives there);
      Approval folds into Library as a review state/filter; Runs demotes to a
      run inspector opened from a source or module, not a tab. The
      [toolbox-v1 exploration](design/explorations/toolbox-v1.md) validated
      this shell IA (sidebar: Toolbox / Runs / Settings + MCP chip).
      Landed across T-8.2/8.3/8.4/8.6 (plus an **Add module** sidebar entry
      from the T-8.3b follow-ups); restyled to toolbox-v2 in T-8.3b
- [x] The entire app is a drop target: dragging a folder anywhere over the
      window raises a full-window drop overlay, and **nothing in the layout
      moves** — the overlay floats above the current view, drops are
      accepted regardless of which section is showing, and it dismisses
      cleanly on drag-exit/drop (extends the existing no-layout-shift rule,
      D15, to the drag gesture itself). Landed in T-8.5 (#153)
- [x] Model switcher in the shell chrome (not behind Settings) — per-provider
      keys already coexist in Keychain, so this is placement + a picker, not
      new storage. Landed brought-forward in the T-8.5 PR (#153), closed out
      in T-8.8: placement is the Library appbar's trailing slot (the
      toolbox-v2 mockup's `.model` position, not the window toolbar), and
      the menu lists only providers with a saved API key
- [x] MCP status front and center when not configured. (Reality check: this
      is *not* hardcoded today — `MCPStatusProvider` genuinely inspects
      `~/.cursor/mcp.json` for a `gunk-mcp` server entry. The work is
      surfacing it prominently and adding one-click setup, not inventing the
      check.) Landed in T-8.7 (persistent MCP chip) + T-8.10 (one-click
      `MCPSetupView` sheet); the provider generalized into
      `MCPClientConfigurator` (T-8.9)
- [x] Multi-client MCP wiring pulled in from the old AI-tool-wiring phase:
      Cursor, Claude Code, Claude Desktop, Codex, OpenCode — idempotent
      config writers, per-tool toggle. Landed in T-8.9 (#160, configurator +
      bundled gunk-mcp installed on wire) and T-8.10 (#161, setup sheet +
      Settings toggles)
- [x] Decompose the overloaded sidebar status strip (today it is MCP health +
      live progress + completion toast + failure alert in one chip with a
      different click target per state). Landed in T-8.7 (#158): MCP chip +
      transient processing element + run-end toast
- [x] Design-first: feed [docs/design/feature-report/](design/feature-report/README.md)
      and the library-view prompt to design before implementing. Iterations
      land in [docs/design/explorations/](design/explorations/) with an
      approved/rejected verdict per iteration (see
      [toolbox-v1](design/explorations/toolbox-v1.md)). CP-A approved
      [toolbox-v2](design/explorations/toolbox-v2.md) (implemented in
      T-8.3b); [module-run-v1](design/explorations/module-run-v1.md) feeds
      Phase 10

---

## Phase 9 — Library v2 + processing states (Weeks 12–14)

**Demo:** Drop a folder, watch it process with a real animation while you
keep browsing, then scan the library and instantly spot the one module that
needs attention.

> Task breakdown:
> [docs/tasks/phase-9-library-v2-and-processing-states.md](tasks/phase-9-library-v2-and-processing-states.md)
> (T-9.1 – T-9.7, with checkpoints CP-D/E).
>
> Design (CP-D, **approved**): the list-view + global-processing-animation
> exploration is
> [docs/design/explorations/library-v2.md](design/explorations/library-v2.md)
> (from the
> [revision instruction](design/explorations/library-v2-instruction.md)). It
> unblocks T-9.3 and T-9.4 visual work.

- [x] Module cell redesign (per
      [library-view-prompt.md](design/feature-report/library-view-prompt.md)):
      purpose line, distinct trust states (confidence / self-containment /
      build / approval), agent-ready axis — not one ambiguous checkmark.
      Shipped in [toolbox-v2](design/explorations/toolbox-v2.md) (T-8.3b): one
      trust verdict, prominent name, purpose line, `via <model>` provenance,
      provider corner, usage-ranked hero. Phase 9 reuses `ModuleCell` as-is
      and adds the dense list-row variant (T-9.3)
- [x] Model attribution: each module states which model created it, with the
      provider's logo (OpenAI / Anthropic / Ollama). Landed in T-9.2 (#166,
      #165): a denormalized `provider`/`model` pair on `gunks` (Schema v5,
      forward migration + backfill from traces, closing audit finding D9),
      preferred by `provenance(for:)` with a trace fallback; provider brand
      glyphs render as a quiet `ProviderMark`/`ProviderWatermark` (neutral
      fallback for unshipped brands)
- [x] Grid + list view toggle, module search (toggle in T-9.3 #167, persisted
      via Settings defaults; search shipped in Phase 8)
- [x] Single-folder processing rule: enforce a one-at-a-time queue (the
      processing model technically allows concurrency today), with a global
      animated processing state; the app stays fully browsable during a run.
      Landed in T-9.4 (#167): a serial queue in `SourceProcessingRunner`, a
      queue-depth signal on `ProcessingModel`, and one global animated state
      reconciled with the T-8.7 chip (resolves to the existing run-end toast)
- [ ] Dependencies + versions panel in module detail (parsed from bundle
      manifests) — *moved to Phase 10* as the "requirements readout"
      (reshaped from a path list into "to run this elsewhere you need")
- [x] Fix the Dock badge render bug (B2) while in the processing/feedback
      area (T-9.5 #167: forced `dockTile.display()` at transitions +
      regression test)
- [→] Stretch (looks-good-only, explicitly low value): graph view of module
      relationships — same-repo modules cluster as one entity, click-through
      morphs the graph into the module's files. **Moved to Phase 13** (T-9.6
      deferred, not built) — lowest-value item, kept for a later phase rather
      than cut (see [phase-9 retro](retros/phase-9.md) and
      [Phase 13 task doc](tasks/phase-13-walkthrough-onboarding.md))

---

## Phase 10 — Run & test modules (Weeks 14–15)

**Demo:** Click "Try it" on a module, watch its entrypoint actually run with
the output streaming in a terminal block, and the module earns a "Tested"
badge.

> Task breakdown:
> [docs/tasks/phase-10-run-and-test-modules.md](tasks/phase-10-run-and-test-modules.md)
> (T-10.1 – T-10.15, with checkpoints CP-F…CP-K). It empowers **both** the
> developer (run, judge, pin a golden example) **and the AI system** (an MCP
> run/test tool so the agent verifies a module before it uses it).
>
> Product definition + design prompt:
> [smoke-run-prompt.md](design/feature-report/smoke-run-prompt.md) — the
> developer trust loop. MCP is the agent's door into a module; this phase is
> the developer's door. Two questions drive every item: *"does it actually
> do the thing?"* (proof, not claims) and *"can I take it somewhere?"*
> (portability).
>
> **Scope grew (2026-06-12):** the design exploration
> [module-run-v1.md](design/explorations/module-run-v1.md) lands clicking a
> module on a **full module page** (breadcrumb, not a sheet) whose spine is
> the proof loop: a synthesized before/after Proof card with developer
> verdicts and pinned golden examples, a **real terminal** with developer
> and example inputs (sandbox-bounded), and the Tested-badge leveling rule
> as the honest metric — one passing example never reads "Proven." Broken
> into its own task-list doc (linked above); items below are the original
> (still-valid) skeleton the tasks expand, with two revisions inline.

- [ ] **Smoke run ("Try it")**: execute a module's entrypoint against its
      extracted bundle in a sandbox, persist the receipt (when, pass/fail,
      duration, output). Receipt-first per module-run-v1: the primary
      evidence is the before/after Proof card **on the full module page**
      (the "detail sheet" is superseded); the raw command + log demote to a
      disclosure. First-run consent treatment (it executes extracted code);
      states: never-tried / consent / running / passed / failed / resting
      receipt. Build verification already stores a command + log, so the
      store pattern exists
- [ ] **Copyable invocation snippet** per module, generated from the stored
      entrypoints + symbols ("how do I use this" in one glance)
- [ ] **Requirements readout**: reshape shared-dependency *paths* into "to
      run this elsewhere you need" — runtime, packages, env vars (parsed
      from bundle manifests; absorbs the old "dependencies + versions
      panel" item from Phase 9)
- [ ] Tested badge: new store field + leveling rule (badge tier scales with
      how much the module was tested) — this becomes the marketplace ranking
      signal in Phase 12, and smoke-run receipts are the first *honest*
      usage signal for the Library's `heroRank` `FUTURE` seam (never
      fabricate usage numbers)
- [ ] Runs stay **receipts, not a dashboard**: the extraction-run inspector
      (T-8.6) answers "what did gunk do"; the smoke run answers "what does
      the module do" — two surfaces, linked from the module, never merged
- [ ] UI-module runner: detect UI modules and **launch the browser** at the
      module's served surface — in-app preview is explicitly out for now
      (module-run-v1 revision of the old "launch/preview them from the app")
- [ ] Explicitly out: dependency-graph visualizations, run-history charts,
      in-app editing, metrics dashboards

---

## Phase 11 — Settings v2 (Weeks 15–16)

**Demo:** See exactly what you've spent, across every key and model.

- [ ] Token + cost meter — presentation only: per-run `input_tokens` /
      `output_tokens` / `cost_usd` already land in the store (this closes the
      Phase 3 "LLM cost meter" leftover)
- [ ] Multi-provider API key management UI (per-provider Keychain storage
      already exists; the management UI doesn't)
- [ ] Local model (Ollama) configuration UX
- [ ] Label the confidence threshold slider and fix bug B1 (the approval
      queue gates on a hard-coded 0.7 instead of the user's setting)
- [ ] Stretch: cost cap setting (from the old Polish phase)

---

## Phase 12 — Marketplace, UI-first (Weeks 16–18)

**Demo:** Browse other people's modules, "install" one, and it appears in
your library as agent-ready.

- [ ] Browse / search / module detail UX built against static or mock data
- [ ] Install flow: bring a marketplace module into the local store and MCP
- [ ] Publish flow designed but stubbed (no real upload)
- [ ] Tested-badge-drives-ranking expressed in the UI
- [ ] Backend (hosting, accounts, real publishing, ranking service) is
      explicitly **out of scope** — gated on the local product being loved
      first, consistent with ADR-0001's no-registry-in-v0 stance. This phase
      is UI against mocks only

---

## Phase 13 — Walkthrough / onboarding (Weeks 18–19)

**Demo:** First launch is a branded, animated intro that ends on a plain
screen with exactly two choices: drop a folder, or browse the marketplace.

- [ ] Animation-heavy brand intro → simple one-line explanation → two-action
      landing
- [ ] Marketplace modules shown during onboarding as the MCP-value marketing
      moment (the MCP is the main value of the app)
- [ ] One-click MCP wiring offered during onboarding (reusing the Phase 8
      config writers)
- [ ] Built last on purpose: it needs marketplace content and the final IA to
      point at
- [ ] Stretch (carried from Phase 9, looks-good-only, explicitly low value):
      graph view of module relationships — same-repo modules cluster as one
      entity, click-through morphs the graph into the module's files. Deferred
      from Phase 9 (was T-9.6); built strictly on existing data, behind a quiet
      affordance, cut without ceremony if it competes with the Library for scan
      attention (see [Phase 13 task doc](tasks/phase-13-walkthrough-onboarding.md))

---

## Phase 14 — Friend alpha (Week 20)

**Demo:** Five real users from the Twitter circle have gunk installed, have
seen their AI use a module from gunk at least once, and have one piece of
feedback that we shipped in response.

- [ ] Notarized + codesigned `.app` build (reuse AICockpit's `make app`
      pipeline; from the old Polish phase)
- [ ] Auto-update via Sparkle or similar (from the old Polish phase)
- [ ] Hand-onboard 5 alpha testers individually (screen-share install)
- [ ] Bug bash — fix every "this is annoying" report, mercilessly
- [ ] Opt-in telemetry: which AI tools called gunk, which tags get used, where
      things fail
- [ ] Collect 5 testimonial quotes for the public launch
- [ ] Internal retro: what surprised us about real usage?

---

## Phase 15 — Public alpha (Week 21)

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

## Beyond Phase 15 (speculative — not committed)

These are ideas, not promises. Each one will get its own ADR if it advances:

- **Live, graded LLM-quality evals.** Today's eval gate is *deterministic
  replay* (key-free, CI-safe): it replays recorded model responses and so tests
  the engine *around* the model, not the model's actual answers. A follow-up
  harness should run the pipeline against a live provider and grade real
  decomposition quality (golden-label scoring and/or an LLM judge), track
  quality drift across prompt and model changes, and gate on quality
  thresholds — run on a cadence/nightly rather than per-PR so CI stays key-free.
  See T-6.8 for the near-term first step (re-recording tapes against the current
  schema). Gets its own ADR.
- Cross-platform UI (Tauri or SwiftUI on Linux/Windows)
- Multi-language extraction beyond JS/TS (Python, Go, Rust)
- Opt-in per-folder file watching (per ADR-0004's "future revisit" path)
- Smarter incremental re-classification (only diff what changed)
- An "AI agent diff view" — visual approval of what gunk is about to inject
- Agent usage telemetry surfaced in the Library ("your agent pulled this
  module 14× this week") — the data doesn't exist yet; library cell designs
  must work without it (absorbs the old Polish phase's usage counter)
- The **marketplace backend** (hosting, accounts, real publishing,
  test-based ranking service) — Phase 12 ships the UI against mocks; the
  backend happens **if and only if** the local product is loved first

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
