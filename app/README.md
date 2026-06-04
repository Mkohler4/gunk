# gunk.app

Native macOS menubar app for gunk.

This package is the Swift / SwiftUI / AppKit half of the product described in
the root README and ADR-0002. It runs as a menu bar accessory with an
`NSStatusItem` and a popover for dropping, listing, and removing gunks.

## Requirements

- macOS 14+
- Xcode-bundled Swift toolchain

## Commands

| Command | Description |
| --- | --- |
| `swift build` | Build the `GunkApp` executable. |
| `swift test` | Run the XCTest suite. |
| `make app` | Build and ad-hoc sign `build/gunk.app` for local development. |
| `make rebuild` | Remove build output and recreate `build/gunk.app`. |
| `make clean` | Remove SwiftPM and app bundle build output. |

## Launching Locally

After `make app`, open `build/gunk.app`. The app runs as a menu bar accessory
and shows a `G` status item. Open the popover and drag a folder onto the
drop zone to add it to `~/.gunk/store.db`. Files and non-file URLs are rejected.
Successful drops post a `gunkInserted` notification so the list view can
refresh immediately.

The popover lists active dropped sources below the drop zone in newest-first
order. Each row shows the folder name, middle-truncated path, relative drop
date, and a trash button that soft-removes the source from the shared store.

## Store

The app uses [GRDB](https://github.com/groue/GRDB.swift) to write the shared
SQLite store. GRDB was chosen over SQLite.swift for its active development,
ergonomic transaction APIs, and support for both file-backed and in-memory
database queues.

`Store(path:)` creates the parent directory, opens the database in WAL mode,
enables foreign keys, and applies pending schema migrations. The typed API is:

| Method | Behavior |
| --- | --- |
| `insertSource(name:path:)` | Inserts or restores a dropped folder and returns its `Source`. |
| `listSources()` | Returns active sources ordered newest-first. |
| `removeSource(id:)` | Soft-removes a source by setting `removed_at`. |
| `insertGunk(sourceId:name:...)` | Inserts an extracted module linked to a source. |
| `listGunks()` | Returns active module gunks ordered newest-first. |
| `gunksForSource(sourceId:)` | Returns active modules for one source. |
| `approveGunk(id:)` | Sets `approved_at` for a module. |
| `removeGunk(id:)` | Soft-removes a module by setting `removed_at`. |
| `listTags()` | Returns the seeded classifier tag taxonomy. |
| `addTag(name:)` | Inserts or returns a taxonomy tag. |
| `addGunkTag(gunkId:tagId:confidence:)` | Adds or updates one module tag. |
| `listGunkTags(gunkId:)` | Returns one module's tags ordered by confidence. |
| `addSourceFile(sourceId:relpath:size:)` | Records one scanned file for a source. |
| `filesForSource(sourceId:)` | Returns scanned files for one source ordered by path. |
| `addGunkFile(gunkId:relpath:size:)` | Records one file in a module bundle. |
| `filesForGunk(gunkId:)` | Returns files for one module ordered by path. |
| `recordLLMRun(...)` | Records provider/model token and cost accounting for a source. |
| `llmRunsForSource(sourceId:)` | Returns LLM runs for one source ordered by insertion. |

The Swift schema strings in `Sources/GunkApp/Store/Schema.swift` are kept
byte-for-byte identical to the MCP source of truth under `../mcp/src/schema/`.
`scripts/check-schema-parity.sh` enforces parity for the module schema in CI.

## Source Scanning

`SourceScanner` walks a dropped source before AI decomposition. It skips noisy
directories (`.git`, `node_modules`, `build`, `dist`, `.build`), `.DS_Store`,
binary files, and files over the scanner size cap.

Secret-like files are skipped before they enter the file index or LLM context:
`.env*`, `*.pem`, `*.key`, `id_rsa*`, `credentials*`, `*.p12`, and `*.pfx`.
Projects may add a root `.gunkignore` with gitignore-style entries such as
`Generated.swift`, `ignored-dir/`, or `*.snap`.

`ContextBuilder` turns scanned files into LLM input with a simple token estimate
of `characters / 4`. It emits a file tree first, then prioritized contents
(`README`, project manifests, entrypoints, then smaller source files) until the
configured budget is reached.

## Decomposition

`DecompositionEngine` sends a token-budgeted context to an injected `LLMClient`
using the ADR-0011 structured module schema. It validates module files against
the scanned source file index, filters tags to the seeded taxonomy, clamps
confidence to `0...1`, records token usage in `llm_runs`, and persists module,
tag, and file membership rows.
