# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added
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
- Deterministic self-containment verification in `gunk-engine` traces and eval reports, checking module imports and exported entrypoints observe-only.
- Optional `gunk-engine` build verification for extracted bundles in eval and CLI trace runs, reporting best-effort pass/skipped metrics without failing decomposition.
- `engine/docs/ARCHITECTURE.md`: stage-by-stage walkthrough of the engine with the verbatim LLM prompts/schemas, survey/refine post-processing filters, quality-gate rules, the `trace.json` schema, and a symptom→fix debugging playbook for analyzing AI output.
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
