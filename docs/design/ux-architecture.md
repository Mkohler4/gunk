# UX architecture — information architecture and placement (T-7.4b / CP2.5)

Status: **approved — CP2.5 signed off.** The recommended defaults in §4.1
(landing split) and §4.5 (MCP payoff layers) were accepted as written. This
document is the contract the CP3 re-skin tasks (T-7.6–T-7.9) implement
alongside the frozen visual system (CP1 tokens + CP2 components). It decides *what shows up where*: landing
logic, navigation hierarchy, status and feedback placement, primary actions,
and state patterns. It deliberately does not restyle anything — that is CP3 —
and it does not invent features.

Audit basis: code audit of `app/Sources/GunkApp/` plus a live walkthrough of
the packaged app (`make app`, real store with 8 sources / 9 modules), including
one end-to-end run: a fixture folder fed through the Dock-drop code path
(`application(_:open:)`), observed through processing to silent completion
(2 modules, 0.95 confidence, auto-accepted).

---

## 1. Surface inventory (today)

Every surface, the information and actions it carries, and where they live.

### 1.1 App shell + sidebar (`AppShellView.swift`)

- Plain `List` sidebar with five rows in this order: **Sources, Modules, Runs,
  Settings, Approval** (`AppSection.allCases`). No header, no badges, no
  status of any kind.
- Landing is hard-coded: `@State selection = .sources` — every launch lands on
  Sources regardless of app state.
- Detail pane applies `.padding(20)` and a `navigationTitle` equal to the
  section name.

### 1.2 Sources (`SourcesSectionView` + `DropZoneView` + `GunkListView`)

- Top: transient status block — a bare `ProgressView("Processing")` and/or red
  caption error text. When it appears it pushes the whole layout down.
- Middle: drop zone, fixed 170 pt, dashed border, "Drag folders here".
  Targeted state = green tint. Inline error ("Only folders can be added.").
- Bottom: flat source list. Each row: name, full path, relative age
  ("2 days, 5 hrs"), and one action — delete (trash). **No per-source status,
  no outcome (module count), no link to the modules it produced.**

### 1.3 Modules (`BrowseView.swift`)

- Filter bar: group segmented control (Tag/Source/Language/Approval) +
  source/tag/language/approval menus.
- Grouped module list. Row: name, purpose, metadata captions (source,
  language, approval, extraction), bundle path, tag capsules, confidence %,
  and three icon actions (open bundle, re-run decomposition, delete).
- Detail pane (min 300 / max 440 pt): header pills, runability (self-contained
  + standalone-build status), bundle path + Open in Finder, owned files,
  shared dependencies, entrypoints, verification details.
- Row actions duplicate detail actions. Selection auto-snaps to the first
  visible item when filters/sections change (`synchronizeSelection()`).

### 1.4 Approval (`ApprovalQueueView.swift`)

- Headline "Approval queue" + rows: name, purpose, source, confidence %, and
  three icon actions (re-run, approve, reject).
- Empty state: one caption line ("No modules waiting for review.").
- Reject permanently deletes (`BrowseModel.reject` → `removeGunk`) with no
  confirmation. Approve silently extracts; the row just disappears.
- Membership rule: confidence below threshold *and* not approved *and* not
  extracted — high-confidence modules never pass through here.

### 1.5 Runs (`RunsView.swift`)

- Run list (fixed 180 pt): source name, status badge, start time, manual
  refresh button. Detail: provider/model, status, duration,
  accepted / needs-approval / rejected counts, per-stage timings and counts,
  error text.
- Self-described in code as a "debug panel". No link from a run to the modules
  it produced; no link from a module back to its run.
- Empty state: caption "No runs yet. Drop a folder to start." — names the
  action but offers no path to it.

### 1.6 Settings (`SettingsView.swift`)

- Provider form: provider picker, model field, API key, **an unlabeled
  slider** (it is the auto-accept confidence threshold; nothing says so),
  Save / Test connection.
- Status block: provider/model, API key, local store, engine binary, and MCP
  config — each with ready/needs-setup/unavailable state and guidance. This is
  **the only place in the app that knows whether MCP is configured.**
- Fixed 520 pt width form floating in the detail pane.

### 1.7 Menubar item (`MenubarController.swift`)

- A literal text "G". One action: open the main window. No menu, no state.

### 1.8 Dock icon (`DockIconController.swift`)

- Three states wired in code (empty / full / processing). As of T-7.5 the
  trash-can metaphor is retired: the Dock icon is the **brand tile** (the
  Ooze mark on a dark glass tile) in three variants — muted mark when empty,
  full-strength mark, and an accent processing glow. The original audit found
  the three bundled assets byte-identical; T-7.5 fixed that half of D11.
- The code sets a numeric `dockTile.badgeLabel` (idle: total module count;
  processing: modules found so far). In live testing **no badge ever
  rendered** (flagged as bug B2 below; still open for T-7.9).
- Dropping a folder on the Dock icon inserts + processes it
  (`application(_:open:)` → `AppRuntime.handleOpenURLs`) and raises the
  window, but does not navigate or acknowledge the drop in-window.

### 1.9 Window chrome (`MainWindowController.swift` + `AppLaunchView`)

- Title shows the *section* name ("Sources", "Modules", …), never the product.
- Default frame 1040×680, autosaved; min 760×520 (`AppLaunchView`). **At
  widths below ~960 pt the Modules layout cannot fit (sidebar 180 + browser
  min 440 + detail min 300 + padding), so `NavigationSplitView` collapses the
  sidebar into an overlay that clips the filter bar.** Observed at 852×600 —
  a realistic resting size under the current minimum.
- Launch failure: plain triangle + error text, unbranded.

### 1.10 Dead code

- `PopoverView.swift` is referenced nowhere (leftover from the menubar-popover
  era). Note for CP3 cleanup, not for this task.

---

## 2. Core-journey walkthrough (drop → process → browse → approve → MCP)

Live run: fixture folder via the Dock-drop path while the window sat on a
non-Sources section.

1. **Drop** — the window raises but does not navigate; nothing in the window
   acknowledges the drop. The only change is on Sources (which you may not be
   looking at).
2. **Processing** — a bare spinner labeled "Processing" above the Sources drop
   zone. No source name, stage, progress %, or modules-found count — even
   though `ProcessingModel` already tracks `progressBySource` and
   `modulesFound` (**no view consumes either**). Other sections show nothing.
   The Dock "processing" state is invisible (identical assets).
3. **Completion** — silent. The spinner disappears; the source row is
   unchanged (no module count or status); the new modules land wherever the
   alphabetical tag-sort puts them in Modules. Nothing says "2 new modules
   from gunk-ux-smoke".
4. **Approval** — both modules came back at 0.95 → auto-accepted + extracted,
   skipping Approval entirely. When something *does* land in the queue,
   nothing announces it: no badge, no count, section parked below Settings.
5. **MCP payoff** — the journey's actual destination ("module is approved and
   visible to `gunk-mcp`") has zero feedback. Approve silently extracts; the
   only MCP awareness in the app is a status row buried in Settings.

### Findings (each proposal in §3–§4 traces back to these)

| ID | Finding | Evidence |
| --- | --- | --- |
| D1 | Dock-drop gives no in-window feedback and doesn't navigate | `AppDelegate.application(_:open:)`; live run |
| D2 | Processing is visible only inside Sources; no global indicator | `SourcesSectionView.statusView`; live run |
| D3 | Per-source progress + modules-found data exists but renders nowhere | `ProcessingModel.progressBySource` / `.modulesFound` unused by views |
| D4 | Run completion is silent; no "N modules created" moment | live run |
| D5 | Source rows carry no status/outcome and no path to their modules | `GunkListView.sourceRow` |
| D6 | Approval is invisible from elsewhere (no badge/count) and ordered below Settings | `AppSection.allCases`; `ApprovalQueueView` |
| D7 | Reject permanently deletes with no confirmation or undo | `BrowseModel.reject` → `removeGunk` |
| D8 | MCP availability — the payoff — is surfaced only in Settings | `SettingsStatusSnapshot.mcpStatus` |
| D9 | Runs and Modules are not cross-linked in either direction | `RunsView`; `BrowseView` |
| D10 | Window min-size (760×520) breaks Modules: sidebar overlays and clips the filter bar | `AppLaunchView.frame(minWidth:760)`; `BrowseView` pane minimums; observed at 852×600 |
| D11 | Dock icon states were byte-identical (fixed by T-7.5's brand tile); the count badge never renders (open — B2, T-7.9) | md5 of `DockBin*.imageset` assets at audit time; live observation |
| D12 | Modules/Approval go stale during a run — refresh fires on insert (`gunkInserted`) and section re-entry, never on completion | notification posted at insert only |
| D13 | Window title shows the section, never the product | `AppShellView.navigationTitle`; `MainWindowController.register` sets "gunk" but it is overridden |
| D14 | Settings slider is unlabeled; nothing connects it to the approval queue it gates | `SettingsView` body |
| D15 | Status/error text injects above content and shifts layout when it appears | `SourcesSectionView.statusView` |

### Bugs noticed during the audit (recorded, not fixed — land in T-7.6–T-7.9)

| ID | Bug |
| --- | --- |
| B1 | `BrowseModel` is constructed with `Extractor.defaultConfidenceThreshold`, not the user's `llm.confidenceThreshold` setting — the Settings slider likely does not affect the approval gating the UI shows. |
| B2 | The Dock tile badge (`dockTile.badgeLabel`) is set but never renders. |
| B3 | `PopoverView.swift` is dead code. |

---

## 3. Per-surface proposals

Format per surface: purpose (one sentence) · primary action · content
hierarchy · empty/loading/error placement · what navigates here when.
Wireframes are structural, not visual; spacing/material comes from the frozen
design system.

### 3.0 App shell + sidebar

**Purpose:** orient the user in the journey and surface global state at a
glance.
**Primary action:** section navigation.

Sidebar order becomes journey order, with Approval promoted above the utility
pair and given a count badge (→ D6). A persistent **status strip** sits at the
bottom of the sidebar (→ D2, D4, D8; see §4.3 for its rules).

```
+--------------------+------------------------------------------+
| (wordmark)  gunk   |  [Section title]            (toolbar)    |
|                    |                                          |
|  Sources        ◌  |                                          |
|  Modules           |          section content                 |
|  Approval       ③  |                                          |
|  ----------------  |                                          |
|  Runs              |                                          |
|  Settings          |                                          |
|                    |                                          |
|  +--------------+  |                                          |
|  | status strip |  |                                          |
|  +--------------+  |                                          |
+--------------------+------------------------------------------+
```

- `◌` on Sources = processing indicator while any source is processing (→ D2).
- `③` on Approval = pending-review count; row hidden-badge when zero (→ D6).
- Separator groups the journey sections (Sources/Modules/Approval) apart from
  the utility sections (Runs/Settings).
- Sidebar header carries `BrandWordmark` (T-7.5).
- Section error text stops being a red caption injected above content
  (→ D15): errors render where they happen (row-level) or in the status strip
  (run-level); see per-surface rules.

### 3.1 Sources

**Purpose:** add folders and see what each one produced.
**Primary action:** drop a folder (drop zone is the hero).

```
+------------------------------------------------------------+
|  [ DROP ZONE — hero, constant position, idle/targeted ]     |
+------------------------------------------------------------+
|  Sources (N)                                                |
|  +--------------------------------------------------------+|
|  | gunk-ux-smoke              ▸ 2 modules        (actions) ||
|  | /tmp/gunk-ux-smoke · added 2 min ago                    ||
|  +--------------------------------------------------------+|
|  | tradelink                  ⟳ processing 60% · 3 found   ||
|  +--------------------------------------------------------+|
|  | broken-repo                ✕ failed — show error        ||
|  +--------------------------------------------------------+|
+------------------------------------------------------------+
```

- **Content hierarchy:** drop zone first and fixed (no layout shift — → D15);
  then source rows. Each row gains a status/outcome slot (→ D3, D4, D5):
  - processing: inline progress (from `progressBySource`) + modules-found,
  - done: "N modules" affordance that navigates to Modules filtered to that
    source (`filters.sourceId` already exists — placement, not a feature),
  - failed: error state with the message disclosed on the row, not as a
    floating caption.
- **Empty state:** branded `EmptyStateView` inside the list area ("No sources
  yet — drop a folder above, or onto the Dock icon").
- **Loading/error:** per-row (above). The global spinner block is removed;
  global awareness lives in the sidebar (Sources row indicator + status
  strip).
- **Navigates here when:** landing (per §4.1), Dock-drop feedback (§4.4),
  "Add a source" affordances from Runs/Modules empty states.

### 3.2 Modules

**Purpose:** browse, inspect, and trust the modules gunk has extracted.
**Primary action:** select a module to inspect its detail.

```
+--------------------- browser ----------------+--- detail ----+
| [filter bar — pinned]                         | name          |
|  Tag | Source | Language | Approval           | purpose       |
|-----------------------------------------------| pills         |
|  ▾ audio-stitching                            |---------------|
|    ModuleRow   (name, purpose, chips, conf %) | Agent-ready ✓ |
|    ModuleRow                                  | runability    |
|  ▾ parser                                     | bundle        |
|    ModuleRow                                  | files / deps  |
|                                               | entrypoints   |
+-----------------------------------------------+---------------+
```

- **Content hierarchy:** filter bar pinned; grouped list; detail pane.
  Row actions slim down to *open bundle* only — re-run and delete move to the
  detail pane exclusively (they duplicate today; destructive actions deserve
  the deliberate surface).
- Detail gains an **"Agent-ready"** line derived from existing state
  (`extractedAt != nil`): the module-level answer to "is this visible to my
  agent?" (→ D8; final shape gated on the §4.5 decision).
- Selection: stop auto-snapping to the first item on every filter change;
  empty selection is a valid state showing the detail-pane empty state.
- **Empty state:** branded, with a "go to Sources" affordance (→ D9-adjacent
  dead-end).
- **Loading:** browse refreshes when a run completes, not only on insert/
  re-entry (→ D12). **Error:** `BrowseModel.errorMessage` renders at the top
  of the browser pane as a dismissible row, not a floating caption.
- **Navigates here when:** "N modules" tap on a source row (filtered to that
  source), run-detail module links (§3.4), post-run "view modules" feedback
  (§4.4).

### 3.3 Approval

**Purpose:** triage the low-confidence modules gunk wasn't sure about.
**Primary action:** approve.

```
+------------------------------------------------------------+
|  Approval queue (3)        threshold: auto-accept ≥ 70%     |
|  +--------------------------------------------------------+|
|  | module name                              conf 62%       ||
|  | purpose · source                                        ||
|  |                       [Re-run]   [Reject]   [Approve]   ||
|  +--------------------------------------------------------+|
+------------------------------------------------------------+
```

- **Content hierarchy:** count + threshold context in the header (→ D14: the
  user finally sees *why* items are here); card per module with confidence
  made meaningful ("62% — below your 70% auto-accept threshold"); explicit
  labeled buttons (`BrandButton`), approve as the primary.
- Reject asks for confirmation (it permanently deletes — → D7). Approve gives
  feedback instead of a silent vanish: the card resolves into the §4.5 payoff
  moment ("now available to your agent").
- **Empty state:** branded, explains the rule ("Modules under your auto-accept
  threshold appear here for review") instead of one caption line.
- **Error:** model errors as a dismissible row at top.
- **Navigates here when:** Approval sidebar badge; post-run feedback when the
  run produced needs-approval items (§4.4).

### 3.4 Runs

**Purpose:** show what the engine did on each run and why.
**Primary action:** select a run to inspect stages and outcomes.

- **Content hierarchy:** keep list + detail. Run detail adds a "Modules
  produced" block linking each module to Modules/detail (→ D9), and surfaces
  per-run cost next to duration *when the trace carries it* (placement only —
  no engine changes; → §4.3 cost rule).
- Auto-refresh while a run is active (it is the natural "watch it work"
  surface; manual refresh button stays).
- **Empty state:** branded, with an affordance that actually navigates to
  Sources ("Add a source to start").
- **Error:** failed runs keep their red badge; the run-level error stays in
  the detail header.
- **Navigates here when:** status-strip tap during/after a run (§4.3);
  "view run" from a future source-row disclosure (optional, CP3 discretion).

### 3.5 Settings

**Purpose:** configure the provider and verify the pipeline is healthy
end-to-end.
**Primary action:** save provider configuration.

- **Content hierarchy:** two groups, in order:
  1. **Provider** — picker, model, key, then the slider **labeled**
     "Auto-accept confidence threshold" with helper text tying it to Approval
     (→ D14, and B1 once fixed in CP3).
  2. **Health** — the existing five status rows (provider/model, API key,
     store, engine, MCP). The MCP row keeps its setup guidance and becomes the
     navigation target for every "MCP not configured" affordance elsewhere
     (→ D8).
- Form stays width-constrained but centers in the pane.
- **Error/feedback:** Save/Test results inline under the buttons (as today),
  not floating.
- **Navigates here when:** MCP chip in the status strip (§4.3) when MCP needs
  setup; engine/store failure affordances.

### 3.6 Menubar item

**Purpose:** one-click path back to the window; passive status at most.
**Primary action:** open the main window (unchanged).

- The "G" text becomes the brand glyph (T-7.5 asset). While processing, the
  glyph may show an activity variant — mirroring the Dock, never replacing it.
- No menu, no popover (menubar stays secondary per the phase constraints;
  `PopoverView` stays dead and gets removed in CP3 cleanup).

### 3.7 Dock icon

**Purpose:** the signature drop target; its state must be readable at a
glance.
**Primary action:** receive dropped folders (unchanged).

- The Dock icon is the **brand tile** from T-7.5 (muted / full / processing-
  glow states); the trash-can metaphor is retired. T-7.5 fixed the
  identical-assets half of D11 — the states are now visually distinct.
- Badge semantics change from "total modules ever" to **pending-approval
  count** — the only number on the Dock should be actionable (→ D6; B2 —
  the badge never rendering — remains open for T-7.9). While processing:
  badge = modules found so far this run (unchanged intent).
- Window-side feedback on Dock-drop is defined in §4.4.

### 3.8 Window chrome + launch/error

**Purpose:** frame the product; recover gracefully when launch fails.

- Window title is the product: **"gunk"** — the section name lives in the
  toolbar/content, not the title bar (→ D13).
- Sizing per §4.6 (min 960×600, default 1120×720) so the Modules layout never
  collapses the sidebar into an overlay (→ D10).
- Launch failure becomes a branded `EmptyStateView` (mark + "gunk could not
  open" + selectable error + the store path it tried), replacing the bare
  triangle. Behavior unchanged.

---

## 4. Cross-cutting rules

### 4.1 Landing / default section

- **First-run (no sources in the store):** land on **Sources** — the only
  meaningful first action is adding a folder.
- **Returning (sources exist):** land on **Modules** — the product's core
  object; Sources is an intake surface, not a home.
  - Approved at CP2.5: the first-run/returning split above is the rule.
- Landing never overrides an explicit user position within a session; the
  rule applies at window creation only.

### 4.2 Sidebar order, grouping, badges

- Order: **Sources → Modules → Approval | Runs → Settings** (journey order,
  separator before the utility group) (→ D6).
- Badges: Approval row shows pending-review count (hidden at zero). Sources
  row shows a processing indicator while any source is processing (→ D2).
  No other row badges — two signals maximum, so neither becomes noise.

### 4.3 Global status placement (processing, cost)

- A single **status strip** at the bottom of the sidebar is the app's one
  global status location (→ D2, D4, D8):
  - **idle + healthy:** MCP chip ("Agent connected" or "MCP not set up →
    Settings").
  - **processing:** source name + progress + modules-found ("tradelink · 60%
    · 3 found"), tap → Sources (or Runs; CP3 may A/B the target).
  - **just completed:** transient summary ("2 modules added · 1 needs review")
    with tap-through to Modules / Approval; decays back to idle (→ D4).
  - **run failed:** error chip, tap → Runs detail for that run.
- **Cost:** when a run trace carries cost/token data, it renders (a) next to
  duration in the Runs detail header, and (b) inside the transient completed
  state of the status strip. No engine changes — placement rule only.

### 4.4 Drop-gesture feedback (Dock icon fed)

When folders hit the Dock icon (or the in-window drop zone) (→ D1):

1. The window raises (existing behavior) **and navigates to Sources**.
2. The new source row appears immediately in its processing state with inline
   progress (→ D3, D5) and a brief arrival highlight.
3. The sidebar Sources indicator and the status strip activate for the
   duration of the run.
4. On completion the row settles into its outcome ("N modules"), and the
   status strip shows the transient completed state (→ D4). No modal, no
   sheet — the journey stays inside the existing surfaces.

### 4.5 The MCP payoff moment

The product's real payoff — "this module is now available to your agent" — is
currently silent (→ D8). Approved at CP2.5 as proposed — all three layers
below are in:

1. **Per-module truth (recommended baseline):** an "Agent-ready" status line
   in the Modules detail (and a compact badge on rows), derived from existing
   `extractedAt` state. Always visible, no new store fields.
2. **Moment feedback (recommended):** the status strip's transient completed
   state doubles as the payoff banner — after approve/auto-accept it reads
   "Now available to your agent" (with count), tap → Modules.
3. **Unconfigured path:** wherever "Agent-ready" or the payoff banner would
   appear while the Settings MCP status is needs-setup, the copy flips to
   "MCP not set up — connect Cursor → Settings" and navigates to the Settings
   Health group. No new setup flow — it links to the existing guidance.

Resolved at CP2.5: layer 2 is wanted, and the row-level badge in 1 stays
(detail-only remains the fallback if it proves noisy in practice).

### 4.6 Window sizing

- **Minimum: 960×600** — sidebar (200) + Modules browser (min 440) + detail
  (min 300) + paddings fit without the sidebar collapsing into an overlay
  (→ D10).
- **Default (first launch): 1120×720**, centered; frame autosave keeps the
  user's last size thereafter (existing behavior).
- The Settings form stays width-constrained (~520 pt) and centered at any
  window size.

---

## 5. Out of scope

Explicitly **not** part of this architecture or the CP3 re-skins:

- **No onboarding flow** — no welcome tour, no setup wizard. First-run
  guidance is limited to the empty states and the existing Settings guidance.
- **No engine / store / MCP behavior changes** — no schema fields, no new
  engine events, no MCP server changes. Every state referenced above is
  derivable from data the app already has (`progressBySource`,
  `modulesFound`, `extractedAt`, run traces, Settings status checks).
- **No new features** — no notifications center, no search, no module
  editing, no run cancellation. Re-ordering, re-grouping, re-placing, and
  feedback for *existing* capabilities only.
- The five sections stay the five sections; nothing is added or removed.
- Bug fixes B1–B3 are noted for the CP3 tasks that own those files; they are
  not designed around here.
