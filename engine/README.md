# gunk-engine

`gunk-engine` is the UI-agnostic, capability-centric decomposition engine for
gunk (see [ADR-0013](../docs/adr/0013-ts-decomposition-engine.md)). It runs as a
headless batch job: point it at a source folder and it scans, statically
analyzes (via `web-tree-sitter`), runs the multi-pass LLM decomposition, applies
quality gates, dedupes, extracts module bundles, and writes everything to the
shared `~/.gunk` SQLite store.

It runs on macOS, Windows, and Linux. Native UI shells (the macOS SwiftUI app
today, a Windows app later) spawn it as a subprocess and read its NDJSON event
stream to drive their UI.

> **Debugging the AI?** See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for a
> stage-by-stage walkthrough, the verbatim LLM prompts/schemas, the quality-gate
> rules, the `trace.json` schema, and a symptom→fix debugging playbook.

## Install

```bash
cd engine
bun install
```

## Scripts

| Script           | What it does                          |
| ---------------- | ------------------------------------- |
| `bun run start`  | Run the engine CLI (`src/index.ts`)   |
| `bun run test`   | Run the vitest suite                  |
| `bun run lint`   | ESLint                                |
| `bun run typecheck` | `tsc --noEmit`                     |
| `bun run build`  | Compile a single binary to `dist/`    |

## CLI

```bash
gunk-engine <folder> --provider <openai|anthropic|ollama> --model <model> \
  [--source-id N] [--db <path>] [--trace] [--json]
```

- `--json` emits NDJSON events on stdout (`progress`, `stage`, `result`,
  `error`) for a host UI to consume.
- `--trace` writes a full per-run trace to `~/.gunk/runs/<runId>/trace.json`.

## Contract

- **State:** the `~/.gunk` SQLite store (engine writes; app + `gunk-mcp` read).
- **Telemetry:** NDJSON events on stdout.
- **Trace:** `~/.gunk/runs/<runId>/trace.json`.

## Layout

```
src/
  models.ts          domain types (ported from Swift)
  contract/          NDJSON event protocol
  trace/             run-trace recorder + observer
  store/             SQLite schema + read/write store
  ingest/            scan, ignore rules, repo map / context builder
  analyze/           symbols, imports, code graph, clustering, fingerprints
  llm/               provider clients + structured output
  decompose/         survey, expand, refine, quality gate, dedupe, pipeline
  extract/           bundle + manifest + redaction + license
  eval/              scorecard + fixtures gate
  index.ts           CLI entrypoint
```
