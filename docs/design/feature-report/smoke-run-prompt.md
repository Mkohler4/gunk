# Design prompt — module smoke run (the developer trust loop)

> Product definition + paste-ready design prompt for the Phase 10 "run &
> test modules" feature. Copy everything below the divider into the Claude
> design chat (it already knows gunk). This file is the repo's record of the
> 2026-06-12 ideation ("what matters for the developer other than the MCP")
> so the design chat, the roadmap, and the eventual task brief can't drift.
>
> **Stage 2 exists:** [`module-io-prompt.md`](module-io-prompt.md) evolves
> this feature — receipt-first evidence with a developer verdict, a typed
> input surface the developer controls, and the on-demand "How this works"
> analysis. When the two prompts disagree, stage 2 wins.

---

We're adding a new aspect of gunk you haven't designed yet: the **developer
trust loop**. You know the product thesis — a module is a capability the
user has extracted, verified, and handed to their agent through MCP. MCP is
the **agent's** door. This feature is the **developer's** door, and it
answers the two questions a developer actually has about a module they
didn't just write:

1. **"Does it actually do the thing?"** — proof, not claims.
2. **"Can I take it somewhere?"** — portability.

Everything on today's module detail is *static evidence* (self-containment
passed, build verified, file lists). gunk asserts; the module never
*demonstrates*. The smoke run is the demonstration.

## The feature (four parts, smallest first)

1. **Copyable invocation snippet.** The store already knows each module's
   entrypoints *with symbols* (e.g. `src/slugify.js · slugify`). Show a
   generated two-line example call with a one-click copy. This answers "how
   do I use this" in a glance.

2. **"To run this elsewhere, you need…" readout.** Replace the raw
   shared-dependency *path list* with a requirements readout: runtime
   (`node ≥ 20`), packages (`lodash`), env vars. Same underlying data,
   reshaped from "what files it touches" into "what you must bring."

3. **The smoke run ("Try it") — the core.** One button on a module:
   execute its entrypoint against the extracted bundle in a sandbox,
   stream stdout/stderr into a mono terminal block, and keep the receipt
   ("Last tried: passed · 1.8s"). States to design: never-tried, consent
   (first run — see safety below), running/streaming, passed, failed, and
   the resting receipt on re-visit. A passed smoke run is *earned* state —
   it may take the accent green (green is meaning-only, and this is
   meaning). This also seeds the module's **Tested badge** and is the first
   *honest* usage signal — the Library's hero ranking has a documented
   `FUTURE: rank by uses/week` seam waiting for exactly this. Never
   fabricate usage numbers.

4. **Runs are receipts, not a dashboard.** Keep two ideas distinct:
   *extraction runs* answer "what did gunk do to produce this module"
   (stages, counts, errors — the receipt of its existence); the *smoke run*
   answers "what does the module do." The run inspector (T-8.6) is the
   former: reachable from `via <model>` on the module, linking back to the
   modules it produced. Do not merge the two into one screen.

## Data truth (design only with this)

- Exists today: entrypoints with symbols; shared-dependency paths; bundle
  path on disk; build verification **already stores a command and a log**
  (a terminal receipt is literally in the store today, buried); extraction
  run traces (provider, model, stages, timings, errors); confidence +
  approval state.
- Does **not** exist: smoke-run results (this feature adds that store
  state — receipts: when, pass/fail, duration, captured output), parsed
  requirements (derivable from bundle manifests), agent usage telemetry
  (still future; flag it if you show it).

## Safety (design this, don't wave at it)

A smoke run executes extracted code on the user's machine. The first run
of any module needs a consent treatment that states what will execute
(command, working directory) without feeling like a scary system dialog.
Subsequent runs of the same module shouldn't re-ask.

## Visual constraints (toolbox-v2 is law)

Neutral graphite surfaces; glass on the floating controls layer only;
accent green only on meaningful state (agent-ready, a passed run); amber
needs-attention, red failed; mono **only** for paths/code — which includes
the terminal output block, the snippet, and the run command; system font
everywhere else. The module detail is moving into a centered glass sheet
(radius 22, blur 50) — design the smoke run as a resident of that sheet.

## What NOT to design

Dependency-graph visualizations, run-history charts, in-app code editing,
metrics dashboards. None of them answer the two trust questions faster
than a green `passed` next to real terminal output.

## Deliverables

1. The module detail sheet with all four parts placed (hierarchy: where do
   snippet, requirements, Try it, and the extraction-run link live
   relative to the existing trust readout and actions).
2. Every smoke-run state: never-tried, first-run consent, running with
   streaming output, passed, failed, and the resting receipt.
3. The Tested badge's expression on the Library cell (it must not compete
   with the one-trust-verdict-per-cell rule).
4. The requirements readout and snippet treatments.
5. Open questions — product decisions you need, explicitly listed
   (e.g. arguments/stdin for entrypoints that need input, timeout
   behavior, what "sandbox" promises the UI may make).
