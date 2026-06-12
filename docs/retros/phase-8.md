# Phase 8 retro: shell & IA restructure

Phase 8 rebuilt the app's information architecture so the layout makes sense
without explanation. The five-tab journey (Sources → Modules → Approval →
Runs → Settings) collapsed into a **Library**-centered shell where sources,
review, and run traces are states and inspectors of the one surface users
actually live in — and the product's selling point, MCP, went from a buried
Settings row to a persistent chip with one-click setup for five AI clients.

Task breakdown: [docs/tasks/phase-8-shell-and-ia-restructure.md](../tasks/phase-8-shell-and-ia-restructure.md)
(T-8.1–T-8.11, checkpoints CP-A/B/C, all cleared).

## What shipped

- **Three-section IA** (T-8.2): Library / Marketplace (placeholder) /
  Settings, plus an **Add module** sidebar entry from the T-8.3b follow-ups.
  Always lands on Library.
- **toolbox-v2 visual restyle** (T-8.1 design gate CP-A, implemented in
  T-8.3b): neutral graphite surfaces (the green-tinted "ooze" palette is
  gone), provider-accent art colors, and the Library as briefing-card cells
  with one trust verdict each, `via <model>` provenance, provider corner
  badges, and a usage-ranked hero cell per group (documented fallback
  ranking until telemetry exists). Single-row appbar: title + count,
  `Project | Model` grouping, search, and the model readout.
- **Sources folded into Library** (T-8.3): sources panel sheet reusing the
  same row logic, add-folder via picker, delete behind a confirmation whose
  copy matches verified store behavior (modules are orphaned, not deleted).
- **Approval folded into Library** (T-8.4, CP-B): needs-approval is an amber
  top edge + headline on the cell, a review block in the module detail with
  threshold context derived from the same constant the queue gates on,
  reject behind a confirmation, and a badge tap-through scope chip instead
  of a filter UI.
- **Whole-window drop target** (T-8.5): one `.onDrop` on the shell root, a
  floating two-state overlay (drag-over / ready), invalid-drop errors inside
  the overlay, zero layout movement; persistent no-gesture add affordances
  in both the empty and populated Library.
- **Model switcher in the chrome** (brought forward into #153, closed out in
  T-8.8): keyed-providers-only menu, stable label width, menu logic pure and
  under test, screenshot-stageable via dev hooks.
- **Runs tab → run inspector** (T-8.6): a shell-owned sheet with entry
  points from source rows, module detail, and the failure toast;
  auto-refreshes during runs; human-formatted durations/timestamps.
- **Status strip decomposed** (T-8.7): persistent MCP chip (green state
  deliberately not clickable), transient processing element, and a run-end
  toast whose "N modules added" is a truthful store diff — engine telemetry
  never becomes a completion claim.
- **Multi-client MCP config writers** (T-8.9, #160): `MCPClientConfigurator`
  detects/statuses/wires/unwires Cursor, Claude Code, Claude Desktop, Codex
  (line-targeted TOML editing), and OpenCode, each shape verified against
  official docs. Idempotent (double-wire byte-stable), preservation-safe,
  malformed-config aborts that never clobber. `make app` bundles `gunk-mcp`
  and wiring installs it to `~/.local/bin/gunk-mcp`, so packaged builds work
  out of the box and configs never point inside the .app bundle.
- **One-click MCP setup** (T-8.10, #161, CP-C): `MCPSetupView` sheet with
  per-client status and Connect / Connect-all, verbatim error surfacing with
  an open-config affordance, Settings per-client toggles, and one shared
  `MCPSetupModel` so chip, sheet, and Settings can never disagree.
- **Cleanup** (T-8.11): the IA-era dead code went down with its tasks
  (`SourcesSectionView`, `ApprovalQueueView`, `RunsView`, `ShellStatusStrip`,
  `BrandDropZone`); this pass removed the last orphan — `MCPStatusProvider`
  and the unrendered `SettingsStatusSnapshot.mcp` item, both superseded by
  the configurator. Feature report bannered as superseded; roadmap checked
  off. Regression pass at 960×600 and default width: Library (hero reflows,
  appbar holds one row), Settings, MCP sheet, drop overlay, toast, run
  inspector, Marketplace — no clipped controls, no layout shifts.

## What slipped

- **Marketplace** is still a branded placeholder — intentionally.
- **Module detail container** is interim: the inline right pane survives
  until the sheet-vs-full-page decision
  ([module-run-v1](../design/explorations/module-run-v1.md)) lands in
  Phase 10. Nothing was pre-built for either container.
- **Filters-in-search** is Mark's design exploration (`[HOLD]`): the appbar
  shipped without filter UI; `BrowseModel`'s filter state is intact and
  tested underneath, and the sources door is a quiet folder icon until that
  design lands.
- **Add module screen** is intentionally blank — the sidebar entry exists,
  Mark designs the screen later.
- **B1** (the 0.7 auto-accept gate is hard-coded; the Settings slider is
  cosmetic) is carried to Phase 11 as planned; **B2** (Dock badge render)
  to Phase 9.
- **Usage telemetry** doesn't exist, so the hero cell ranks by a documented
  fallback (`extractedAt`/agent-ready, then confidence, then name) behind a
  single swappable comparator.
- **Ollama** stays out of the model switcher until its keyless UX is
  designed.

## What we learned

- **Locking decisions in writing works.** The "Decisions locked in (do not
  relitigate)" block and the `[HOLD FOR ME]` gates kept eleven tasks from
  re-opening settled questions; the two scope deviations that did happen
  (model switcher brought forward, appbar filter UI removed) were ratified
  into the doc instead of argued in PRs.
- **A design gate is only half the work.** CP-A approved toolbox-v2, but
  T-8.2/8.3 shipped on the old palette anyway because no task *implemented*
  the approved look — T-8.3b had to be inserted to close the gap. Future
  phases: an approved exploration needs an explicit implementation task
  before structural work builds on top.
- **Truthful claims need a rule, not discipline.** Splitting engine
  telemetry ("N found", allowed mid-run) from store diffs ("N added", the
  only completion claim) fixed a real lie — the strip once showed "14 added"
  on a run that persisted zero.
- **Idempotency as the stated core requirement made filesystem work safe.**
  Byte-stable double-wire, preservation tests, and abort-don't-clobber
  semantics meant pointing the writers at real tool configs was a
  non-event; constructor-injecting every path (home, FileManager,
  binary resolver) kept all of it testable against temp dirs.
- **The `GUNK_DEBUG_*` hook family keeps paying for itself.** Every
  screenshot state this phase — drop overlay phases, toasts, run inspector,
  switcher menus, MCP sheet against a fake home — was stageable in a
  scripted launch without touching real state. New hooks cost a few lines
  each; build them with the feature, not after.
- **One shared observable per concern prevents drift.** The MCP chip, setup
  sheet, and Settings toggles all read one `MCPSetupModel`; "statuses agree
  everywhere" fell out of the architecture instead of being tested into
  existence.

## What we're cutting

- The phase-7 feature report stays as-is behind a superseded banner — pages
  01/02/04/05 document an IA that no longer exists; we are not rewriting
  them.
- `MCPStatusProvider` and the Settings snapshot's single-Cursor MCP item are
  deleted, not deprecated — `MCPClientConfigurator` is the only MCP
  config-reading code path now (the `GUNK_MCP_CONFIG` dev override moved
  with it).
- No second source-list implementation: the sources panel reuses
  `GunkListView` verbatim, and that stays the rule when the filters-in-search
  design restores a richer entry point.
- No speculative module-detail container work ahead of the Phase 10
  decision, and no fake usage numbers ahead of real telemetry.
