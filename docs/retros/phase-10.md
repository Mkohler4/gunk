# Phase 10 retro: Run & test modules (the proof loop)

Phase 10 built **the developer's door** into a module — and, for the first
time, **the agent's door beyond read-only**. Clicking a module stopped opening
an inline pane and now navigates to a full **module page** whose hero is a
sandbox-bounded **run console** paired with a **coverage ledger** that states —
plainly, never as a score — which classes of input have actually been proven
(*happy path · your own inputs · edge cases · adversarial*). An MCP `run_gunk`
tool lets the agent earn the same evidence the human does, and a quiet "How
this works" disclosure explains a module's design on demand. Trust is coverage
across classes plus an honest sign-off, not a badge earned in one click.

Task breakdown:
[docs/tasks/phase-10-run-and-test-modules.md](../tasks/phase-10-run-and-test-modules.md)
(T-10.1–T-10.15, checkpoints CP-F…CP-K). Design source of truth:
[module-run-v2](../design/explorations/module-run-v2.md) (+ the landed
`module-run-v2.html`, which wins over v1). Architecture:
[ADR-0016](../adr/0016-sandbox-execution-model.md) (sandbox, Accepted) and
[ADR-0017](../adr/0017-mcp-run-tool.md) (MCP run tool, Accepted).

## What shipped

- **Design gate** (T-10.1, CP-F): the module-run-v2 HTML export landed and
  reframed the phase — "Proven by you" is dead; the page is a run console +
  honest coverage ledger, runtime scope is **terminal-only**, and the improve
  loop is **capture-and-queue** (re-extraction deferred). All ten open
  questions resolved.
- **Sandbox & execution runner** (T-10.2, CP-G, ADR-0016): an app-side Swift
  `SmokeRunner` that copies a bundle into a throwaway run dir and wraps the
  interpreter in a deny-by-default `sandbox-exec` (Seatbelt) profile — network
  off, writes confined. Backs both run doors. A **runnability classifier**
  produces the honest "runnable here: not yet" categories (needs network /
  secrets / interactive / long-running / UI module / can't-determine) as a
  distinct class from a failed run.
- **Proof-loop store** (T-10.3, CP-H, Schema **v6**, #/178-era): two additive,
  app-only tables — `smoke_runs` (the receipt: runnability, origin, exit/pass,
  duration, log) and `module_examples` (the fixture library, folding pinned
  failing cases and known limits into one table via `input_class` +
  `expected_output`/`note`). Coverage/Tested state stays **derived**, not
  denormalized.
- **Full module page** (T-10.4): clicking a module navigates to a breadcrumbed
  page (`‹ Library › <source> › <module>`) that carries every former inline
  capability, hosting the run console + ledger.
- **Call it snippet** (T-10.5, #174): a copyable, generated invocation snippet
  from the stored entrypoints + symbols.
- **Requirements readout** (T-10.6, #175): "to run this elsewhere, you need" —
  runtime, packages, env vars, persisted into the bundle's `gunk.yml` and read
  back by the app.
- **Run console** (T-10.7, CP-I, #176): consent → run → streaming terminal →
  receipt, with the raw command + log demoted to a disclosure and the receipt
  as the durable resting state.
- **Typed input surface** (T-10.8, #177): native controls inferred from the
  entrypoint signature so the developer can bring **their own** input; an
  unreliable inference falls back to the zero-touch terminal run.
- **Run console v2 + coverage ledger** (T-10.9, #178): the input-class spine,
  in-console diff receipt, developer verdict, and known limits — the heart of
  the page. Plus the **passing-checks** named-case list (T-10.10).
- **Coverage sign-off** (T-10.11, CP-J, #179): the pure derivation that gates
  `Ready to connect` — earned only when happy-path **and** the developer's own
  inputs are proven, never by one AI-staged pass.
- **MCP `run_gunk` tool** (T-10.12, CP-K, #180, ADR-0017): the agent's execute
  door, sharing the evidence pile but stated separately ("N agent runs · M you
  checked") — agent volume never reads as human-checked.
- **UI-module detection** (T-10.13, #181): keys on declared UI framework **or**
  entrypoint shape (`.jsx`/`.tsx`/`.vue`/`.svelte`/`.astro`/`.html`/`.htm`),
  rendering the neutral "UI module — in-browser launch coming later" label. The
  actual launch is **deferred** (see below).
- **"How this works" analysis** (T-10.14): one quiet disclosure opens a cached
  AI walkthrough of a module's design — instant on open, generated once and
  cached, never auto-summoned. **Decision: generated app-side and cached** in a
  new app-only, additive **Schema v7** (`module_analyses`), because the engine
  extractor makes no LLM call and the manual-approve path is pure Swift with no
  engine — so app-side generation is the one mechanism that covers every module
  (including older + manually-approved ones).
- **Close-out** (T-10.15): deleted the orphaned legacy `RunConsoleView`,
  updated the roadmap + ADRs, and wrote this retro (below).

## Cleanup (T-10.15)

`rg` confirmed the inline `ModuleDetailView` was already gone (its capabilities
moved onto the page in T-10.4; only docstrings still name it). The one piece of
genuinely orphaned scaffolding was the **legacy `RunConsoleView`** struct: it
was superseded by `RunConsoleStageView` (the v2 presentation) when the run
console v2 landed in T-10.9, yet `RunConsoleView` was never instantiated
anywhere — including by the screenshot hooks, which live on the still-used
`RunConsoleModel`. T-10.13 even updated its deferred-label copy, which was
editing dead code (the same "kept for reuse" trap Phase 9 called out). It was
removed and its file renamed to `RunConsoleModel.swift` to match its sole
surviving content; `RunConsoleModel` and the `GUNK_DEBUG_RUN_CONSOLE` staging
stay intact. Schema-parity check still passes (it only asserts v0–v4, and v5/v6/
v7 are all app-only with no `mcp/` counterpart). Build + tests green (257
passing, 1 sandbox-availability skip).

## Regression pass (T-10.15)

Reviewed at the 960×600 minimum and default window size: the module page and
its run states — consent, streaming, passed, failed, resting receipt, the
intent toolbar + typed inputs, the in-console diff receipt, the coverage ledger
+ known limits, the passing-checks list, the sign-off locked vs.
`Ready to connect`, the UI-module not-runnable label, and the new "How this
works" disclosure (closed / open / not-analyzed) — all staged via the
`GUNK_DEBUG_RUN_CONSOLE`, `GUNK_DEBUG_MODULE_PAGE`, and `GUNK_DEBUG_HOW_IT_WORKS`
hooks. The **toolbox-v2 constraints hold**: solid graphite content, glass on the
controls layer only (the breadcrumb header), `mono` confined to paths / code /
terminal (the Call-it snippet, bundle path, entrypoints, and the analysis's code
references), and accent green only on earned meaning (the `Ready to connect`
sign-off and the live-run pulse). The **two-surfaces rule** holds: the smoke run
("what does the module do") never merges with the `view run →` extraction
inspector ("what did gunk do"). The live visual confirmation of the transient
run states and a real "How this works" open remain Mark's `[HOLD FOR ME]` gate.

## What slipped

- **In-browser UI-module launch (T-10.13)** is deferred to a later phase, as
  the CP-F revision planned. This phase ships **detection + an honest deferred
  label**, not a working launch button; `NSWorkspace.open` at a served surface
  is the eventual target.
- **Guided re-extraction** stayed **capture-and-queue** (CP-F open question
  #10): a wrong verdict pins the expected output + a note as a failing case;
  the re-extraction trigger that flips it green is a follow-up.
- **The "How this works" analysis is generated app-side, not at extraction.**
  The faithful "engine at extraction" place can't reach manually-approved or
  older modules (no engine on that path, no LLM call in the extractor), so the
  honest, uniform choice was app-side on-demand generation. Generating at
  extraction for auto-accepted modules — so the first open is pre-warmed — is a
  reasonable future optimization on top of the same cache.

## What we learned

- **"Kept for reuse" is still how dead code is born — and gets *maintained*.**
  Phase 9 deleted `ProviderBadge` for this reason; Phase 10 found
  `RunConsoleView` had not only survived but been *edited* in T-10.13. The
  close-out lesson compounds: delete the unreferenced view at the phase exit,
  and don't update copy on a view nothing renders.
- **"The faithful place" and "the place that covers every case" can differ.**
  The engine at extraction is the natural home for module prose, but it doesn't
  run for manually-approved modules and makes no LLM call. Choosing the app-side
  cache made the feature uniform and let the schema comment record *why* the
  obvious-looking choice was wrong.
- **A derived flag beats new store state until it can't.** Runnability and
  coverage stayed derived (no persisted `isUIModule`, no denormalized Tested
  tier); only the genuinely expensive-to-recompute artifacts earned a table
  (receipts, examples, the cached analysis).
- **`GUNK_DEBUG_*` hooks keep paying for themselves.** Every run state, the
  UI-module label, and now the analysis disclosure are screenshot-stageable
  without a live model, a real sandbox run, or a seeded store.

## What we're deferring / cutting

- **UI-module in-browser launch** → a later phase (detection landed now).
- **Guided re-extraction** → follow-up (capture-and-queue shipped now).
- **Pre-warming "How this works" at extraction** for auto-accepted modules →
  optional future optimization over the existing cache.
- Still explicitly **out**: dependency-graph visualizations, run-history charts,
  in-app editing, metrics dashboards — the proof loop is receipts + coverage,
  not a dashboard.
