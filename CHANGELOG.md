# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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
