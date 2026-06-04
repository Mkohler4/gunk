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

The popover lists active gunks below the drop zone in newest-first order. Each
row shows the folder name, middle-truncated path, relative drop date, and a
trash button that soft-removes the gunk from the shared store.

## Store

The app uses [GRDB](https://github.com/groue/GRDB.swift) to write the shared
SQLite store. GRDB was chosen over SQLite.swift for its active development,
ergonomic transaction APIs, and support for both file-backed and in-memory
database queues.

`Store(path:)` creates the parent directory, opens the database in WAL mode,
enables foreign keys, and applies pending schema migrations. The typed API is:

| Method | Behavior |
| --- | --- |
| `insertGunk(name:path:)` | Inserts a dropped folder and returns its `Gunk`. |
| `listGunks()` | Returns active gunks ordered newest-first. |
| `removeGunk(id:)` | Soft-removes a gunk by setting `removed_at`. |
| `listTags()` | Returns the seeded classifier tag taxonomy. |
| `setGunkTags(gunkId:tags:)` | Replaces one gunk's classifier tags. |
| `listGunkTags(gunkId:)` | Returns one gunk's tags ordered by confidence. |

The Swift schema strings in `Sources/GunkApp/Store/Schema.swift` are kept
byte-for-byte identical to the MCP source of truth under `../mcp/src/schema/`.
