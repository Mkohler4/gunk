# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Fixed
- `gunk-engine` no longer returns zero modules on real-world (notably Python) repositories. Three independent decomposition bugs are fixed: (1) Pass-1 survey kept discarding entire capability hypotheses when their `expectedCollaborators` were descriptive names (e.g. `logging`, `utils`) rather than exact repo file paths — unresolved collaborators are now dropped while the hypothesis (defined by its seed files) is retained; (2) self-containment flagged language standard-library / runtime-builtin imports (Python stdlib, Node builtins, `java.*`/`javax.*`, `kotlin.*`, `dart:`) as missing dependencies, failing the imports check — these are now treated as covered via a per-language allowlist; (3) Python symbol extraction never recorded exports, so every Python entrypoint failed the surface/self-containment gates — public top-level `def`/`class` definitions (excluding nested and underscore-prefixed names) are now recorded as exports.

### Changed
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
