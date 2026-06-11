# 05 — Runs page

Source file: `Views/RunsView.swift`

> **Important for the redesign:** like Approval, this page was **never
> re-skinned** in phase 7 — plain SwiftUI styling throughout. The code's
> own doc comment calls it a **"debug panel."**

## Purpose

Inspect what the engine did on each run: per-run traces (read from
`~/.gunk/runs`) with status, timing, outcome counts, and per-stage detail.

## Layout

Master-detail in a plain HStack:

```
+--- run list (fixed 180) ---+--------- detail (rest) ----------+
| Runs              (⟳)      | source-name        (title)       |
|  source-name               | provider · model   (caption)     |
|   [status] 14:32:05        | [status badge]  1234 ms          |
|  source-name               | (error text, red, if failed)     |
|   [status] 14:18:40        |                                  |
|  ... List, sidebar style   |  Accepted  Needs appr.  Rejected |
|                            |     4          1           0     |
|                            | ─────────────────────────────    |
|                            | Stages                           |
|                            |  [ stage rows ... ]              |
+----------------------------+----------------------------------+
```

## Feature inventory

### Run list (left, fixed 180 pt)

- Header "Runs" + a **manual refresh button** (`arrow.clockwise`,
  borderless). Traces are loaded on page appear and on refresh click —
  **there is no auto-refresh**, even while a run is actively executing.
- One row per trace: **source name**, a colored **status capsule**
  (succeeded = green, failed = red, anything else = orange), and the start
  time (hour:minute:second only — no date).
- Selecting a row shows its detail; with nothing selected the most recent
  trace is shown by default.

### Run detail (right)

- **Header:** source name (title3 bold), `"{provider} · {model}"` caption,
  status capsule, duration in raw milliseconds (e.g. "83214 ms").
- **Error text** (plain red caption) when the run failed.
- **Summary row** — three count pills: **Accepted** (green), **Needs
  approval** (orange), **Rejected** (red).
- **Stages list** — one box per engine stage:
  - stage name (monospaced) + duration in ms,
  - a counts line (`key=value` pairs, monospaced, e.g. `files=120
    modules=4`),
  - stage error text (red) if any,
  - background tinted faint red for errored stages, faint gray otherwise.

## States

- **Empty:** plain caption — "No runs yet. Drop a folder to start." (names
  the action, but offers no link/button to go do it).
- **No selection:** "Select a run to inspect its stages." (rarely seen,
  since the first trace auto-selects).
- **Error:** run-level and stage-level error text inline (above).

## Known problems & quirks

1. **No auto-refresh:** while a run is executing — the one moment a user
   would watch this page — nothing updates until they click refresh.
2. **Completely disconnected from the rest of the app:** no link from a run
   to the modules it produced, no link from a module/source back to its
   run, and the run-failed status strip drops users here with no
   highlighting of the failed run.
3. **Raw developer formatting:** millisecond durations ("83214 ms"),
   `key=value` stage counts, time-of-day-only timestamps with no date.
   The needs-approval pill doesn't link to Approval.
4. **Off the design system** entirely (the only `List`/`.sidebar` style in
   the app, plain dividers, ad-hoc capsules and pills).
5. **Identity confusion in the list:** rows show only source name + time,
   so several runs of the same source are indistinguishable at a glance
   except by timestamp.
