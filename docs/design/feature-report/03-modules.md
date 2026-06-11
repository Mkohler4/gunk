# 03 — Modules page

Source files: `Views/BrowseView.swift`, `Views/AppShellView.swift`
(`ModulesSectionView`), models in `Models/BrowseModel.swift`

## Purpose

The product's core surface: browse, filter, inspect, and trust the modules
gunk has extracted from your sources.

## Layout

Two side-by-side panes (this is the widest page in the app — it is the
reason the window minimum is 960 pt and why the shell removes horizontal
padding for this page):

```
+----------------------- browser (≥440) ---------+--- detail (300–440) --+
| [filter bar — pinned glass card]                | module name           |
|   (Tag | Source | Language | Approval) segments | purpose               |
|   Source ▾  Tag ▾  Language ▾  Approval ▾       | chips: source · lang  |
|-------------------------------------------------|        · confidence   |
|  GROUP HEADER (e.g. tag name)                   |-----------------------|
|   [ module row card ]                           | Agent-ready line      |
|   [ module row card ]                           | [Re-run] [Delete]     |
|  GROUP HEADER                                   | Runability            |
|   [ module row card ]                           | Bundle path           |
|   ... scrollable ...                            | Owned files           |
|                                                 | Shared dependencies   |
|                                                 | Entrypoints           |
|                                                 | Verification details  |
+-------------------------------------------------+-----------------------+
```

- Browser pane: min 440 pt, takes remaining width. Detail pane: explicitly
  computed width clamped 300–440 pt (computed manually because HStack's own
  negotiation cropped both edges at the minimum window size).
- An error from the browse model renders as a danger caption above the
  whole two-pane layout (injected, shifts layout).

## Feature inventory

### Filter bar (pinned, outside the scroll view)

Glass card, small control size, two rows:

1. **Group segmented control** — chooses how the list is sectioned:
   **Tag / Source / Language / Approval**. (Default: Tag.)
2. **Four filter menus:**
   - **Source** — "All sources" or any source by name.
   - **Tag** — "All tags" or any known tag.
   - **Language** — "All languages" or any known language.
   - **Approval** — All / Auto accepted / Approved / Needs approval.

All five controls write straight into `model.filters`; the grouped list
re-derives instantly. The Sources page's "N modules" button arrives here
with the Source filter pre-set.

### Browser list

- Sections per the chosen grouping, each with a `SectionHeader` (the tag /
  source / language / approval bucket name) and a stack of module row
  cards. Lazy, scrollable.
- **Module row card** (glass card; click anywhere selects it):
  - **Name** (medium body, 1 line) and **purpose** (caption, 2 lines).
  - **Metadata caption:** `"{source name} · {language label} · {approval
    label}"`.
  - **Badge row:** an **"Agent-ready"** success badge (sparkles icon) when
    the module has been extracted (`extractedAt != nil`), followed by the
    module's **tag chips**.
  - **Confidence percent** (right-aligned, e.g. "95%").
  - **One action: open-bundle** (folder icon button) — opens the module's
    extracted bundle folder in Finder; disabled when no bundle path exists.
    Re-run and delete were deliberately removed from rows; they live only
    in the detail pane.
  - Selected row: accent border + accent-tinted fill. Hover: faint border.

### Selection behavior

- Clicking a row selects it and renders its detail.
- Filter changes never steal or re-assign selection. If the selected module
  is no longer visible under current filters, selection **clears** and the
  detail pane shows its empty state ("Select a module") — empty selection
  is a valid resting state. There is no auto-select of the first row.

### Detail pane (`ModuleDetailView`), top to bottom

1. **Header:** name (headline, 2 lines), purpose (caption), then three
   `TagChip`s: source name, language (or "Unknown language"), confidence %.
2. **Agent-ready line** — the MCP payoff truth, three variants:
   - MCP **not set up** (per the shell's MCP status): warning badge
     "MCP not set up" + "Connect Cursor → Settings"; the whole line is a
     button that **navigates to Settings**.
   - Extracted: success badge **"Agent-ready"** + "Available to your agent
     through MCP."
   - Not extracted: neutral badge "Not agent-visible yet" + "Approve this
     module to extract it for agents."
3. **Actions row** (the only place these exist):
   - **"Re-run source"** (secondary button) — re-runs decomposition for the
     module's *entire source*, not just this module.
   - **"Delete"** (destructive button) — deletes this module. **No
     confirmation dialog.**
4. **Runability** section (glass card) — two labeled status rows, each with
   a `StatusBadge` and explanatory caption:
   - **"Self-contained for AI reuse"** — Passed / Needs attention / Not
     verified. Checks module-owned imports stay inside the bundle and
     claimed entrypoints exist.
   - **"Standalone runnable project"** — Passed / Failed / Skipped / Not
     verified. Explicitly explained as separate from self-containment.
5. **Bundle path** — monospaced path (selectable, middle-truncated) +
   **"Open in Finder"** secondary button; or "No extracted bundle path
   recorded."
6. **Owned files** — monospaced path list, or "No owned files recorded."
7. **Shared dependencies** — path list, or "No shared dependencies
   recorded."
8. **Entrypoints** — labeled list, or "No confident entrypoints recorded."
9. **Verification details** (conditional):
   - If self-containment failed: **"Self-containment details"** card with
     "Dangling imports" (`from -> target (reason)`) and "Missing
     entrypoints" (`path · symbol (reason)`) lists.
   - If a build verification exists: **"Build verification"** card with the
     command and up to 8 lines of build log (monospaced, selectable).

## States

- **Browser empty (no modules at all):** branded `EmptyStateView` —
  "No modules yet" / explanation / **"Go to Sources"** primary button.
- **Detail empty (nothing selected):** `EmptyStateView` — "Select a module"
  / "Open a module to inspect its files, bundle, and runability signals."
- **Error:** browse-model error message as a danger caption above the panes.
- Refresh triggers: page appear, `gunkInserted`, and run completion (the
  shell refreshes the model when processing ends).

## Known problems & quirks

1. **The information density is very high** and almost everything is
   caption-sized: a row carries name, purpose, three-part metadata, badges,
   chips, a percentage, and a button. Scanning is hard.
2. **Filtered-empty looks like really-empty.** When filters match nothing
   the browser shows… nothing in particular (no "no matches under these
   filters" state) — only the no-modules-at-all empty state exists.
3. **"Re-run source" inside a module's detail re-processes the whole
   source** — destructive-ish scope hidden behind a per-module surface, and
   there is no progress feedback in the detail pane afterwards.
4. **Delete has no confirmation** despite re-run/delete being moved to the
   detail pane specifically because they're "deliberate" actions.
5. **Confidence % appears with no scale or threshold context** here (the
   threshold only appears, unlabeled, in Settings).
6. **The grouping control and the four filter menus overlap conceptually**
   (you can group by Source *and* filter by source) — powerful but
   confusing; there's no indication of active filters beyond menu labels,
   and no one-click "clear filters".
7. **No link from a module to the run that produced it** (Runs page is a
   dead end in both directions).
8. **The layout drives global constraints:** this page's pane minimums
   dictate the 960 pt window minimum, the fixed sidebar, and the
   zero-padding exception in the shell. A redesign that relaxes this page
   relaxes the whole app.
