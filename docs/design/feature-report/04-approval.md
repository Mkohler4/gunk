# 04 — Approval page

Source files: `Views/ApprovalQueueView.swift`, `Views/AppShellView.swift`
(`ApprovalSectionView`)

> **Important for the redesign:** this page was **never re-skinned** in
> phase 7. It still uses plain SwiftUI styling (system fonts, `Divider()`s,
> borderless icon buttons, plain red error text) and none of the brand
> components the rest of the app uses. It is the most visually and
> behaviorally outdated page in the app.

## Purpose

Triage queue for low-confidence modules: the engine wasn't confident enough
to auto-accept them, so a human decides — approve (extract for agents),
reject (delete), or re-run.

## Membership rule (what appears here)

A module is in the queue when **all three** hold:

- confidence is **below the auto-accept threshold**, and
- it has **not been approved**, and
- it has **not been extracted**.

High-confidence modules are auto-accepted + extracted during the run and
**never appear here**. The queue count is the same number shown as the
badge on the sidebar's Approval row.

## Layout

A plain scroll view:

```
+------------------------------------------------------------+
| (error caption, plain red, only when the model errors)      |
| Approval queue                       ← plain headline       |
|  module-name                         62%   (⟳) (✓) (✕)      |
|  purpose, up to 2 lines                                     |
|  source-name                                                |
|  ──────────────────────────────────────────                 |
|  next row ...                                               |
+------------------------------------------------------------+
```

Rows are divided by hairline `Divider()`s — no cards, no glass.

## Feature inventory

### Header

- Static text **"Approval queue"** (system headline). No count, no
  threshold context, no explanation of why items are here.

### Queue row

- **Name** (medium body, 1 line), **purpose** (caption, 2 lines),
  **source name** (caption2, tertiary).
- **Confidence percent** (e.g. "62%"), right-aligned, fixed 42 pt column.
- **Three icon-only borderless buttons** (78 pt cluster, right-aligned):

| Icon | Action | Exactly what it does |
| --- | --- | --- |
| `arrow.triangle.2.circlepath` | Re-run | Re-runs decomposition for the module's **entire source** |
| `checkmark.circle` | Approve | Marks approved and **extracts the module** (making it Agent-ready / MCP-visible). The row silently disappears. **No success feedback.** |
| `xmark.circle` (destructive) | Reject | **Permanently deletes the module** from the store. **No confirmation dialog, no undo.** The row disappears. |

Each button has a tooltip and accessibility label; that is the only
labeling.

## States

- **Empty:** one plain caption — "No modules waiting for review." No
  explanation of the rule that feeds the queue.
- **Error:** browse-model error as plain red caption above the headline
  (injected, shifts layout).
- Refresh triggers: page appear and `gunkInserted` notifications.

## Known problems & quirks

1. **Reject = permanent delete behind an unlabeled icon with no
   confirmation.** This is the single most dangerous control in the app and
   it sits 6 pt away from Approve.
2. **Approve gives zero feedback.** The whole point of the product — "this
   module is now available to your agent" — happens here, silently; the row
   just vanishes. (The shell's status strip completion state only fires for
   *runs*, not for manual approvals.)
3. **Confidence is meaningless without the threshold.** "62%" gives no clue
   that the auto-accept bar is, say, 70%, or that the slider in Settings
   controls it.
4. **Re-run scope is misleading** — the icon sits on a module row but
   re-processes the whole source.
5. **Not on the design system** — fonts, spacing, dividers, and buttons all
   differ from Sources/Modules; the page feels like a different app.
6. **Known logic bug (B1, still open, verified in code):** the *engine*
   reads the user's `llm.confidenceThreshold` setting when deciding what to
   auto-accept, but `BrowseModel` — which computes this queue and the
   sidebar badge — is constructed with the hard-coded default (0.7). If the
   user moves the Settings slider away from 0.7, the queue shown here can
   disagree with what the engine actually did.
7. **No detail access:** you must judge a module from name + 2 lines of
   purpose + a percent. There is no way to inspect its files/runability
   (the information that exists in the Modules detail pane) before deciding
   — and unextracted modules may not even be reachable in Modules'
   default views without fiddling with the Approval filter.
