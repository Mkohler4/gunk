# 01 — App shell (window, sidebar, navigation, global status)

Source files: `Views/AppShellView.swift`, `MainWindowController.swift`

## Purpose

The shell frames the whole app: a fixed sidebar on the left for navigation
and global status, a detail container on the right that swaps in one of the
five pages.

## Layout

```
+--------------------+--------------------------------------------------+
| (wordmark) gunk    |  [Section title in toolbar]                      |
|                    |                                                  |
|  Sources        ◌  |                                                  |
|  Modules           |                                                  |
|  Approval       ③  |              page content                        |
|  ----------------  |                                                  |
|  Runs              |                                                  |
|  Settings          |                                                  |
|                    |                                                  |
|  +--------------+  |                                                  |
|  | status strip |  |                                                  |
|  +--------------+  |                                                  |
+--------------------+--------------------------------------------------+
```

- **Not a `NavigationSplitView`** — it is a plain `HStack` with a fixed
  **192 pt** sidebar that can never collapse. This was a deliberate fix:
  the split view collapsed the sidebar into an overlay whenever the Modules
  page's wide layout didn't fit.
- Window minimum **960×600** (enforced in `AppLaunchView`); below that the
  Modules three-pane layout cannot fit.
- The detail container gets `Spacing.lg` horizontal padding for every page
  **except Modules**, which gets zero horizontal padding (its internal
  panes need every point of width at the 960 pt minimum). Pages therefore
  have inconsistent content insets.
- Detail background: `backgroundPrimary` with a flush glass wash on top.

## Feature inventory

### Window chrome

- Window title is always **"gunk"**. The current section name renders as a
  `headline` text in the toolbar's navigation slot; the toolbar background
  is hidden so the label floats over the content.
- There is **no toolbar beyond that label** — no global actions, no search,
  no add button anywhere in the chrome.

### Sidebar

- **Header:** the brand wordmark ("gunk").
- **Navigation rows**, in fixed order with a 1 px separator dividing two
  groups:
  - Journey group: **Sources** (`tray.and.arrow.down`), **Modules**
    (`square.grid.2x2`), **Approval** (`checkmark.seal`)
  - Utility group: **Runs** (`clock.arrow.circlepath`), **Settings**
    (`gearshape`)
- Each row: SF Symbol + label; selected row gets accent-tinted fill and
  accent icon; hover gets a faint highlight. Clicking selects that page.
- **Row accessories (the only two badges in the app):**
  - Sources row shows a small **pulsing accent dot** while any source is
    processing.
  - Approval row shows a **count capsule** (accent fill, e.g. "3") equal to
    the number of modules waiting for review. Hidden at zero. The count
    comes from the same model that renders the Approval page, so the badge
    and queue can never disagree.

### Status strip (bottom of sidebar)

The app's **single global status location**. A rounded, tinted, clickable
chip with an icon, a one-line title, and an optional one-line subtitle.
Four mutually exclusive states; clicking navigates somewhere different in
each state:

| State | Shows | Tint/icon | Click navigates to |
| --- | --- | --- | --- |
| Idle, MCP ready | "Agent connected" | green check | Settings |
| Idle, MCP not set up | "MCP not set up" / "Connect Cursor → Settings" | orange warning | Settings |
| Processing | source name (or "N sources") / "NN% · M found" | accent + small spinner | Sources |
| Completed (transient) | "N modules added · M need review" / "Review → Approval" or "View → Modules" | accent sparkles | Approval if review needed, else Modules |
| Run failed | "Run failed" / "View → Runs" | red xmark | Runs |

- The **completed** state lives for exactly **8 seconds** after a run
  finishes, then decays back to idle. It is the app's only "your run
  finished" feedback (besides the per-row outcome on Sources). The
  modules-added count is captured live during the run (max of
  `modulesFound` while processing) because the processing model resets its
  count when the run completes.
- The "needs review" count is computed as the *delta* in the approval queue
  between run start and run end.
- A failed run shows the failed chip instead of a summary; the chip
  persists until the next run starts (it is derived from the processing
  model's lingering `errorMessage`).
- MCP status is re-checked on appear and on every section change.

### Navigation & landing rules

- **Landing (window creation only):** if the store has no sources → land on
  **Sources**; otherwise → land on **Modules**. Never re-routes mid-session.
- **Dock-drop navigation:** when folders arrive via the Dock icon
  (`sourcesArrivedViaOpen` notification), the window raises *and* the shell
  navigates to Sources so the user sees the new row processing.
- **Cross-page navigation wiring** (closures handed to pages):
  - Sources row "N modules" → sets the Modules source filter to that source
    and switches to Modules.
  - Modules empty state "Go to Sources" → Sources.
  - Modules "MCP not set up" affordance → Settings.
  - Status strip taps as in the table above.

### Refresh / data-freshness wiring

- On shell appear: refreshes the source list and browse model, snapshots
  MCP status.
- On `gunkInserted` notification (a source was added): refreshes browse +
  source list.
- When processing flips from true→false (run end): refreshes browse +
  source list, builds the completed summary.
- Individual pages additionally refresh themselves on appear and on
  `gunkInserted` (see their documents).

## States

- The shell itself has no empty/error states; those belong to pages and to
  the launch-failure screen (see 07).

## Known problems & quirks

1. **The status strip is overloaded.** One small chip is simultaneously the
   MCP health indicator, the live progress display, the run-completion
   toast, and the run-failure alert — with a different click target in
   every state. Users cannot predict what clicking it does.
2. **The completion moment is 8 seconds long and tiny.** The single most
   important feedback in the app ("your modules are ready") is a sidebar
   footer chip that silently disappears.
3. **Idle-tap is non-obvious:** clicking "Agent connected" (a green,
   healthy-looking chip) navigates to Settings, which surprises.
4. **Inconsistent page padding** (Modules has none, everything else has
   `lg`) makes page transitions feel unstable.
5. **The toolbar is nearly empty** — a floating section label with no
   actions; meanwhile the wordmark in the sidebar also says "gunk", so the
   product name effectively appears twice next to each other.
6. **Section error text styling differs per page** (Sources/Modules use
   brand caption-with-danger color inline at the top; Approval uses plain
   red `.caption`). Errors still inject above content and shift layout on
   Sources/Modules/Approval.
