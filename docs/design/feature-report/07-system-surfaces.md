# 07 — System surfaces (Dock icon, menubar item, launch failure)

Source files: `Dock/DockIconController.swift`, `MenubarController.swift`,
`AppDelegate.swift`, `Views/AppShellView.swift` (`AppLaunchView`)

These aren't pages, but they are part of the front-end surface area and the
redesign should account for them — especially the Dock icon, which is the
product's signature gesture.

## Dock icon

**Purpose:** the signature drop target; also a glanceable state indicator.

- **Drop target:** dropping folders onto the Dock icon inserts and
  processes them exactly like the in-window drop zone
  (`application(_:open:)` → `AppRuntime.handleOpenURLs`). The window
  raises **and the shell navigates to Sources**, where the new row appears
  highlighted in its processing state.
- **Three visual states** (the phase-7 brand tile — the Ooze mark on a dark
  glass tile; the old trash-can metaphor is retired):
  - **empty** — muted mark (no modules in the store),
  - **full** — full-strength mark,
  - **processing** — accent glow variant while a run is active.
- **Badge (broken — known bug B2, still open):** the code sets a numeric
  `dockTile.badgeLabel` (idle: total module count; processing: modules
  found so far this run) but **no badge has ever been observed to render**.
  The phase-7 ux doc also wanted the idle badge semantics changed from
  "total modules ever" to "pending-approval count"; that change has not
  landed either.

## Menubar item

**Purpose:** one-click path back to the main window.

- Renders a **literal text "G"** in the system menubar (the planned brand
  glyph swap never landed — the controller still sets `button.title = "G"`).
- Tooltip: "Open gunk". **One action:** clicking opens/raises the main
  window. No menu, no popover, no state indication of any kind.
- `PopoverView.swift` no longer exists; the menubar-popover era is fully
  retired.

## Launch failure screen

**Purpose:** graceful recovery when the app can't open its services
(usually the store).

- Replaces the entire shell when `AppRuntime.services` is nil: the brand
  **wordmark (hero style, with reveal animation)**, "gunk could not open"
  (title3 bold), and the selectable underlying error message, centered.
- No retry button, no link to the store path or any remediation — display
  only.

## Known problems & quirks

1. **Dock badge never renders (B2)** — the only number the Dock was
   supposed to show is invisible.
2. **The menubar "G"** is off-brand (plain text glyph) and gives no
   processing/attention state, despite the Dock having three states.
3. **Dock-drop feedback depends entirely on the window**: if the user
   doesn't look at the raised window, nothing else (menubar, notification)
   acknowledges the drop.
4. **Launch failure offers no action** — a dead end with an error string.
