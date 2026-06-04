# gunk.app

Native macOS menubar app for gunk.

This package is the Swift / SwiftUI / AppKit half of the product described in
the root README and ADR-0002. For T-2.3 it only contains a menubar skeleton:
an accessory app, an `NSStatusItem`, and a placeholder popover that later tasks
will replace with the drop-zone and list views.

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
and shows a `G` status item with a placeholder popover.

## Store

The app uses [GRDB](https://github.com/groue/GRDB.swift) to write the shared
SQLite store. GRDB was chosen over SQLite.swift for its active development,
ergonomic transaction APIs, and support for both file-backed and in-memory
database queues.

`Store(path:)` creates the parent directory, opens the database in WAL mode,
enables foreign keys, and applies the v0 schema migration. The typed API is:

| Method | Behavior |
| --- | --- |
| `insertGunk(name:path:)` | Inserts a dropped folder and returns its `Gunk`. |
| `listGunks()` | Returns active gunks ordered newest-first. |
| `removeGunk(id:)` | Soft-removes a gunk by setting `removed_at`. |

The Swift v0 schema in `Sources/GunkApp/Store/Schema.swift` is kept
byte-for-byte identical to the MCP source of truth at
`../mcp/src/schema/v0.sql`.
