# 02 — Sources page

Source files: `Views/AppShellView.swift` (`SourcesSectionView`),
`Views/DropZoneView.swift` (`BrandDropZone`, `DropZoneHandler`),
`Views/GunkListView.swift`

## Purpose

Intake surface: add folders for the engine to decompose, and see what each
folder produced.

## Layout

Top-to-bottom, left-aligned, `Spacing.lg` between blocks:

```
+------------------------------------------------------------+
|  [ DROP ZONE — fixed 170 pt tall, full width, glass card ]  |
+------------------------------------------------------------+
|  SOURCES (N)                       ← section header         |
|  (error caption, only when the list model has an error)     |
|  +--------------------------------------------------------+|
|  | source-name                 [status slot]      (trash)  ||
|  | /path/to/folder · added 2 minutes ago                   ||
|  +--------------------------------------------------------+|
|  | ... more rows, scrollable ...                           ||
+------------------------------------------------------------+
```

The drop zone is the hero and **never moves** — there is no global status
block above it anymore (processing awareness lives in the shell's sidebar
dot + status strip).

## Feature inventory

### Drop zone (`BrandDropZone`)

- Glass card, large radius, dashed border, fixed height 170 pt. Contents:
  `folder.badge.plus` icon + "Drag folders here" headline.
- **Targeted state** (while dragging over it): border and icon flip to the
  accent color, an accent-tinted fill fades in, and the whole card scales
  up slightly with a settle animation.
- **Accepts:** file-URL drags. Only **directories** are inserted; files are
  filtered out. If a drop contains no directories, an inline danger caption
  appears *inside* the drop zone: "Only folders can be added." (clears on
  the next successful drop).
- **On successful drop:** each directory is inserted as a Source in the
  store, a `gunkInserted` notification fires (which refreshes the list and
  triggers the arrival highlight), and engine processing starts for that
  source immediately. Multiple folders in one drop are all processed.
- The Dock icon is an equivalent drop target (see 07); Dock drops also
  navigate the window to this page.

### Section header

- `SectionHeader` reading **"Sources (N)"** where N is the live source
  count.

### Error caption

- If the source-list model has an `errorMessage` (e.g. a store read/delete
  failure), it renders as a selectable danger-colored caption between the
  header and the list, pushing the list down.

### Source list (`GunkListView`)

Scrollable stack of glass row cards. Each row contains:

- **Name** (folder name) — body weight medium, one line.
- **Metadata line** — `"{full path} · added {relative time}"` (e.g.
  "/tmp/proj · added 2 minutes ago"), one line, middle-truncated.
- **Status slot** (right-aligned, one of four mutually exclusive states):

| State | Rendering | Behavior |
| --- | --- | --- |
| Processing | linear accent progress bar + "NN% · M found" caption | live progress for this source from the processing model |
| Has modules | secondary brand button: "N modules ›" | **clicking navigates to Modules pre-filtered to this source** |
| Failed | red "Failed" `StatusBadge`; the error message also renders inside the row under the metadata (selectable, 2 lines) | none |
| No modules | tertiary caption "No modules" | none |

- **Delete button** (trash icon, brand icon style) on every row. Removes
  the source from the store **immediately — no confirmation dialog** — and
  refreshes the list. Help text: "Remove {name} from gunk".
- **Arrival highlight:** a freshly dropped source's row appears with an
  accent border + accent-tinted fill, which decays after **2 seconds**.

## States

- **Empty (no sources):** branded `EmptyStateView` in the list area —
  "No sources yet" / "Drop a folder above, or onto the Dock icon."
- **Processing:** per-row progress (above) + the shell-level signals
  (sidebar dot on the Sources row, status strip).
- **Error:** source-level failures on the affected row; list-model errors
  as the caption above the list; drop-validation errors inside the drop
  zone.
- Refresh triggers: page appear, and every `gunkInserted` notification.

## Known problems & quirks

1. **Delete is one click and irreversible** — no confirmation, no undo.
   What deleting a source does to its modules is not communicated at all.
2. **"X% · M found" is ambiguous:** the modules-found count shown on a
   processing row is the *global* `modulesFound` for the whole run, not
   per-source — with multiple sources processing simultaneously, every row
   shows the same number.
3. **"No modules" vs "Failed" vs an old source that processed before
   failure tracking existed** are hard to distinguish; "No modules" reads
   like an error but may be a legitimate outcome.
4. **The list-model error caption still injects above content** and shifts
   the layout when it appears (the one remaining layout-shift error on this
   page).
5. **No way to re-process from here.** Re-running a source's decomposition
   exists only inside the Modules detail pane and the Approval queue —
   nothing on the Sources row offers it, which is where users look first
   after a failure.
6. **No path from a failed row to its run trace** (Runs page) for more
   detail.
