# Phase 2 — Walking skeleton

> The dumbest possible end-to-end loop. When this phase ships, you can drag
> one of your old repos onto `gunk.app`, open Cursor, and Cursor's agent can
> reference that folder via `gunk-mcp`. **No classification yet — that's
> Phase 3.** The point is the loop is real and demoable.

**Demo at end of phase:**

1. Launch `gunk.app`. The menubar icon appears.
2. Click the icon. A drop zone window opens.
3. Drag the folder of an old project onto the window. It appears in the list.
4. Open Cursor (already configured with `gunk-mcp`).
5. In Cursor, ask: "What gunks do I have? Show me the README of the first one."
6. Cursor's agent calls `gunk-mcp`, gets the list, fetches the README, replies with the right content.

If that works end-to-end, Phase 2 is done.

---

## Dependency graph

```
T-2.1  monorepo skeleton
   │
   ├──► T-2.2  gunk-mcp scaffold ──┐
   │                                │
   ├──► T-2.3  gunk.app scaffold ──┤
   │                                │
   └──► T-2.4  GitHub Actions CI ◄─┘
                │
                ▼
         T-2.5  SQLite schema v0  (+ ADR-0006)
                │
        ┌───────┴────────┐
        ▼                ▼
T-2.6 mcp store    T-2.10 app store
       reader            writer
        │                ▼
        ▼          T-2.11 drop zone view
T-2.7 MCP server         │
       skeleton          ▼
        │          T-2.12 list view + delete
        ▼
T-2.8 list_gunks tool
        │
        ▼
T-2.9 get_gunk tool
        │
        ▼
T-2.13 gunk-mcp single binary
        │
        ▼
T-2.14 Cursor MCP integration docs
        │
        ▼
T-2.15 End-to-end smoke + retro
```

Tasks in the same row of the graph can be parallelized. Default to
sequential unless capacity demands otherwise.

---

## Phase complete checklist

Phase 2 ships when **every** box is ticked:

- [ ] All 15 tasks merged to `main`
- [ ] CI green on `main`
- [ ] `gunk.app` launches, accepts a folder drop, lists it
- [ ] `gunk-mcp` single-binary built and runnable
- [ ] Cursor (configured per `docs/integration/cursor.md`) can call
      `list_gunks` and `get_gunk` against a real store
- [ ] Demo (see top of this file) recorded as a ≤90s screen capture
- [ ] Friday release thread posted with the recording

---

## Tasks

### T-2.1 — Monorepo skeleton

**Status:** Not started
**Owner:** Codex

#### Goal
Create the empty `mcp/` and `app/` subdirectories at the repo root, plus
shared toolchain config files. No package code yet.

#### Why
Per [ADR-0005](../adr/0005-monorepo-layout.md), both packages live in this
repo. We need the directory structure and shared editor/toolchain config
in place before either package can scaffold.

#### Prerequisites
None.

#### Files
- `mcp/.gitkeep`
- `app/.gitkeep`
- `.editorconfig` (root)
- `.tool-versions` (root) — Bun version pin and Swift version note
- `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/ISSUE_TEMPLATE/bug_report.md`
- `.github/ISSUE_TEMPLATE/feature_request.md`

#### Execution steps
1. Create `mcp/` and `app/` directories with `.gitkeep` files.
2. Write `.editorconfig` with sane defaults (LF, UTF-8, 2-space TS, tabs
   off, trim trailing whitespace, final newline).
3. Write `.tool-versions` pinning Bun (latest stable) and noting Swift
   toolchain via Xcode-bundled.
4. Write `.github/PULL_REQUEST_TEMPLATE.md` with sections: Summary,
   Linked task ID, Definition of done (copy from spec), Testing
   evidence, Out-of-scope observations.
5. Write `.github/ISSUE_TEMPLATE/bug_report.md` and
   `feature_request.md` with minimal structured fields.

#### MCP touchpoints
None — pure structure.

#### Tests required
None — no executable code.

#### Execution objective
`ls mcp/ app/` shows the empty directories. `git status` shows the
template files staged.

#### Definition of done
- [ ] All listed files exist
- [ ] `CHANGELOG.md` `[Unreleased] / Added`: "Monorepo skeleton (`mcp/`, `app/`), `.editorconfig`, `.tool-versions`, GitHub PR + issue templates"
- [ ] `docs/roadmap.md` Phase 1: tick "Bun + TypeScript scaffold" precondition (the directory)
- [ ] PR title: `chore: monorepo skeleton + PR/issue templates`
- [ ] PR body links to T-2.1

---

### T-2.2 — `gunk-mcp` Bun + TypeScript scaffold

**Status:** Not started
**Owner:** Codex

#### Goal
Initialize the `mcp/` package with Bun + TypeScript + Vitest + ESLint +
Prettier, plus a smoke "hello world" script and one passing test.

#### Why
Per ADR-0002, `gunk-mcp` is a TypeScript package on Bun. We want a
working `bun test` and a working `bun run start` before any real logic
exists, so every later task can ride on that infrastructure.

#### Prerequisites
- T-2.1 (monorepo skeleton)

#### Files
- `mcp/package.json`
- `mcp/tsconfig.json`
- `mcp/.eslintrc.cjs` (or `eslint.config.js`)
- `mcp/.prettierrc`
- `mcp/vitest.config.ts`
- `mcp/src/index.ts` (entry, prints `gunk-mcp <version>` and exits 0)
- `mcp/test/smoke.test.ts`
- `mcp/README.md`

#### Execution steps
1. `cd mcp && bun init -y`, then customize `package.json`: name
   `gunk-mcp`, version `0.0.1`, type `module`, scripts: `start`,
   `test`, `lint`, `typecheck`, `format`, `build`.
2. Configure `tsconfig.json` for strict mode, ES2022 target, NodeNext
   module resolution, `bun-types` lib.
3. Add ESLint + Prettier with conservative defaults (no opinionated
   rules beyond style; we'll tighten later if needed).
4. Add Vitest. Configure to run files under `mcp/test/`.
5. Implement `mcp/src/index.ts`: read `package.json` version, print
   `gunk-mcp <version>` to stderr, exit 0.
6. Write `mcp/test/smoke.test.ts`: import `index.ts`'s exported main
   function (refactor entry to export it) and assert it returns
   without throwing.
7. Write `mcp/README.md`: package description, install, scripts table,
   pointer back to root README and ADR-0002.

#### MCP touchpoints
None yet — package scaffold only. T-2.7 adds the actual MCP server.

#### Tests required
- [ ] `mcp/test/smoke.test.ts > main exits 0`

#### Execution objective
`cd mcp && bun install && bun test` passes. `bun run start` prints
`gunk-mcp 0.0.1` and exits 0. `bun run lint` and `bun run typecheck`
pass.

#### Definition of done
- [ ] All scripts (`test`, `lint`, `typecheck`, `format`, `build`) work
- [ ] Smoke test passes
- [ ] `mcp/README.md` populated
- [ ] `CHANGELOG.md` `[Unreleased] / Added`: "`gunk-mcp` package scaffold (Bun + TypeScript + Vitest + ESLint + Prettier)"
- [ ] `docs/roadmap.md` Phase 1: tick "Bun + TypeScript scaffold for `gunk-mcp`"
- [ ] PR title: `feat(mcp): scaffold gunk-mcp package`
- [ ] PR body links to T-2.2

---

### T-2.3 — `gunk.app` Swift Package scaffold

**Status:** Not started
**Owner:** Codex

#### Goal
Initialize the `app/` package as a Swift Package with a SwiftUI menubar
app skeleton (NSStatusItem + popover with placeholder text), plus one
passing XCTest.

#### Why
Per ADR-0002, `gunk.app` is Swift/SwiftUI on macOS 14+. We want a
buildable `.app` bundle and a working `swift test` before any real UI
logic exists.

#### Prerequisites
- T-2.1 (monorepo skeleton)

#### Files
- `app/Package.swift`
- `app/Sources/GunkApp/GunkAppMain.swift`
- `app/Sources/GunkApp/AppDelegate.swift`
- `app/Sources/GunkApp/MenubarController.swift`
- `app/Sources/GunkApp/Views/PopoverView.swift`
- `app/Tests/GunkAppTests/SmokeTests.swift`
- `app/Makefile` (mirroring AICockpit's `make app` workflow at minimum)
- `app/README.md`

#### Execution steps
1. Write `Package.swift` declaring an executable target `GunkApp`,
   macOS 14+ platform, no external dependencies yet.
2. Implement `GunkAppMain.swift` as the `@main` entry; install
   `AppDelegate`.
3. Implement `AppDelegate` with `NSApplicationDelegate`, hide dock
   icon (`LSUIElement = true` via Info.plist or programmatic
   activation policy `.accessory`), instantiate `MenubarController`.
4. Implement `MenubarController` with an `NSStatusItem` showing a
   simple symbol or "G" text, and an `NSPopover` hosting
   `PopoverView`.
5. Implement `PopoverView` (SwiftUI) with placeholder text:
   "Drop folders here (T-2.11)" — this is a deliberate marker that
   later tasks will replace.
6. Write `SmokeTests.swift` — XCTest verifying the AppDelegate can be
   instantiated without crashing in a headless context.
7. Write `Makefile` mirroring AICockpit's: `swift build`,
   `swift test`, `make app` (codesign + bundle), `make rebuild`.
8. Write `app/README.md` describing build commands and dependencies.

#### MCP touchpoints
None — UI scaffolding only.

#### Tests required
- [ ] `SmokeTests.testAppDelegateInitializes`

#### Execution objective
`cd app && swift build && swift test` succeeds. `make app` produces
a runnable (unsigned-for-dev) `.app` whose menubar icon appears when
launched.

#### Definition of done
- [ ] Builds clean with `swift build` (zero warnings)
- [ ] `swift test` passes
- [ ] `make app` produces `app/build/gunk.app`
- [ ] Menubar icon appears on launch
- [ ] `app/README.md` populated
- [ ] `CHANGELOG.md` `[Unreleased] / Added`: "`gunk.app` Swift Package scaffold (menubar app skeleton)"
- [ ] `docs/roadmap.md` Phase 1: tick "Swift Package scaffold for `gunk.app`"
- [ ] PR title: `feat(app): scaffold gunk.app package`
- [ ] PR body links to T-2.3

---

### T-2.4 — GitHub Actions CI

**Status:** Not started
**Owner:** Codex

#### Goal
Add a single CI workflow that runs both packages' lint + typecheck +
test on every PR and push to `main`.

#### Why
Per `CONTRIBUTING.md`, "CI must be green" is a merge gate. We need it
to actually run, today, not someday.

#### Prerequisites
- T-2.2 (`mcp` package has scripts to call)
- T-2.3 (`app` package has tests to run)

#### Files
- `.github/workflows/ci.yml`

#### Execution steps
1. Write `.github/workflows/ci.yml` with two parallel jobs:
   - `mcp`: ubuntu-latest, sets up Bun via `oven-sh/setup-bun`, runs
     `bun install`, `bun run lint`, `bun run typecheck`, `bun test`.
   - `app`: macos-14, runs `xcodebuild -version`, `swift --version`,
     `cd app && swift build && swift test`.
2. Add path filters so PRs touching only `docs/` skip the build jobs
   (but still run a quick "no broken links" check — optional in this
   task; defer if hard).
3. Add a CI status badge to the root `README.md`.

#### MCP touchpoints
None directly; CI gates every future MCP change.

#### Tests required
- [ ] CI run on a deliberate failing PR shows red (manual verification
      via a throwaway PR; revert before merging T-2.4).
- [ ] CI run on the T-2.4 PR shows green.

#### Execution objective
Opening a PR that introduces a TS or Swift compile error triggers a
red CI status. Opening a PR that passes both suites shows green.

#### Definition of done
- [ ] CI workflow exists and runs on every PR
- [ ] Both `mcp` and `app` jobs pass on `main`
- [ ] Status badge in `README.md`
- [ ] `CHANGELOG.md` `[Unreleased] / Added`: "GitHub Actions CI workflow (mcp + app jobs)"
- [ ] `docs/roadmap.md` Phase 1: tick "CI: GitHub Actions running lint + typecheck + test on every PR"
- [ ] PR title: `ci: add lint + typecheck + test workflow for mcp and app`
- [ ] PR body links to T-2.4

---

### T-2.5 — SQLite schema v0

**Status:** Not started
**Owner:** Codex

#### Goal
Define the SQLite schema that both `gunk-mcp` and `gunk.app` share.
Ship an idempotent migration runner in the `mcp/` package and ratify
the schema as ADR-0006.

#### Why
Per ADR-0002, the app and MCP server communicate exclusively via the
shared SQLite store. The schema is their contract. Without versioning
and explicit migrations, drift is the most likely class of bug.

#### Prerequisites
- T-2.2 (mcp scaffold)

#### Files
- `mcp/src/schema/v0.sql`
- `mcp/src/schema/migrate.ts`
- `mcp/src/schema/index.ts`
- `mcp/test/schema.test.ts`
- `docs/adr/0006-sqlite-schema-v0.md` (NEW)
- `docs/adr/README.md` (update index)
- `mcp/README.md` (add Schema section)

#### Execution steps
1. Define `v0.sql` with three tables:
   - `schema_version (version INTEGER PRIMARY KEY, applied_at INTEGER NOT NULL)`
   - `gunks (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, path TEXT NOT NULL UNIQUE, dropped_at INTEGER NOT NULL, removed_at INTEGER)`
   - `files (id INTEGER PRIMARY KEY AUTOINCREMENT, gunk_id INTEGER NOT NULL REFERENCES gunks(id) ON DELETE CASCADE, relpath TEXT NOT NULL, size INTEGER, UNIQUE(gunk_id, relpath))`
2. Implement `migrate.ts`: exports `runMigrations(db: Database): { from: number; to: number }`. Reads current version from `schema_version`, applies `v0.sql` if `version < 0` (treating version 0 as "v0 applied"). Records the new version with `applied_at = unix epoch ms`.
3. Wrap a `bun:sqlite` opener in `index.ts` that takes a path, opens with WAL mode, runs migrations, returns the `Database` handle.
4. Tests:
   - migrating a fresh in-memory DB creates all expected tables (verify via `sqlite_master` query)
   - running migrations twice is a no-op (no error, no extra `schema_version` rows)
   - schema version is recorded with a sane timestamp (>0, <= now)
5. Write ADR-0006 (Status: Accepted) capturing the schema. Include the SQL verbatim. Link from ADRs index.
6. Update `mcp/README.md` with a "Schema (v0)" section listing each table and column.

#### MCP touchpoints
This is the data MCP will serve. Every later MCP tool reads from this
schema. No tools added in this task — purely foundational.

#### Tests required
- [ ] `mcp/test/schema.test.ts > runMigrations creates v0 tables`
- [ ] `mcp/test/schema.test.ts > runMigrations is idempotent`
- [ ] `mcp/test/schema.test.ts > runMigrations records schema_version with a sane timestamp`

#### Execution objective
`cd mcp && bun test test/schema.test.ts` passes all three tests. A
fresh `~/.gunk/store.db` opened via `index.ts` has all three tables.

#### Definition of done
- [ ] All tests pass locally and in CI
- [ ] `mcp/src/schema/v0.sql` exists and matches the spec
- [ ] `mcp/src/schema/migrate.ts` is idempotent
- [ ] `mcp/src/schema/index.ts` opens with WAL mode
- [ ] `mcp/README.md` documents each table
- [ ] `docs/adr/0006-sqlite-schema-v0.md` exists, status Accepted, linked from index
- [ ] `CHANGELOG.md` `[Unreleased] / Added`: "SQLite schema v0 (`gunks`, `files`, `schema_version`) and idempotent migration runner"
- [ ] `docs/roadmap.md` Phase 2: tick "SQLite schema v0"
---

### T-2.6 — `gunk-mcp` store reader

**Status:** Not started
**Owner:** Codex

#### Goal
Implement a typed read API over the SQLite store: `listGunks()` and
`getGunk(id)` returning typed records.

#### Why
The MCP tools (T-2.8, T-2.9) shouldn't talk to SQLite directly; they
should call into a thin store layer that's independently testable.

#### Prerequisites
- T-2.5 (schema)

#### Files
- `mcp/src/store/index.ts`
- `mcp/src/store/types.ts`
- `mcp/test/store.test.ts`

#### Execution steps
1. Define `Gunk` and `GunkFile` types in `types.ts` matching the
   schema columns plus camelCase field names.
2. Implement `listGunks(db): Gunk[]` returning rows where
   `removed_at IS NULL`, ordered by `dropped_at DESC`.
3. Implement `getGunk(db, id: number): Gunk | null` and
   `getGunkFiles(db, gunkId: number): GunkFile[]`.
4. Tests use an in-memory DB seeded by direct INSERT statements;
   verify all three functions return correctly shaped records and
   honor `removed_at` filtering.

#### MCP touchpoints
This is the layer the MCP tools will call. No MCP tools added yet.

#### Tests required
- [ ] `store.test.ts > listGunks returns rows in dropped_at desc order`
- [ ] `store.test.ts > listGunks excludes rows with removed_at set`
- [ ] `store.test.ts > getGunk returns null for unknown id`
- [ ] `store.test.ts > getGunk returns full record for known id`
- [ ] `store.test.ts > getGunkFiles returns rows for that gunk only`

#### Execution objective
`bun test test/store.test.ts` passes all five tests against an
in-memory DB.

#### Definition of done
- [ ] All tests pass
- [ ] `mcp/README.md` documents the store API
- [ ] `CHANGELOG.md` entry: "`gunk-mcp` store reader (`listGunks`, `getGunk`, `getGunkFiles`)"
- [ ] `docs/roadmap.md` Phase 2: tick "SQLite reader" sub-bullet (add if missing)
- [ ] PR title: `feat(mcp): add typed store reader`
- [ ] PR body links to T-2.6

---

### T-2.7 — `gunk-mcp` MCP server skeleton

**Status:** Not started
**Owner:** Codex

#### Goal
Wire `@modelcontextprotocol/sdk` into `gunk-mcp` so it speaks MCP over
stdio. Handshake works; capabilities are advertised; **no tools yet**.

#### Why
Per ADR-0002, AI tools spawn `gunk-mcp` over stdio. We need the
protocol layer working before adding tools, so we can debug the wiring
in isolation.

#### Prerequisites
- T-2.2 (mcp scaffold)

#### Files
- `mcp/src/server/index.ts`
- `mcp/src/server/capabilities.ts`
- `mcp/src/index.ts` (update to start the server)
- `mcp/test/server-handshake.test.ts`

#### Execution steps
1. Add `@modelcontextprotocol/sdk` as a dependency.
2. In `server/index.ts`, create a `Server` instance with name
   `gunk-mcp` and version from `package.json`. Connect it to a stdio
   transport.
3. In `capabilities.ts`, declare `tools: { listChanged: false }` (we
   have no tools yet but want the capability slot ready). No
   `resources` or `prompts` capabilities.
4. Update `mcp/src/index.ts` to start the server and stay alive on
   stdio.
5. Write a handshake test that programmatically pipes a
   `tools/list` request through the in-process server and asserts it
   returns an empty array (since no tools are registered).

#### MCP touchpoints
Establishes the MCP server itself. From now on, every change to MCP
tools threads through this server.

#### Tests required
- [ ] `server-handshake.test.ts > server starts and advertises tools capability`
- [ ] `server-handshake.test.ts > tools/list returns empty array when no tools registered`

#### Execution objective
Running `cd mcp && bun run start` blocks on stdio (does not exit),
ready to accept MCP messages. Pressing `^C` exits cleanly.

#### Definition of done
- [ ] Both tests pass
- [ ] `bun run start` blocks on stdio cleanly
- [ ] `mcp/README.md` mentions the MCP entrypoint
- [ ] `CHANGELOG.md` entry: "MCP server skeleton (stdio transport, tools capability)"
- [ ] `docs/roadmap.md` Phase 2: tick "`gunk-mcp` skeleton using `@modelcontextprotocol/sdk`"
- [ ] PR title: `feat(mcp): add MCP server skeleton (stdio transport)`
- [ ] PR body links to T-2.7

---

### T-2.8 — `gunk-mcp` `list_gunks` tool

**Status:** Not started
**Owner:** Codex

#### Goal
Register a `list_gunks` MCP tool that returns the user's gunks
(name, path, dropped_at) as a JSON list.

#### Why
First MCP tool. Once this works, an AI client can ask "what gunks does
this user have?" and get a real answer.

#### Prerequisites
- T-2.5, T-2.6 (schema + store reader)
- T-2.7 (MCP server skeleton)

#### Files
- `mcp/src/tools/list_gunks.ts`
- `mcp/src/server/registerTools.ts`
- `mcp/test/tools/list_gunks.test.ts`

#### Execution steps
1. Define the tool with name `list_gunks`, description "List the user's
   gunks (folders dropped onto gunk.app).", and an empty input schema.
2. The handler opens `~/.gunk/store.db` via the migration runner,
   calls `listGunks`, returns `{ gunks: [...] }` as the tool result
   content.
3. Register the tool in `registerTools.ts`; call it from
   `server/index.ts`.
4. Test with an in-memory DB seeded with three gunks; assert the tool
   handler returns them in `dropped_at desc` order.

#### MCP touchpoints
Adds the first tool. Future tools join the same registration list.

#### Tests required
- [ ] `tools/list_gunks.test.ts > returns empty list for empty store`
- [ ] `tools/list_gunks.test.ts > returns three seeded gunks in dropped_at desc order`
- [ ] `tools/list_gunks.test.ts > excludes removed gunks`

#### Execution objective
`tools/list` over MCP shows `list_gunks`. `tools/call` for `list_gunks`
returns the seeded data.

#### Definition of done
- [ ] All tests pass
- [ ] `mcp/README.md` documents the `list_gunks` tool
- [ ] `CHANGELOG.md` entry: "MCP tool `list_gunks`"
- [ ] `docs/roadmap.md` Phase 2: tick "MCP tools: `list_gunks`"
- [ ] PR title: `feat(mcp): add list_gunks tool`
- [ ] PR body links to T-2.8

---

### T-2.9 — `gunk-mcp` `get_gunk` tool

**Status:** Not started
**Owner:** Codex

#### Goal
Register a `get_gunk` MCP tool that returns a single gunk's metadata,
its README content (if a README is present at the folder root), and a
shallow file tree (one level deep).

#### Why
The "wow demo" requires the AI to see *content*, not just names. This
tool delivers that minimum content surface for Phase 2. Phase 4 will
replace this with smart extraction; for now, README + shallow tree is
enough to be useful.

#### Prerequisites
- T-2.6 (store reader)
- T-2.7 (MCP server)
- T-2.8 (precedent for tool registration)

#### Files
- `mcp/src/tools/get_gunk.ts`
- `mcp/src/lib/readme.ts`
- `mcp/src/lib/tree.ts`
- `mcp/test/tools/get_gunk.test.ts`
- `mcp/test/lib/readme.test.ts`
- `mcp/test/lib/tree.test.ts`

#### Execution steps
1. Implement `readReadme(folderPath: string): string | null`. Looks for
   `README.md`, `README`, `Readme.md`, `readme.md` (case-insensitive
   match in that priority). Returns first match's UTF-8 contents,
   capped at 64 KiB (truncate with a `\n\n[...truncated]` marker).
2. Implement `shallowTree(folderPath: string, maxEntries = 200):
   { name: string; type: 'file' | 'dir'; size?: number }[]`. One
   level only. Skips `.git`, `node_modules`, `.DS_Store`. Caps at
   maxEntries.
3. Define the `get_gunk` tool: input schema `{ id: integer }`, output
   `{ id, name, path, droppedAt, readme: string | null, tree: [...] }`.
4. Tests:
   - `readReadme` finds the right file via priority order
   - `readReadme` truncates large files
   - `shallowTree` returns one level only
   - `shallowTree` skips ignored entries
   - `get_gunk` returns 404-ish "gunk not found" for unknown id
   - `get_gunk` returns full payload for a fixture folder

#### MCP touchpoints
Second MCP tool. Combined with `list_gunks`, this is enough surface
for the Phase 2 demo.

#### Tests required
- [ ] `lib/readme.test.ts > finds README.md`
- [ ] `lib/readme.test.ts > prefers README.md over readme.md`
- [ ] `lib/readme.test.ts > returns null when none present`
- [ ] `lib/readme.test.ts > truncates files over 64 KiB with marker`
- [ ] `lib/tree.test.ts > returns one level only`
- [ ] `lib/tree.test.ts > skips .git and node_modules`
- [ ] `lib/tree.test.ts > caps at maxEntries`
- [ ] `tools/get_gunk.test.ts > returns error for unknown id`
- [ ] `tools/get_gunk.test.ts > returns full payload for known id`

#### Execution objective
Calling `get_gunk` with the id of a real folder returns its README
content and shallow tree, which an AI agent can render.

#### Definition of done
- [ ] All listed tests pass
- [ ] `mcp/README.md` documents `get_gunk`
- [ ] `CHANGELOG.md` entry: "MCP tool `get_gunk` (returns README + shallow tree)"
- [ ] `docs/roadmap.md` Phase 2: tick "`get_gunk`"
- [ ] PR title: `feat(mcp): add get_gunk tool`
- [ ] PR body links to T-2.9

---

### T-2.10 — `gunk.app` store writer

**Status:** Not started
**Owner:** Codex

#### Goal
Implement a Swift store layer that opens the same SQLite file, runs
the v0 schema migrations, and exposes `insertGunk(name, path)`,
`listGunks()`, `removeGunk(id)`.

#### Why
The app needs to write to the shared store. We isolate the SQL layer
behind a typed Swift API for the same testability reasons as T-2.6.

#### Prerequisites
- T-2.5 (schema definition; the SQL is the same on both sides)
- T-2.3 (app scaffold)

#### Files
- `app/Sources/GunkApp/Store/Store.swift`
- `app/Sources/GunkApp/Store/Schema.swift`
- `app/Sources/GunkApp/Store/Models.swift`
- `app/Tests/GunkAppTests/StoreTests.swift`
- `app/Package.swift` (add SQLite.swift or GRDB dependency)

#### Execution steps
1. Decide between GRDB and SQLite.swift; document the choice in this
   task's PR. (Recommendation: GRDB for active development + better
   ergonomics.)
2. Add the dependency to `Package.swift`.
3. In `Schema.swift`, embed the v0 SQL as a Swift string literal kept
   character-for-character identical to `mcp/src/schema/v0.sql`.
   Add a comment cross-referencing ADR-0006.
4. In `Store.swift`, implement `Store(path: URL)` that opens the DB
   in WAL mode, runs migrations, and exposes the three methods.
5. In `Models.swift`, define `Gunk` matching the TS counterpart.
6. Tests: open in-memory store, insert a row, list returns it,
   remove flips `removed_at`, list excludes it.

#### MCP touchpoints
Indirect — this is what produces the data MCP serves.

#### Tests required
- [ ] `StoreTests.testInsertGunkPersists`
- [ ] `StoreTests.testListGunksReturnsInDroppedAtDescOrder`
- [ ] `StoreTests.testRemoveGunkSetsRemovedAt`
- [ ] `StoreTests.testListGunksExcludesRemoved`
- [ ] `StoreTests.testMigrationsAreIdempotent`

#### Execution objective
`cd app && swift test` passes the new tests. App can write a row
that `gunk-mcp` (T-2.8) lists correctly.

#### Definition of done
- [ ] All tests pass
- [ ] Schema SQL matches `mcp/src/schema/v0.sql` byte-for-byte (verify
      manually; consider adding a CI check later)
- [ ] `app/README.md` documents the store API
- [ ] `CHANGELOG.md` entry: "`gunk.app` store writer (insert/list/remove + migrations)"
- [ ] `docs/roadmap.md` Phase 2: tick "SQLite schema v0 (using GRDB or sqlite3)"
- [ ] PR title: `feat(app): add SQLite store writer`
- [ ] PR body links to T-2.10

---

### T-2.11 — `gunk.app` drop zone view

**Status:** Not started
**Owner:** Codex

#### Goal
Replace the placeholder popover with a real drop zone. Dragging a
folder onto it inserts a row in the store via T-2.10's API.

#### Why
This is the user-facing entry point per ADR-0004 (drag-in over
file-watch). Without this, gunk has no ingestion surface.

#### Prerequisites
- T-2.10 (store writer)

#### Files
- `app/Sources/GunkApp/Views/DropZoneView.swift`
- `app/Sources/GunkApp/Views/PopoverView.swift` (replace placeholder)
- `app/Tests/GunkAppTests/DropZoneTests.swift`

#### Execution steps
1. Implement `DropZoneView` (SwiftUI) with a dashed-border rectangle,
   centered text "Drag folders here", and a green highlight when a
   draggable item is hovered over it.
2. Use `.onDrop(of: [UTType.fileURL])` (or appropriate macOS API) to
   accept file URLs. Filter to directories only; reject files.
3. On a successful drop, call `Store.insertGunk(name: lastPathComponent,
   path: absolutePath)` and emit a notification (or use a shared
   `@Observable` model) so the list view (T-2.12) refreshes.
4. Update `PopoverView` to embed `DropZoneView`.
5. Tests:
   - DropZoneView rejects non-directory URLs (unit test against the
     filter function, not the UI itself)
   - Calling the drop handler with a real directory URL inserts a
     row in a test Store

#### MCP touchpoints
Indirect — the dropped folders appear in `list_gunks` results
immediately because the MCP server reads from the same DB.

#### Tests required
- [ ] `DropZoneTests.testFilterAcceptsDirectoryURL`
- [ ] `DropZoneTests.testFilterRejectsFileURL`
- [ ] `DropZoneTests.testDropHandlerInsertsGunk`

#### Execution objective
Manual: open the app, click menubar, drag a folder onto the popover,
see a row appear in the underlying SQLite store
(`sqlite3 ~/.gunk/store.db "SELECT * FROM gunks;"`).

#### Definition of done
- [ ] Tests pass
- [ ] Manual smoke test recorded in PR description
- [ ] `CHANGELOG.md` entry: "`gunk.app` drop zone (drag a folder, it lands in the store)"
- [ ] `docs/roadmap.md` Phase 2: tick "Drop zone (\"Drag folders here\")" and "Drop handler"
- [ ] PR title: `feat(app): add drop zone view`
- [ ] PR body links to T-2.11

---

### T-2.12 — `gunk.app` list view + delete affordance

**Status:** Not started
**Owner:** Codex

#### Goal
Below the drop zone, render the list of dropped gunks. Each row shows
name, path, and drop date, with a delete button.

#### Why
The user needs to see what's in gunk and remove things they didn't
mean to drop. Without this, gunk feels like a black hole.

#### Prerequisites
- T-2.10 (store reader exists on app side)
- T-2.11 (drop zone produces rows to display)

#### Files
- `app/Sources/GunkApp/Views/GunkListView.swift`
- `app/Sources/GunkApp/Views/PopoverView.swift` (compose drop zone +
  list view)
- `app/Sources/GunkApp/Models/GunkListModel.swift` (`@Observable`)
- `app/Tests/GunkAppTests/GunkListModelTests.swift`

#### Execution steps
1. Build `GunkListModel` as an `@Observable` (or `ObservableObject` if
   necessary on macOS 14) class wrapping a `Store`. Methods: `refresh`,
   `delete(id:)`. Property: `gunks: [Gunk]`.
2. Build `GunkListView` rendering each gunk as a row with name, path
   (truncated middle), drop date (relative), and a trash button.
3. The trash button calls `model.delete(id:)`.
4. Wire `PopoverView` to refresh the model on appearance and on the
   `gunkInserted` notification fired by T-2.11.
5. Tests against `GunkListModel` only (avoid UI tests at this stage):
   - refresh loads all gunks
   - delete removes one and shrinks the list
   - delete is a no-op for unknown id

#### MCP touchpoints
Indirect — deleting a gunk in the app removes it from MCP results
immediately.

#### Tests required
- [ ] `GunkListModelTests.testRefreshLoadsAll`
- [ ] `GunkListModelTests.testDeleteRemovesOne`
- [ ] `GunkListModelTests.testDeleteUnknownIdIsNoOp`

#### Execution objective
Manual: drop two folders, see them listed; click trash on one, see it
disappear; verify with `sqlite3` that `removed_at` is set.

#### Definition of done
- [ ] Tests pass
- [ ] Manual smoke evidence in PR
- [ ] `CHANGELOG.md` entry: "`gunk.app` list view + delete"
- [ ] `docs/roadmap.md` Phase 2: tick "List view" and "Delete affordance"
- [ ] PR title: `feat(app): add list view and delete affordance`
- [ ] PR body links to T-2.12

---

### T-2.13 — `gunk-mcp` single binary

**Status:** Not started
**Owner:** Codex

#### Goal
Produce a single-binary build of `gunk-mcp` via `bun build --compile`.
Verify it runs on a clean macOS shell with no Bun installed.

#### Why
AI tools (Cursor, Claude Code, etc.) spawn `gunk-mcp` as a child
process. They can't depend on the user having Bun installed. A
single binary is the only reasonable distribution.

#### Prerequisites
- T-2.7, T-2.8, T-2.9 (functional MCP server with two tools)

#### Files
- `mcp/scripts/build.ts`
- `mcp/package.json` (update `build` script)
- `mcp/.gitignore` (exclude `dist/`)

#### Execution steps
1. Write `mcp/scripts/build.ts` invoking
   `Bun.build({ entrypoints: ['src/index.ts'], compile: true,
   outfile: 'dist/gunk-mcp', target: 'bun' })`.
2. Wire `bun run build` to call this script.
3. Verify the binary runs on a fresh shell (`PATH=/usr/bin:/bin
   ./dist/gunk-mcp`) and blocks on stdio waiting for MCP messages.
4. Add `mcp/dist/` to `.gitignore`.

#### MCP touchpoints
None functionally — the same MCP surface is now distributed as a
binary.

#### Tests required
- [ ] CI step: build the binary on macOS runner; verify it executes
      without crashing in a no-input scenario (kill after 2s).

#### Execution objective
`cd mcp && bun run build` produces `mcp/dist/gunk-mcp`. Running it
from a fresh shell waits on stdin.

#### Definition of done
- [ ] Build script works locally on macOS
- [ ] CI builds and smoke-tests the binary on the macOS runner
- [ ] `CHANGELOG.md` entry: "Single-binary build of `gunk-mcp` via Bun"
- [ ] `docs/roadmap.md` Phase 2: tick "Bun-compiled single binary"
- [ ] PR title: `build(mcp): produce single-binary distribution`
- [ ] PR body links to T-2.13

---

### T-2.14 — Cursor MCP integration docs

**Status:** Not started
**Owner:** Codex

#### Goal
Write a one-page `docs/integration/cursor.md` showing exactly how to
wire `gunk-mcp` into Cursor manually. Include a copy-pasteable JSON
snippet.

#### Why
Phase 5 will automate this for all 4 AI tools. For Phase 2, we need
*one* working manual path so we can demo end-to-end.

#### Prerequisites
- T-2.13 (binary exists)

#### Files
- `docs/integration/cursor.md`
- `docs/integration/README.md` (index page for integrations)

#### Execution steps
1. Document where to drop the binary
   (`/usr/local/bin/gunk-mcp` or `~/.local/bin/gunk-mcp`).
2. Provide the exact Cursor MCP config (JSON), with the binary path,
   plus instructions for where Cursor stores its global MCP config.
3. Include a verification step: in Cursor, ask "what gunks do I have?"
   and screenshot the agent calling `list_gunks`.
4. Note: per ADR-0003, this is the manual path. The app's auto-wiring
   (Phase 5) will replace this for most users.

#### MCP touchpoints
Documents the surface; doesn't change it.

#### Tests required
- [ ] Documentation accuracy verified by following the steps on a
      clean Cursor install (manual; record evidence in PR).

#### Execution objective
A reader following `docs/integration/cursor.md` end-to-end can get
Cursor calling `list_gunks` and `get_gunk` against their own gunks.

#### Definition of done
- [ ] Doc is accurate and tested manually
- [ ] `README.md` links to it
- [ ] `CHANGELOG.md` entry: "Cursor MCP integration docs"
- [ ] `docs/roadmap.md` Phase 2: tick "Manual MCP config snippet for one tool (Cursor) in docs"
- [ ] PR title: `docs: add Cursor MCP integration guide`
- [ ] PR body links to T-2.14

---

### T-2.15 — End-to-end smoke test + retro

**Status:** Not started
**Owner:** Mark (with Codex assist for the retro doc)

#### Goal
Run the Phase 2 demo end-to-end on a real machine. Record a ≤90s
screen capture. Write a phase-2 retro. Post the build-in-public
thread.

#### Why
A phase isn't done until a stranger can watch the demo and understand
what gunk is. This task is that closure.

#### Prerequisites
- T-2.1 through T-2.14 all merged

#### Files
- `docs/retros/phase-2.md` (NEW)
- `docs/demos/phase-2.mov` (or external link if too large)

#### Execution steps
1. Run the demo from a clean state (`rm -rf ~/.gunk` before starting).
2. Drag two real abandoned-project folders onto `gunk.app`.
3. Open Cursor, ask: "What gunks do I have? Show me the README of the
   most recent one."
4. Verify the agent calls `list_gunks` and `get_gunk` and returns
   real content from the dropped folders.
5. Record a screen capture.
6. Write `docs/retros/phase-2.md` with sections: What shipped, What
   slipped, What surprised us, What we're cutting.
7. Post the Friday build-in-public thread linking to the recording
   and the repo.

#### MCP touchpoints
Validates that the full MCP surface works end-to-end with a real
client.

#### Tests required
- [ ] The demo flow works on a clean state without errors.

#### Execution objective
A 90-second video the user can DM to anyone that explains gunk in one
view.

#### Definition of done
- [ ] Demo recorded
- [ ] Retro written
- [ ] Build-in-public thread posted
- [ ] `CHANGELOG.md` entry: "Phase 2 walking skeleton complete"
- [ ] `docs/roadmap.md` Phase 2: every box ticked
- [ ] Tag a release: `git tag v0.2.0-alpha && git push --tags`
- [ ] PR title: `chore: phase-2 retro and demo`
- [ ] PR body links to T-2.15

---

## After Phase 2

When every task above is merged and the demo recording exists, we
plan Phase 3 (classifier) by adding `docs/tasks/phase-3-classifier.md`
informed by what we learned. **Do not pre-write Phase 3 — it will be
wrong.**

