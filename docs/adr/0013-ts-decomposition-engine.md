# ADR-0013: AI pipeline moves to a TypeScript/Bun engine

- **Status:** Accepted
- **Date:** 2026-06-05
- **Deciders:** Mark Kohler

## Context

The AI decomposition pipeline (ADR-0012) was implemented in Swift inside the
macOS menubar app: `Ingest/`, `Analyze/`, `Decompose/`, `LLM/`, and `Extract/`.
Two problems pushed us to revisit that placement:

1. **Visibility.** The pipeline is a black box at runtime. It computes rich
   signal (survey rationale, expansion closures and exclusions, refiner reject
   reasons, quality-gate decisions) and then discards most of it, exposing only
   a single progress fraction. Debugging quality means rebuilding a macOS app.
2. **Cross-platform.** A Windows app is on the roadmap. Anything written in
   Swift is effectively macOS-only and would have to be re-ported. The pipeline
   itself is a headless batch job (folder in, SQLite rows + extracted bundles
   out) with no UI needs, so binding it to a macOS UI toolkit is the wrong
   coupling.

We already run polyglot: `gunk-mcp` is a TypeScript/Bun process that reads the
same `~/.gunk` SQLite store and ships as a Bun single binary.

## Decision

Move the **entire** AI pipeline into a UI-agnostic `gunk-engine` package
(TypeScript on Bun). The engine owns scanning, static analysis (via
`web-tree-sitter` WASM grammars), capability survey/expansion/refinement,
quality gates, dedupe, extraction, and embeddings. It writes to the shared
`~/.gunk` SQLite store and emits a per-run JSON trace plus NDJSON progress
events on stdout.

The SwiftUI app becomes a thin macOS shell: Dock surface, drop zone, menubar,
Browse/Approval UI, and a new Runs debug panel. It spawns `gunk-engine` as a
subprocess and reads its NDJSON events to drive `ProcessingModel`. A future
Windows shell is a separate native app that drives the same engine.

This supersedes the *implementation language and process location* of
ADR-0012's pipeline. The capability-centric algorithm, the real-module rubric,
the `gunk.yml` manifest spec, secret redaction, and license flagging from
ADR-0011/0012 are retained by reference and ported faithfully.

## Cross-language contract

- **State:** the `~/.gunk` SQLite store (engine writes, app + MCP read).
- **Control/telemetry:** NDJSON events on stdout
  (`progress` / `stage` / `result` / `error`).
- **Trace:** `~/.gunk/runs/<runId>/trace.json` with per-stage timings, counts,
  LLM prompts/responses, hypotheses, expansions, and all decisions.

## Acceptance gate

The existing Swift eval fixtures and baseline scorecard
(`docs/retros/phase-4-eval-baseline.md`) are ported to the engine's test
suite. The engine must meet or beat that baseline before the Swift pipeline is
removed. Migration is strangler-style: the Swift pipeline keeps shipping until
the engine reaches parity, then `SourceProcessingRunner` flips to the engine
and the Swift `Analyze/Ingest/Decompose/Extract/LLM` code is deleted.

## Consequences

- One portable implementation of the "brain" for macOS, Windows, Linux, and CI.
- Fast iterate/eval/trace loop in the language with the strongest LLM tooling.
- Cost: a real port (the static-analysis code is the bulk), a bundled Bun
  binary inside the notarized app, and a stdio IPC boundary.

## Out of scope

- Building the Windows shell now.
- Converging on a single cross-platform UI shell (Tauri/Electron); we keep two
  native shells for now.
