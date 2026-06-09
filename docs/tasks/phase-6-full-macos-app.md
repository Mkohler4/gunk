# Phase 6 — Full macOS app

This task file supersedes the old "AI-tool wiring next" plan. The priority is
to turn `gunk.app` into a real app people can open, understand, and use before
we spend more time on automatic MCP setup.

## Phase goal

Ship a full macOS app shell around the engine that makes dropped sources,
extracted modules, verification status, approval, settings, and run traces
visible without relying on a menubar popover.

## Product constraints

- `gunk.app` is a regular Dock app first.
- The menubar item is optional/secondary.
- The Dock recycling-bin drop target remains a core gesture.
- No filesystem watching and no Full Disk Access.
- Manual MCP setup is acceptable until the app experience is coherent.

## What is wrong right now

- Docs and task files still conflict: some say "menubar app", while the code and
  ADR-0009 already moved toward a regular Dock app.
- The engine can extract multi-file modules, but the app does not yet explain
  module boundaries, self-containment, or whether an extracted bundle is
  runnable.
- Several historical task files have unchecked boxes for work that later landed
  in different forms. Treat those specs as history, not the active backlog.
- The roadmap over-prioritized one-click AI-tool wiring before the Mac app felt
  like a complete product.

## T-6.1 — App shell and navigation

**Status:** Shipped in PR for T-6.1
**Owner:** Codex

### Goal
Replace the popover-first experience with a full windowed macOS app shell.

### Files
- `app/Sources/GunkApp/AppDelegate.swift`
- `app/Sources/GunkApp/Views/*`
- `app/README.md`

### Acceptance
- Opening `gunk.app` shows a primary window.
- The window has stable navigation for Sources, Modules, Runs, Settings, and
  Approval.
- The menubar item, if present, opens the main window instead of being the main
  workspace.

## T-6.2 — Import/drop source workflow

**Status:** Not started
**Owner:** Codex

### Goal
Make adding sources obvious from the main window and Dock.

### Acceptance
- Users can drag folders onto the Dock icon or main window.
- Import progress is visible in the main app.
- Dropped sources show status: queued, processing, complete, failed.

## T-6.3 — Modules browser

**Status:** Not started
**Owner:** Codex

### Goal
Show extracted modules as the primary object, not raw folders.

### Acceptance
- Modules can be grouped or filtered by source, tag, language, and approval
  state.
- Each row shows name, purpose, tags, source, confidence, and extraction status.
- Trivial rejected candidates are not shown as modules.

> Note: tags are now AI-discovered, not a fixed 11-tag taxonomy. The engine mints
> normalized (lowercase kebab-case) domain tags per module and auto-creates them
> in the `tags` table. The tag/filter UI must treat the tag set as **open and
> growing** (read it from the DB at runtime) rather than a hardcoded list of
> seeded tags.

## T-6.4 — Module detail and runability contract

**Status:** Not started
**Owner:** Codex

### Goal
Make it clear what a gunk bundle contains and whether it can run by itself.

### Acceptance
- Detail view shows owned files, shared dependencies, entrypoints, bundle path,
  self-containment result, and optional build verification result.
- UI copy distinguishes "self-contained for AI reuse" from "standalone runnable
  project."
- Users can open the extracted bundle in Finder.

## T-6.5 — Approval and re-run controls

**Status:** Not started
**Owner:** Codex

### Goal
Make low-confidence and needs-approval modules manageable inside the app.

### Acceptance
- Approval queue is available from the main navigation.
- Users can approve, reject/remove, and re-run decomposition for a source.
- Actions update the shared store and refresh views.

## T-6.6 — Settings and provider status

**Status:** Not started
**Owner:** Codex

### Goal
Make engine/provider configuration visible and debuggable.

### Acceptance
- Settings show provider/model, API-key status, local store path, engine binary
  status, and MCP config status.
- Missing configuration is explained in-app.

## T-6.7 — Packaging and Mac polish

**Status:** Not started
**Owner:** Codex

### Goal
Make the app feel installable and trustworthy.

### Acceptance
- `make app` produces a runnable `.app`.
- App icon, launch behavior, main menu, window restoration, and failure states
  are tested manually.
- Signing/notarization/update path is documented, even if not fully automated.

## T-6.8 — Dynamic tags: validation, discovery, and consistency

**Status:** Not started
**Owner:** Codex

### Goal
Harden the dynamic AI-driven tagging that landed engine-only (the refiner now
mints normalized, lowercase kebab-case domain tags per module and `persist`
auto-creates them in the `tags` table). These are the deferred follow-ups from
that change, grouped here so they stay on the active backlog instead of being
brushed aside.

### Acceptance
- **Eval recall (engine):** re-record the replay tapes against the relaxed
  refiner schema (requires an API key) so the eval corpus actually demonstrates
  novel tags matching golden labels such as `orders`/`reports`, and
  `tag_accuracy` reflects dynamic tags. Today replay evals only prove
  determinism, not dynamic-tag recall, because the tapes were recorded under the
  old `enum`-constrained schema.
- **Discovery (MCP):** add a `list_tags` MCP tool (and/or surface the live tag
  vocabulary in tool descriptions) so AI clients can see the growing tag set
  instead of inferring it from individual gunks. `search_gunks` already matches
  arbitrary tag strings, so this is purely additive.
- **Editing (app):** let users view and edit a module's tags and trigger a real
  reclassify/re-run from the app. This extends T-6.3 (Modules browser) and T-6.5
  (Approval and re-run controls); the Swift `reclassify` hook is currently a
  no-op.
- **Consistency (engine):** add synonym/alias collapsing beyond normalization
  (e.g. fold `billing` into `payments`) so semantically equivalent tags
  converge. Keep it deterministic and eval-gated so it cannot regress the
  Phase 5 floor.

### Notes
- No schema change was required for dynamic tags (`tags.name` is already an open
  `TEXT UNIQUE` column). Every item above is additive and must preserve the
  byte-for-byte engine/MCP/Swift schema parity and the Phase 5 eval floor.

## Later: AI-tool auto-wiring

Move one-click Cursor/Claude/Codex/OpenCode setup here until the app shell is
ready. It is still important, but it is no longer the next phase.
