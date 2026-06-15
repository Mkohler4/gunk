# Phase 9 retro: Library v2 + processing states

Phase 9 finished the Library as a **roster of your agent's toolbox** and made
folder processing **feel alive**. A module now durably states which model
created it (with the provider's brand mark), the Library toggles between the
briefing-card grid and a denser list, dropping a second folder mid-run
enqueues instead of racing, one global animated state shows the live run while
the app stays fully browsable, and the long-deferred Dock badge render bug
(B2) is fixed. It builds **on top of** the Phase 8 cell (toolbox-v2, T-8.3b)
without re-opening it.

Task breakdown:
[docs/tasks/phase-9-library-v2-and-processing-states.md](../tasks/phase-9-library-v2-and-processing-states.md)
(T-9.1–T-9.7, checkpoints CP-D/E, both cleared). Approved design:
[library-v2](../design/explorations/library-v2.md).

## What shipped

- **List-view + processing-animation design gate** (T-9.1, CP-D): the
  approved [library-v2](../design/explorations/library-v2.md) exploration —
  a denser list (hero flattened to a quiet `MOST USED` marker) and one global
  processing animation that reconciles the T-8.7 signals into a single run
  panel with queue depth, resolving into the existing toast — from a verbatim
  [revision instruction](../design/explorations/library-v2-instruction.md),
  cross-linked from the roadmap. An approved exploration plus an explicit
  implementation task (Phase 8's hard-won lesson) kept T-9.3/T-9.4 on the
  right look.
- **Durable model attribution** (T-9.2 Part A, #166, CP-E; closes D9): a
  denormalized `provider`/`model` pair on `gunks` (Schema **v5** — additive,
  nullable, non-destructive; old stores open unchanged). Chosen over a
  `runId` FK because the whole point of D9 is that a module knows its model
  even when traces/runs are pruned, and `llm_runs` is not a reliable
  per-module source. `SourceProcessingRunner` writes it at extraction time
  (`engine/` untouched); `ProvenanceBackfill` fills today's library once on
  open from the same `RunTrace` resolution `BrowseModel` already used;
  `provenance(for:)` prefers the stored value with a trace fallback so nothing
  regresses. App-only — no `mcp/` counterpart, verified safe against the
  gunk-mcp migrator (early-returns past v4) and its explicit-column reads.
- **Provider brand marks** (T-9.2 Part B, #165): OpenAI / Anthropic / Ollama
  SVGs bundled as `Bundle.module` resources and resolved through
  `ProviderIcon`; the grid card carries a large faint `ProviderWatermark`
  bled off the bottom-trailing corner, the list row a compact `ProviderMark`
  squircle. Unshipped brands fall back to a neutral provider-accent mark.
  Quiet provenance, never a second trust badge.
- **Grid + list view toggle** (T-9.3, #167): an icon-pair segmented control
  in the appbar, persisted via `@AppStorage("library.viewMode")` (grid
  default). The list renders each group as one solid graphite card of
  hairline-divided `ModuleRow`s reusing the cell's resolved data; search,
  grouping, the needs-approval scope, selection, and the arrival highlight are
  shared across both modes — only the layout forks. Both fit at 960pt.
- **Single-folder processing queue + global run panel** (T-9.4, #167):
  `SourceProcessingRunner` owns a serial enqueue/drain queue (a second drop
  waits instead of running concurrently — the old per-drop `Task` raced);
  queue depth surfaces through `ProcessingModel.waitingSourceNames` without
  touching its `isProcessing`/progress contract. The T-8.7 chip is extended
  into the one `ShellRunPanel` (spinner ring, determinate progress,
  "decomposing · N found", "N waiting · next:"), reconciled with the nav-row
  live-dot echo and resolving into the existing run-end toast. The app stays
  fully browsable mid-run with zero layout shift (D15).
- **Dock badge render bug B2 fixed** (T-9.5, #167): the transition applied
  state then badge as two render passes, flashing the stale idle count on the
  new processing icon. Fixed with an atomic
  `DockIconController.transition(to:badgeCount:)` and a forced
  `dockTile.display()` per apply; regression-tested.
- **Close-out** (T-9.7): removed the orphaned `ProviderBadge` — #165 reworked
  it into a "token" and kept it "for reuse", but the card uses
  `ProviderWatermark` and the row uses `ProviderMark`, so nothing consumed it
  (only its own `#Preview`). Its provider→color/glyph resolution lives on in
  the shared `ProviderIcon` + `BrandColors.providerAccent`. Backfilled the
  missing Phase 9 CHANGELOG entries (T-9.2–T-9.5 had merged undocumented),
  checked off the roadmap, and ran the regression pass below.

## Regression pass (T-9.7)

At the 960pt minimum and default width, both Library modes were verified
against the real store: the grid (provider watermark logos, `via <model>`
provenance, "Agent-ready" verdict, usage-ranked hero) and the list (compact
`ProviderMark`, the faint `MOST USED` marker, `Project | Model` grouping with
capability counts) render with no clipped controls and no layout shifts. The
**toolbox-v2 styling constraints hold**: content is solid graphite, glass is
on the controls layer only (appbar header, sidebar, run panel, run-end toast,
drop-intake panel, detail overlay cards — all documented as such), `mono` is
confined to paths/code (bundle path, build command/log, owned files, shared
deps, entrypoints) plus the one sanctioned `MOST USED` micro-label, and accent
green appears only on meaningful state (the approval count badge, the live-run
pulse dot, selection/arrival rings). The mid-run animation, queued state, and
the full Dock badge idle→processing→complete cycle are covered by tests
(`SourceProcessingRunnerTests`, `ProcessingModelTests`, `ShellRunToastTests`,
`DockIconControllerTests`) and stageable via `GUNK_DEBUG_PROCESSING`; the live
visual confirmation of those transient states remains Mark's `[HOLD FOR ME]`
gate. Build + tests green (147 tests, 1 skipped).

## What slipped

- **Module relationship graph view** (T-9.6) was an explicit cut-freely
  stretch and was **deferred to Phase 13** rather than built — see below.
- **Usage telemetry** still doesn't exist, so the hero/`MOST USED` ranking
  stays on its documented fallback comparator (`extractedAt`/agent-ready,
  then confidence, then name) behind the single swappable `heroRank` seam.
  No fabricated "uses this week" numbers.
- **Module detail stays interim**: the full module page is Phase 10
  ([module-run-v1](../design/explorations/module-run-v1.md)); nothing was
  pre-built here. The dependencies/versions panel stayed moved to Phase 10 as
  the "requirements readout".
- **B1** (the 0.7 auto-accept gate is hard-coded; the Settings slider is
  cosmetic) remains a Phase 11 item, as planned.
- **Google/Gemini and other brands** ship the neutral provider-accent mark,
  not a logo, until their brand terms are cleared — `ProviderIcon` only
  resolves OpenAI / Anthropic / Ollama artwork.

## What we learned

- **An approved exploration still needs its own implementation task.** Phase 8
  taught this the hard way; Phase 9 front-loaded it (T-9.1 → T-9.3/T-9.4) and
  the list view and run panel landed on the approved look the first time.
- **Denormalize when the requirement is "survives deletion".** D9's whole
  point was attribution that outlives trace pruning, so a `runId` FK (to a
  row that's `ON DELETE SET NULL` and mostly absent) would have re-created the
  dependency we were removing. Storing the two strings made the stored path
  and the trace fallback produce identical values.
- **Concurrency bugs hide as "works today".** `ProcessingModel` allowed
  concurrent sources and nothing had forced the race yet; the fix was a queue
  at the orchestration layer, not a model rewrite — its multi-source map still
  cleanly handles the active one.
- **Two-render-pass bugs need an atomic API, not a nudge.** B2 wasn't a count
  error; it was state and badge applied in separate passes. Collapsing them
  into one `transition(to:badgeCount:)` with a forced redraw fixed the class
  of bug, not just the symptom.
- **"Kept for reuse" is how dead code is born.** #165 deliberately kept
  `ProviderBadge` "for reuse"; three tasks later nothing used it. The honest
  move at close-out is to delete the unconsumed component and let the shared
  resolution (`ProviderIcon`) carry the reuse instead.
- **`GUNK_DEBUG_*` hooks keep earning their keep.** `GUNK_DEBUG_PROCESSING`
  made the running/queued run-panel states screenshot-stageable without a live
  decomposition, the same pattern as the toast and drop-overlay hooks.

## What we're deferring / cutting

- **The module relationship graph view (T-9.6) — deferred to Phase 13.** Never
  started. It was the lowest-value, looks-good-only item in the phase, gated on
  the core (T-9.2–T-9.5) being solid, and it ships only if it never competes
  with the cells for scan attention — a bar a tech-demo graph doesn't clear.
  Rather than cut it outright, it moved to
  [Phase 13](../tasks/phase-13-walkthrough-onboarding.md) as a carried-over
  stretch; the data (sources → modules → owned files) is still there if a later
  phase finds a real use for it.
- No fabricated usage numbers ahead of real telemetry, and no speculative
  module-detail container work ahead of the Phase 10 decision.
