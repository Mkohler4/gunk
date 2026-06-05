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
Browse tab's drop zone to add it to `~/.gunk/store.db`. Files and non-file URLs
are rejected. Successful drops post a `gunkInserted` notification so the list
view can refresh immediately.

If an LLM provider and key are configured in Settings, the drop also starts the
Phase 3 processing path: scan the source, build a token-budgeted context, call
the selected LLM with temperature `0`, persist module gunks, and extract
high-confidence modules into `~/.gunk/modules/`.

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
| `source(id:)` | Returns one active source by id. |
| `removeSource(id:)` | Soft-removes a source by setting `removed_at`. |
| `insertGunk(sourceId:name:...)` | Inserts an extracted module linked to a source. |
| `listGunks()` | Returns active module gunks ordered newest-first. |
| `gunk(id:)` | Returns one active module by id. |
| `gunksForSource(sourceId:)` | Returns active modules for one source. |
| `approveGunk(id:)` | Sets `approved_at` for a module. |
| `removeGunk(id:)` | Soft-removes a module by setting `removed_at`. |
| `updateGunkExtraction(id:bundlePath:manifestPath:extractedAt:)` | Records the physical bundle and manifest paths after extraction. |
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
| `listLLMRuns()` | Returns all LLM runs ordered by start time for cost aggregation. |

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

`SourceProcessingRunner` wires the app drop path to the decomposition pipeline.
It reads the selected provider/model/confidence threshold from Settings, reads
provider API keys from Keychain, scans the dropped source, calls
`DecompositionEngine`, extracts high-confidence modules, and reports processing
state back to the Dock/progress UI. Tests inject a fake `LLMClient` and temp
gunk home so the runner never touches the network or real `~/.gunk`.

## Extraction

`Extractor.extract(gunk:)` turns a persisted module into a portable bundle when
its confidence is at least the configured threshold (`0.7` by default).
Bundles are written under `<gunkHome>/modules/<gunk_id>/`; `gunkHome` is
injectable and defaults to `~/.gunk`, so tests use temp directories and never
write to the real home store.

Only rows from `gunk_files` are copied, preserving relative paths. The bundle
also contains:

| File | Purpose |
| --- | --- |
| `gunk.yml` | ADR-0011 manifest with schema version, module metadata, tags, language, purpose, empty dependency lists when unknown, inferred entrypoints, home-relative provenance, detected license, confidence, extraction time, and any redactions. |
| `README.gunk.md` | Generated mini-README from the module purpose, tags, entrypoints, and confidence. |

Extraction repeats secret protection as a defense-in-depth backstop. It skips
secret-named files such as `.env*`, `*.pem`, `*.key`, `id_rsa*`,
`credentials*`, `*.p12`, and `*.pfx`; it scans file contents for known key
patterns such as AWS access key prefixes, OpenAI-style `sk-` prefixes, private
key blocks, and high-entropy credential-looking lines. Matched lines are
redacted or the file is skipped before bytes reach the bundle, and every action
is recorded in `gunk.yml`.

Manifest provenance stores the source path relative to the user home, for
example `~/Documents/project`, and never records git remotes. When the source is
a git repository, only the short local commit hash is included. Top-level source
licenses are detected where possible; restrictive licenses such as GPL are
flagged in the manifest but do not block extraction.

## Processing UI

`ProcessingModel` tracks active source decompositions, exposes
`isProcessing`, per-source progress fractions, and the number of modules found
so far, then drives `DockIconController` to show the processing bin state and a
live badge count. When all active work completes, it reflects the current gunk
count as the idle Dock badge.

## Browse and Approval

The menubar popover opens Browse and Settings. `BrowseModel` loads module
gunks, groups them by tag, attaches their source information for provenance,
and exposes actions to open an extracted bundle, re-classify the source, or
delete the module.

Below-threshold modules that have not been approved or extracted appear in the
approval queue. Approving a module marks `approved_at`, runs extraction through
an injected extractor path, and refreshes the Browse list; rejecting a module
soft-removes it from the store.
