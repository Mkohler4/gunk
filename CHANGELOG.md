# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Changed
- `gunk.app` the sidebar status strip is decomposed into single-purpose
  elements (T-8.7). The old `ShellStatusStrip` was four jobs in one chip —
  idle MCP health, live processing, completion summary, and run failure —
  behind one ambiguous click target. It is replaced by: a **persistent MCP
  chip** at the sidebar bottom with exactly two states — "Agent connected"
  (green, deliberately *not* clickable; hovering shows the config path) and
  "MCP not set up → Connect" (amber, routes to Settings until T-8.10's
  one-click setup lands); a **transient processing element** above it while
  a run is active (source name, linear progress, live "N found" telemetry —
  allowed there, never as a completion claim) that clicks into the Library
  and disappears when idle; and a **run-end toast** floating over the
  detail area's bottom edge (glass — it floats on the controls layer):
  success reads "N modules added · M need review" from the truthful
  store-diff `RunCompletionSummary` with a **View** action (→ Library,
  applying the needs-approval scope only when M > 0 — the same wiring as
  the sidebar badge tap-through), failure reads "Run failed" with an
  **Inspect** action (→ run inspector at the most recent failure, T-8.6's
  existing plumbing). The toast auto-dismisses after 8s, has a manual ×,
  enters on `BrandMotion.settle` so completion lands as feedback, and is
  overlay-only — it can never shift layout (docked bottom-center so it
  cannot overlap the module detail's action row at the 960pt minimum).
  Toast-state derivation and the M > 0 filter rule are pure and under test
  (`ShellRunToastTests`). Dev-only screenshot hook added:
  `GUNK_DEBUG_TOAST=<success|failure>` stages the toast without a live run
  (same family as `GUNK_DEBUG_DROP_OVERLAY`).
- `gunk.app` run traces are now an inspector, not a destination (T-8.6):
  `RunsView` is refactored into `RunInspectorView`, a sheet summoned from
  the places users actually are — a "View runs" affordance on each sources
  panel row, a quiet "Last run" line in the module detail header (kept
  deliberately cheap: the module-run-v1 full page owns run provenance in
  Phase 10), and the status strip's run-failed chip, which now opens the
  inspector at the most recent failed run so the error text is one click
  from the failure signal. Every entry opens *on* something: a context
  (`all` / `source` / `most recent failure`) picks the initial selection,
  under test in `RunInspectorTests`. While a run is active the open
  inspector refreshes traces every 2.5s — the old tab never refreshed
  mid-run. Numbers are formatted for humans: durations as seconds
  ("83.2s", never "83214 ms") and timestamps carry the date only when the
  run wasn't today. Restyled from debug-panel system colors to brand
  tokens (solid surfaces; glass stays on container chrome). Also restores
  the sources panel's lost door: the T-8.3b appbar slimming removed the
  only trigger for `showSourcesPanel`, so the panel was unreachable — a
  quiet folder icon now sits in the appbar's actions cluster (not filter
  UI, so the one-row appbar rule holds). Dev-only screenshot hooks added:
  `GUNK_DEBUG_RUN_INSPECTOR` opens the inspector at launch with a given
  context, and `GUNK_DEBUG_NO_KEYCHAIN` skips the model switcher's
  synchronous Keychain probe, which otherwise blocks an unsigned debug
  binary's first window behind a consent dialog no script can click.

### Fixed
- CI: two bugs in the changed-paths / CHANGELOG gating were failing PRs
  that should pass. `dorny/paths-filter` defaults to OR-ing patterns, so
  `'**'` matched every file, the `'!docs/**'` exclusion was dead code, and
  docs-only PRs were classified as code changes and hit the CHANGELOG gate
  (now `predicate-quantifier: 'every'`). The gate itself diffed against
  `origin/$BASE_REF`, a ref `actions/checkout` can leave pointing at the
  PR's own test-merge commit — an empty diff that failed PRs that *did*
  update the CHANGELOG; it now diffs the test-merge commit against its
  first parent, which is the base tip by construction.
- `gunk.app` the run-completion summary no longer lies about how many
  modules a run added (it could claim "14 modules added" when zero were
  persisted). The old count captured the engine's mid-run `modulesFound`
  telemetry — a *pre-gate candidate* count emitted by the refine stage that
  the accept/reject gates later correct downward — and a `max(old, new)`
  capture with a `> 0` guard kept the inflated number and discarded the
  honest final zero. "N modules added" is now a store diff: the shell
  snapshots `BrowseModel.loadedGunkIds` when a run starts and counts the
  ids that exist after the post-run refresh and didn't before — exactly the
  cells that appear in the grid, needs-approval included, and a real zero
  stays zero. The live "N found" label in the processing strip still shows
  engine telemetry, which is fine for progress but never the completion
  claim. Summary arithmetic extracted into `RunCompletionSummary`'s
  initializer and under test (`RunCompletionSummaryTests`).

### Changed
- `gunk.app` the Library appbar's `provider · model` readout is now a
  working model switcher (T-8.8 brought forward, Mark's direction): a
  toolbox-v2 `.model-menu` popover grouped by provider — uppercase section
  headers, two-line rows (name over a muted subtitle), accent check on the
  selected model — that writes the exact same `llm.provider` / `llm.model`
  storage Settings owns. A provider's models only appear once its API key
  is saved in the Keychain (set up a key in Settings → that provider's
  models become available); local/Ollama models are intentionally absent
  for now. The currently-saved custom model appears as an extra row when
  it is off-catalog, a quiet warning dot marks a selected provider whose
  key has gone missing, and a "Model settings…" item routes to Settings —
  the switcher only selects, key entry stays in Settings. Curated catalog
  under test (`ModelCatalogTests`).
- `gunk.app` the whole window is now the drop target (T-8.5): one `.onDrop`
  on the shell root accepts folder drags over every section — sidebar,
  Library, Marketplace, Settings — and raises the toolbox-v2 full-window
  overlay (dimmed scrim + centered glass card) in a floating layer, so
  nothing in the underlying layout moves during a drag (D15 extended to the
  drag gesture). The card mirrors the mockup's two drag states: dashed
  border while drag-over, solid accent with a "— let go" affordance and
  glow ring once drop-ready; invalid drops (no directories) show "Only
  folders can be added." *inside* the overlay before it dismisses, and a
  successful drop from any section lands in the Library (same feedback as
  Dock drops). `BrandDropZone` and its fixed slot are retired; drops still
  route through the unchanged `DropZoneHandler`, with the new
  `DropPayloadLoader` collecting a drag's file URLs into one batch (under
  test). Drag is never the only door: the empty Library is now a
  click-or-drag zone (a centered glass/dashed panel sharing the overlay's
  visual language, with an accent **Add folder** button) opening the same
  `NSOpenPanel` → `DropZoneHandler` path. The spec's persistent
  "+ Add folder" grid tile was built and then cut on Mark's review — once
  modules exist, drag plus the Add module sidebar entry cover intake.
- `gunk.app` approval folds into the Library (T-8.4): the Approval surface
  is gone — needs-approval is now a state inside the Library. Queued cells
  gain the mockup's 3px amber top edge (`.card.attn::before`,
  `BrandColors.warning`, concentric with the card radius; the green
  selection/arrival ring wins while present). The module detail gains a
  review block above the actions row: confidence with threshold context
  ("62% — below the 70% auto-accept threshold", derived from the same
  `BrowseModel.confidenceThreshold` the queue rule gates on — B1: hard-coded
  0.7 until Phase 11), **Approve** (primary; extracts in place and animates
  the Agent-ready line to its success state with `BrandMotion`, keeping the
  selection even when the active scope hides the cell) and **Reject**
  (destructive; behind a confirmation dialog stating the module is
  permanently deleted). Tapping the sidebar Library badge navigates to the
  Library **and** applies the needs-approval scope, shown as one transient,
  clearable amber chip ("Needs approval (N) ×") in the appbar's flexible
  gap — no persistent filter UI. Approving the last queued module while
  scoped lands on a friendly "All caught up" state and clears the chip.
  `ApprovalQueueView` and the `ApprovalSectionView` wrapper are deleted.

### Fixed
- `gunk-engine` no longer returns zero modules on real-world (notably Python) repositories. Three independent decomposition bugs are fixed: (1) Pass-1 survey kept discarding entire capability hypotheses when their `expectedCollaborators` were descriptive names (e.g. `logging`, `utils`) rather than exact repo file paths — unresolved collaborators are now dropped while the hypothesis (defined by its seed files) is retained; (2) self-containment flagged language standard-library / runtime-builtin imports (Python stdlib, Node builtins, `java.*`/`javax.*`, `kotlin.*`, `dart:`) as missing dependencies, failing the imports check — these are now treated as covered via a per-language allowlist; (3) Python symbol extraction never recorded exports, so every Python entrypoint failed the surface/self-containment gates — public top-level `def`/`class` definitions (excluding nested and underscore-prefixed names) are now recorded as exports.

### Changed
- `gunk.app` appbar vertical-weight pass (T-8.3b follow-up 2, Mark's
  review): the bar, the `Project | Model` segmented (now custom-built to
  the mockup `.seg`, scaled up), and the search field are all taller; the
  search field is capped at the mockup's 300pt max width instead of
  running the whole bar. The trailing slot renders a `provider · model ⌄`
  readout from the Settings `llm.provider`/`llm.model` storage (visual
  only — T-8.8 builds the switching menu). **Add module** moves from the
  appbar to a new sidebar nav row whose screen is intentionally blank for
  now (drag-and-drop and the empty-Library button still intake; the
  folder-picker plumbing is untouched). The sidebar widens from 192pt to
  the mockup's 232pt, with the Library browser-pane minimum relaxed to
  400pt so everything still fits the 960pt minimum window.
- `gunk.app` Library drops the resting "Select a module" placeholder ahead
  of T-8.6 (T-8.3b follow-up 1): with nothing selected the briefing-card
  grid owns the full content width; the interim inline detail pane only
  appears once a module is selected and still goes away entirely when
  T-8.6 moves module detail into the toolbox-v2 centered glass sheet.
- `gunk.app` Library appbar lands the annotated-mockup single row (T-8.3b
  follow-up 2): `Library` + a plain muted count (the pill chip is gone),
  the `Project | Model` segmented, one long search field (now with the
  mockup's hairline border), and the labeled **Add module** button; the
  trailing slot stays reserved for T-8.8's `provider · model` switcher.
  Controls are regular weight at the mockup's `.search input` proportions
  (a small-control first pass read too thin). The sources-panel entry
  point is removed from the appbar for now — it returns with the
  filters-in-search design; the panel and filter state are untouched. At
  the 960pt window minimum the row falls back to the previous two-row
  stack instead of shrinking touch targets. The glass treatment now
  carries the mockup's exact `.glass` box-shadow — a crisp 1pt inner top
  highlight (`inset 0 1px 0 rgba(255,255,255,0.10)`) plus the
  `0 12px 40px -16px rgba(0,0,0,0.6)` drop shadow — the sidebar, which was
  previously un-shadowed and diverged from the HTML, now shares the same
  elevated treatment as the appbar, and the shell's pre-v2 flush glass
  wash (which rimmed the whole modules surface with a hairline) is
  replaced by a solid `backgroundPrimary` window background.
- `gunk.app` Library header pass from Mark's review of T-8.3b (documented as
  follow-ups in the phase-8 task doc): **`Add folder` is now `Add module`**
  (the user adds a capability, not a folder — same intake path), the
  **Filters popover is removed for now** (`BrowseModel` filter state is
  untouched; the filters return layered inside the search bar once that
  design exists), the **search field extends** across the remaining
  controls-row width, and the **`Project | Model` segmented selection drops
  the accent tint** for the neutral system treatment (green stays
  meaning-only). Also documented: the inline detail pane and its resting
  "Select a module" empty state are interim, removed (design only, no
  functionality) when T-8.6 moves module detail into the toolbox-v2 centered
  glass sheet.
- `gunk.app` Library grid restyle (T-8.3b Part B): the dense filter card is
  replaced by the toolbox-v2 controls layer — `Library` title + count chip,
  a **`Project | Model`** grouping segmented control, a search field
  (case-insensitive across name/purpose/tags via the new `filters.query`),
  and a compact **Filters** popover that preserves the old
  source/tag/language/approval *filtering* (the segmented control replaces
  only the old grouping). Modules render as **briefing cards**: one trust
  verdict per cell (`Agent-ready` green / `Needs approval` amber /
  `Not in toolbox` dimmed at 50%), provider-colored corner badge and a
  `via <model>` provenance line derived from `RunTrace` (most recent trace
  per gunk, falling back to its source's trace — no store changes), and tag
  pills. Each group promotes its top-ranked module to a **hero cell**
  spanning two columns (full-width below ~810pt content width, so the 960pt
  window minimum reflows instead of clipping); ranking is agent-ready first,
  then confidence, then name, isolated behind `BrowseModel.heroRank` with a
  `FUTURE: rank by uses/week` seam. No usage numbers are rendered anywhere —
  telemetry does not exist yet. The new `Model` grouping buckets by the
  extracting `provider · model` with an "Unknown model" fallback. Glass is
  confined to the floating controls layer; cards are solid
  `backgroundElevated` on the new `backgroundSecondary` content surface and
  scroll beneath the header.
- `gunk.app` toolbox-v2 palette retune (T-8.3b Part A): `BrandColors` dark
  surfaces move from the green-tinted "ooze" near-black to the neutral
  graphite tokens read from the toolbox-v2 mockup — `#161618` window, a new
  `backgroundSecondary` (`#1d1d20`) content surface, `#27272b` cards, a new
  `backgroundElevatedHover` (`#303036`) step, and a `rgba(48,48,54,0.55)`
  glass tint with a `0.09` hairline. The text ramp goes neutral
  (`#f3f3f5`/`#9b9ba2`/`#6c6c74`), separators become `rgba(255,255,255,0.07)`,
  and `warning`/`danger` retune to `#e7b765`/`#e5786a`. The accent green is
  **unchanged** (`#5fe08c`, green-on-meaning-only); light-mode values are
  re-derived neutral; brand-mark art colors are untouched. New fixed
  provider-accent art colors (Anthropic coral `#D26D43`, OpenAI teal
  `#639FA9`, Google indigo `#33508A`, neutral fallback) ship with a
  case-insensitive `BrandColors.providerAccent(for:)` resolver for the
  toolbox-v2 provider badges.
- `gunk.app` sources fold into the Library (T-8.3): source management is no
  longer a separate tab. The Library header gains a **Sources (N)** button that
  opens a sources sheet reusing the existing source rows verbatim — processing
  progress, the "N modules" affordance (which closes the sheet and applies the
  Library's source filter), failures disclosed on the row, and delete — plus a
  compact **Add folder** button that routes a folder picker (`NSOpenPanel`,
  directories only) through the existing `DropZoneHandler` intake path (no
  duplicated insert/processing logic). Source delete now requires a
  confirmation whose copy matches the verified store behavior — "Removes the
  source from gunk. Its modules remain until you delete them." (`removeSource`
  only stamps `removed_at`; the source's gunks are left intact). The 2s arrival
  highlight moves from the retired Sources surface to the module grid: modules
  created during a run carry the accent treatment for a beat after the run
  completes. `SourcesSectionView` is deleted (`BrandDropZone` stays until T-8.5).
- `gunk.app` shell IA restructure (T-8.2): the five-section navigation
  (Sources/Modules/Approval/Runs/Settings) is replaced by a three-section IA
  — **Library / Marketplace / Settings**. Library renders the existing
  Modules browser as-is (sources and review fold in under later tasks);
  Marketplace is a branded "coming soon" placeholder; Settings is unchanged.
  The app always lands on Library, the Dock-drop handler navigates there, and
  the sidebar processing dot and pending-review count combine onto Library
  (the dot wins while processing, the count otherwise). `SourcesSectionView`,
  `ApprovalSectionView`, and `RunsView` are kept compiling but unrouted for
  dismantling in later tasks.
- `gunk.app` Modules re-skin (T-7.8): module rows keep only the open-bundle
  action while re-run and delete move exclusively to the detail pane;
  selection no longer auto-snaps to the first item when filters change
  (empty selection shows the detail empty state); the detail gains an
  "Agent-ready" status line derived from `extractedAt` plus a compact row
  badge, flipping to "MCP not set up — connect Cursor → Settings" (which
  navigates there) when the shared MCP status reports needs-setup; rows,
  detail sections, and the pinned filter bar are glass cards using
  `TagChip`/`StatusBadge`, the empty states are branded (the browser one
  routes to Sources), and the runability section reads "self-contained for
  AI reuse" vs. "standalone runnable" with branded badges.
- `gunk.app` Sources re-skin (T-7.7): the drop zone is a branded glass
  surface with accent targeted/idle states that holds a constant position
  (the global status block above it is removed — global awareness lives in
  the shell sidebar and status strip); source rows are glass cards that
  carry their own outcome — inline progress and found count while
  processing, an "N modules" affordance that opens Modules filtered to
  that source, and failures disclosed on the affected row; newly dropped
  sources appear immediately with a brief arrival highlight; the empty
  state uses the branded mascot treatment.
- `gunk.app` shell re-skin (T-7.6): the sidebar is a fixed-width glass
  surface (`GlassSidebar` + branded rows, wordmark header) ordered
  Sources → Modules → Approval | Runs → Settings, with an Approval
  pending-review badge and a Sources processing indicator; a persistent
  status strip at the sidebar bottom shows MCP status, run progress, a
  transient completion summary, or a run failure (the MCP config check
  moved to a shared `MCPStatusProvider`, same behavior); windows land on
  Sources when the store is empty and Modules otherwise, keep the title
  "gunk" with the section name in the toolbar, enforce a 960×600 minimum
  (sidebar can no longer collapse into an overlay), default to 1120×720,
  and navigate to Sources when folders arrive via the Dock icon. The
  unused `PopoverView` is removed.
- Phase 7 CP3 task briefs (T-7.6–T-7.9) now carry the concrete structural
  spec from the approved UX architecture instead of a generic doc reference:
  sidebar order/badges + status strip + landing rule + window sizing and
  Dock-drop navigation (T-7.6), constant drop zone + per-source
  progress/outcome rows (T-7.7), action de-duplication + completion refresh +
  Agent-ready placement (T-7.8), and approval context/confirmation, Runs
  cross-links, threshold labeling with the B1 fix, distinct Dock-bin states
  with the B2 badge fix, and the menubar glyph (T-7.9).
- Phase 7 plan now includes a product UX pass (T-7.4b, gate CP2.5) covering
  information architecture and placement — landing logic, sidebar
  order/badges, status and drop-feedback placement — and the CP3 re-skin
  tasks now implement the approved UX architecture alongside the visual
  re-skin instead of being visual-only.
- `gunk.app` now requires macOS 26: the package builds with the Xcode 26
  toolchain (swift-tools 6.2, `.macOS(.v26)`), the app bundle declares
  `LSMinimumSystemVersion` 26.0, and the App CI job runs on the `macos-26`
  image so real Liquid Glass `glassEffect` APIs are available.
- `gunk.app` packaging now verifies the built app bundle after `make app`,
  keeps ad-hoc signing as the default, and documents the Developer ID,
  notarization, and manual update path.
- `gunk.app` approval and module rows now expose source re-run actions that
  call the shared engine runner, and Approval queue actions keep the Browse
  model refreshed after approve/reject/re-run decisions.
- `gunk.app` Modules now behaves as a real module browser: users can group by
  live tags, source, language, or approval state; filter by source/tag/language
  and approval state; and scan rows with purpose, tags, source, confidence, and
  extraction status.
- `gunk.app` now launches as a regular Dock/window app with a SwiftUI sidebar
  shell for Sources, Modules, Runs, Settings, and Approval; the status item now
  opens the main window instead of presenting the workspace in a popover.
- ADR-0002 (stack and runtime): record the stack options not yet evaluated (Node.js, Deno, Python, alternative local stores) as deliberately deferred, each with a revisit trigger, plus a per-phase plan to reconsider them.

### Added
- `gunk.app` app icon and brand wordmark (T-7.5): a complete
  `AppIcon.appiconset` plus a regenerated `app/AppIcon.icns`, both rendered
  from the shared `BrandMark` Ooze centered on a dark glass tile via a new
  `make icon` target (dev-only `GUNK_RENDER_APPICON`/`GUNK_RENDER_DOCKBIN`
  export modes — no new shipping UI); the runtime Dock states drop the
  trash-can metaphor and reuse the same tile (muted mark when empty, accent
  glow while processing, count badge unchanged); and `BrandWordmark` (mark +
  "gunk" lockup, sidebar and hero styles with a `BrandMotion`-driven reveal),
  now shown in the sidebar header and the launch-failure view.
- UX architecture doc (`docs/design/ux-architecture.md`, T-7.4b): the CP2.5
  contract for the phase-7 re-skins — surface inventory of every screen plus
  menubar item, Dock bin, and window chrome; core-journey audit findings
  (silent processing/completion, invisible approval queue, unsurfaced MCP
  payoff, Dock-bin state assets that are byte-identical); per-surface
  placement proposals; and cross-cutting rules for landing, sidebar
  order/badges, global status, drop-gesture feedback, and window sizing.
- `gunk.app` component gallery (`Design/ComponentGalleryView.swift`): a dev-only,
  glass-backed CP2 review surface rendering every brand token (palette, type
  scale, spacing/radius, motion, mark) and every T-7.3 component on one
  scrollable screen with an in-window Light/Dark toggle. Gated behind
  `GUNK_DESIGN_GALLERY=1` (Debug menu + auto-open), so it is absent from
  normal launches and packaged builds.
- `gunk.app` Liquid Glass component library (`Design/Components/`): `GlassCard`,
  `GlassSidebar`, `BrandButton` (primary / secondary / destructive / icon styles
  with hover and press motion), `TagChip`, `StatusBadge`, `SectionHeader`, and a
  branded `EmptyStateView` built on the Ooze mark — all token-driven with light
  and dark previews, plus new `BrandMetrics.Control` tokens for hover, press,
  tinted-fill, and disabled control states.
- `gunk.app` brand and design-system foundation (`Design/`): semantic color
  tokens with Light + Dark color sets, the Space Grotesk / JetBrains Mono type
  scale, spacing/radius/glass metrics, an adaptive Liquid Glass material, named
  motion tokens from the brand animation spec, and the Ooze brand mark as a
  native SwiftUI view with its breathe/blink idle loop.
- `gunk.app` Settings now surfaces provider/model, API-key, local store, engine
  binary, and Cursor MCP config status with setup guidance when something is
  missing.
- `gunk.app` Modules now has a module detail pane that shows owned files,
  shared dependencies, entrypoints, bundle path, self-containment for AI reuse,
  and optional standalone build verification when trace data is available.
- `gunk-engine` now derives module tags dynamically (hybrid): the refine pass treats the seeded taxonomy as a suggested vocabulary but lets the model mint new domain tags, which are normalized to lowercase kebab-case (deduped, capped at 6) and auto-created in the `tags` table on persist instead of being silently dropped. No schema change; MCP and the app Browse view pick up the richer tags automatically.
- `gunk-engine`: a cross-platform (macOS/Windows/Linux) TypeScript/Bun decomposition engine that owns the entire AI pipeline (scan, web-tree-sitter symbol extraction, code graph, fingerprints, repo map, capability survey/expansion/refinement, quality gates, dedupe, extraction, embeddings), writes the shared `~/.gunk` SQLite store, and emits NDJSON progress events plus per-run JSON traces to `~/.gunk/runs/<runId>/trace.json`.
- Engine eval gate ported to `bun test`, holding the capability-centric pipeline at or above the Phase 4 baseline scorecard (perfect file precision/recall and zero trivial-module false positives on both fixtures).
- Multi-language engine eval fixtures for Phase 5: Flutter/Dart, Kotlin/Android, Java service, mixed monorepo, and a large repo fixture with golden labels and negative traps.
- Per-stage engine signal metrics for Phase 5 evals, including parse coverage, graph edge density, survey hypothesis counts, expansion closure sizes, and quality-gate rejection histograms.
- Offline replay eval harness and CLI report for deterministic, key-free engine evals in CI.
- Dart tree-sitter symbol extraction in `gunk-engine`, covering classes, methods, functions, top-level declarations, imports, and public exports for Flutter fixtures.
- Dart import resolution in `gunk-engine`, linking relative, lib-relative, and package-self imports to in-repo files while keeping SDK and third-party `package:` imports external.
- Pubspec and Gradle manifest parsing plus mobile dependency lexicon hints for Flutter/Android capability fingerprints.
- Kotlin and Java tree-sitter symbol extraction plus package-path import resolution for Android/JVM fixtures.
- Generalized non-web module surface detection so public APIs and capability-hint anchors can pass quality gates without HTTP routes.
- Flutter replay eval coverage now requires accepted mobile modules, with `mobile` seeded as an allowed module tag.
- `gunk-engine` quality gates now consume deterministic self-containment results: failures downgrade or reject modules, while verified modules with real entrypoints can survive weak cohesion without bypassing trivial-module traps.
- Engine eval reports now show cohesion, surface, and classification proxy agreement against deterministic self-containment, and the surface gate rejects claimed entrypoints that verification proves are not real.
- Large-repo eval coverage now uses deterministic repo-map chunking with map-reduce survey, preserving capabilities that were previously hidden by repo-map truncation.
- Survey prompting now calls out JVM/Android feature-package patterns, lifting the Kotlin Android replay fixture to accepted mobile modules without new trap false positives.
- Phase 5 eval gate closure: Java service and mixed-monorepo replay fixtures now have enforced score floors, all multi-language fixtures assert zero trap false positives, and `docs/retros/phase-5.md` records the final scorecards.
- Deterministic self-containment verification in `gunk-engine` traces and eval reports, checking module imports and exported entrypoints before quality-gate decisions.
- Optional `gunk-engine` build verification for extracted bundles in eval and CLI trace runs, reporting best-effort pass/skipped metrics without failing decomposition.
- `engine/docs/ARCHITECTURE.md`: stage-by-stage walkthrough of the engine with the verbatim LLM prompts/schemas, survey/refine post-processing filters, quality-gate rules, the `trace.json` schema, and a symptom→fix debugging playbook for analyzing AI output.
- ADR-0015 and Phase 6 task plan: `gunk.app` is now documented as a full macOS app first, with menubar controls secondary and one-click AI-tool wiring moved behind the app shell.
- `gunk.app` Runs debug panel that reads `~/.gunk/runs`, surfacing per-run stages, timings, counts, and accept/approve/reject summaries.
- ADR-0013 (the AI pipeline moves to a TS/Bun engine; the SwiftUI app becomes a thin macOS shell).
- ADR-0014 (multi-language coverage and verification feedback for Phase 5).
- CI: `engine` (lint/typecheck/test + eval gate) and `engine-binary` (self-contained single-binary smoke test with embedded tree-sitter grammars) jobs; engine schema kept byte-for-byte in parity with MCP.
- OpenAI embedding support for app indexing and MCP semantic query search, with Ollama still available as the local fallback.

### Changed
- `gunk.app` `SourceProcessingRunner` now spawns the bundled `gunk-engine` binary and maps its NDJSON events onto `ProcessingModel` instead of running an in-process Swift pipeline; `make app` builds and bundles the engine into the `.app` Resources.

### Removed
- The in-process Swift AI pipeline (`Analyze/`, AI `Decompose/` stages, ingest scanning/context, `Search/EmbeddingIndex`) and its SwiftPM tree-sitter grammar dependencies, now superseded by `gunk-engine`. The Swift `Extract/`, `SourceDetector`, LLM clients, and store remain for the shell's approval-extract, folder detection, and connection-test features.
- Dead Swift `Store` accessors and models orphaned by the engine port: `addSourceFile`/`filesForSource` (+ `SourceFile`), `llmRunsForSource`/`listLLMRuns`, and the gunk-cluster membership reader/writer (+ `GunkClusterMembership`); these tables are now written by the engine and read by MCP. Also dropped the unused test-bundle `Fixtures` (the eval fixtures live in `engine/test/fixtures`).
- Cross-source module dedup with canonical cluster links, variant counts, and MCP exposure for list/get/search.
- Local semantic search for extracted gunks with schema v3 `gunk_embeddings`, app-side embedding indexing, and MCP cosine ranking with substring fallback.
- `gunk.app` eval gate proving the capability-centric pipeline beats the Phase 3 baseline and emits zero trivial-module false positives.
- `gunk.app` capability-centric decomposition pipeline orchestrating static analysis, survey, expansion, refinement, quality gates, persistence, approval routing, extraction, and progress updates.
- `gunk.app` real-module quality gates for trivial files, surfaces, cohesion, confidence, and duplicate overlap.
- `gunk.app` per-capability refinement pass with closure-bounded membership validation and per-candidate `llm_runs`.
- `gunk.app` deterministic capability closure expansion with shared dependency detection.
- `gunk.app` capability survey pass with rubric-grounded structured hypotheses and `llm_runs` recording.
- `gunk.app` structural repo-map context builder with symbols, edges, clusters, fingerprints, and budgeted snippets.
- `gunk.app` capability fingerprinting for dependency anchors, route surfaces, env/config reads, naming tokens, and lexicon hints.
- `gunk.app` code graph builder, import resolver, closure queries, and clustering metrics for Phase 4.
- `gunk.app` tree-sitter symbol extraction for JS/TS, Python, Swift, Go, plus unknown-language fallback.
- Decomposition eval harness with golden fixtures, negative traps, and a Phase 3 baseline scorecard.
- ADR-0012 (capability-centric decomposition architecture and real-module rubric).
- `gunk.app` drop-to-decompose demo path with visible drop target, Settings paste support, and live processing errors.
- MCP tools v1: module-level `list_gunks`, `list_sources`, `search_gunks`, bundle-returning `get_gunk`.
- `gunk-mcp` store reader v1 (sources, modules, tags, search).
- `gunk.app` Browse view, re-classify, and approval queue.
- `gunk.app` cost meter + Dock processing/progress UI.
- `gunk.app` physical extractor (bundle + gunk.yml + mini-README + secret redaction + license flagging).
- `gunk.app` AI decomposition engine (project -> tagged modules).
- `gunk.app` source scanner + token-budgeted context builder (secret-aware ignore rules).
- `gunk.app` pluggable LLM client (OpenAI, Anthropic, Ollama) + settings.
- `gunk.app` Dock drop handling + source detection.
- `gunk.app` Dock recycling-bin icon with empty/full/processing states.
- ADR-0011 (AI decomposition pipeline + gunk.yml spec).
- `gunk.app` store v2 (sources, module gunks, tags, files, llm_runs) and schema parity CI.
- SQLite schema v2 (sources + module-level gunks, tags, gunk_files, llm_runs) and v0/v1 to v2 migration.
- ADR-0008 (gunks are modules), ADR-0009 (Dock recycling-bin surface).
- SQLite schema v1 tag taxonomy (`tags`, `gunk_tags`) and shared store helpers.
- CI hardening: secret scan, PR-title lint, CHANGELOG gate.
- Cursor MCP integration docs.
- Single-binary build of `gunk-mcp` via Bun.
- `gunk.app` list view + delete.
- `gunk.app` drop zone (drag a folder, it lands in the store).
- `gunk.app` store writer (insert/list/remove + migrations).
- MCP tool `get_gunk` (returns README + shallow tree).
- MCP tool `list_gunks`.
- MCP server skeleton (stdio transport, tools capability).
- `gunk-mcp` store reader (`listGunks`, `getGunk`, `getGunkFiles`).
- SQLite schema v0 (`gunks`, `files`, `schema_version`) and idempotent
  migration runner.
- GitHub Actions CI workflow (mcp + app jobs).
- `gunk.app` Swift Package scaffold (menubar app skeleton).
- Monorepo skeleton (`mcp/`, `app/`), `.editorconfig`, `.tool-versions`,
  GitHub PR + issue templates.
- Initial repository scaffold: `README.md`, `LICENSE` (MIT), `CHANGELOG.md`, `.gitignore`.
- `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1).
- ADR-0001: "What is gunk?" — locks the product thesis (local-only, drop-in,
  Swift macOS app + short-lived TypeScript MCP server, no daemon).
- ADR-0002: "Stack and runtime" — Swift/SwiftUI for `gunk.app`, TypeScript on
  Bun for `gunk-mcp`, shared SQLite store at `~/.gunk/store.db`. No daemon,
  no IPC socket.
- ADR-0003: "Ambient over invoked" — locks the principle that the happy-path
  user types zero commands. The CLI is plumbing, not product.
- ADR-0004: "Drag-in over file-watch" — locks the principle that gunk only
  knows about folders the user explicitly drops on the app. No filesystem
  watching, no Full Disk Access, no path config in v0.
- ADR-0005: "Monorepo layout" — both packages (`mcp/` for TypeScript,
  `app/` for Swift) live in this repo. One CHANGELOG, one set of ADRs,
  one CI workflow.
- `docs/tasks/README.md` — format and conventions for structured task
  specs designed for autonomous agent execution.
- `docs/tasks/codex-prompt.md` — exact prompt template to invoke Codex
  on a single task with proper guard rails.
- `docs/tasks/phase-2-walking-skeleton.md` — 15 ordered, individually
  testable tasks (T-2.1 through T-2.15) covering the Phase 2 walking
  skeleton: monorepo scaffolding, CI, SQLite schema v0, store layers,
  MCP server with `list_gunks` + `get_gunk`, drop-zone UI, list view,
  single-binary build, Cursor integration docs, end-to-end smoke test.
- `docs/roadmap.md` — 9-week phased plan, walking-skeleton-first.
- Conventional Commits enforcement (commitlint + husky), GitHub Project board.
- `web/` — marketing landing page (Next.js App Router + TypeScript), ported
  from the `gunk.html` prototype: one minimal page with the "Reinventing the
  trash can." hero, problem/how-it-works/before-after sections, dark mode,
  and a placeholder email signup.
- `gunk-mcp` package scaffold (Bun + TypeScript + Vitest + ESLint +
  Prettier).

### Changed
- Pivoted from a CLI-first product framing to an ambient/background system
  before any code was written. README and ADR-0001 rewritten to match.
- Removed all references to a public/shared marketplace from v0 scope. Gunk
  is local-only at launch.
- Dropped the long-lived `gunkd` daemon from the architecture. The MCP
  server is now spawned by AI tools using the standard MCP stdio pattern,
  and the macOS app does ingestion/classification work in-process. Two
  processes total, sharing a SQLite store. (See ADR-0002.)
- Dropped the filesystem-watching design. Gunk now ingests only folders the
  user explicitly drops on the app. (See ADR-0004.)

[Unreleased]: https://github.com/Mkohler4/gunk/commits/main
