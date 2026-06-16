# Phase 10 — Run & test modules (the proof loop)

This phase builds **the developer's door** into a module — and, for the
first time, **the agent's door beyond read-only**. MCP let the agent *read*
a module (Phases 2–8); this phase lets a module **demonstrate that it
works**, to two audiences: the **developer** (who runs it, judges the
output, and pins a golden example) and the **AI system** (which can run and
test a module over MCP before it dares use it). Two questions drive every
item: *"does it actually do the thing?"* (proof, not claims) and *"can I
take it somewhere?"* (portability).

Clicking a module stops opening an inline pane and instead navigates to a
**full module page** (breadcrumb `‹ Library › <source> › <module>`) whose
hero is a real, **sandbox-bounded run console** paired with a **coverage
ledger** that states — plainly, never as a score — which classes of input
have actually been proven (*happy path · your own inputs · edge cases ·
adversarial*). Trust is not a badge earned in one click: it is coverage
across those classes, and an **agent connection** (`Connect to my agent`)
is offered only when that coverage is honestly sufficient. An MCP run/test
tool lets the agent earn the same evidence the human does. (This supersedes
v1's standalone *proof card* and *Tested badge* per the CP-F-approved
[module-run-v2.md](../design/explorations/module-run-v2.md); the task bodies
below were updated to match — the run console is T-10.7, the coverage ledger
is T-10.9, and the sign-off is T-10.11.)

Roadmap: [docs/roadmap.md → Phase 10](../roadmap.md). Product definition:
[smoke-run-prompt.md](../design/feature-report/smoke-run-prompt.md) (stage
1), [module-io-prompt.md](../design/feature-report/module-io-prompt.md)
(stage 2), and the direction-setting exploration
[module-run-v1.md](../design/explorations/module-run-v1.md) (stage 3 —
**when its design HTML lands, the HTML wins** over the prose and the PNGs,
same rule as toolbox-v2). Phase 8/9 outcomes this phase builds on:
[docs/retros/phase-8.md](../retros/phase-8.md),
[docs/retros/phase-9.md](../retros/phase-9.md) (write the latter if it does
not exist yet).

The reference screens. The **CP-F-approved target** is the
[module-run-v2](../design/explorations/module-run-v2.md) **run console +
coverage ledger** — the interactive HTML export is the source of truth (when
the HTML lands, the HTML wins, same rule as toolbox-v2):

![Module page — run console + coverage ledger](../design/explorations/module-run-v2-coverage.png)

- Interactive source of truth (full page, every run state):
  [`module-run-v2.html`](../design/explorations/module-run-v2.html).
- The structural shell that hosts it ships in **T-10.4**; the run console
  (intent toolbar, composed command, Run) and the coverage ledger land across
  **T-10.5 – T-10.11** (they are *not* part of the T-10.4 shell).

The earlier v1 PNGs (resting "Proven" state only — **every other state was
unbuilt and ungated**, which is what T-10.1 fixed; now **superseded by v2**)
remain for lineage:

![Module page — v1 top](../design/explorations/module-run-v1-page.png)
![Module page — v1 proof card, call-it, footer](../design/explorations/module-run-v1-proof.png)

## Mid-phase revision (2026-06-15) — empowerment loop + terminal-only scope

Pressure-testing the v1 prototype ("Proven by you" after a single run)
surfaced changes that reshape what this phase builds. They are routed into
CP-F via
[`module-run-v2-instruction.md`](../design/explorations/module-run-v2-instruction.md)
(the design side) and recorded here (the build side). **These supersede the
matching points below where they conflict.**

1. **"Proven by you" is dead; replace it with an honest evidence readout —
   not a game.** Nobody tests a module once. The Tested metric (T-10.11)
   becomes a **plain factual description of what testing happened** —
   `Untested → Ran-not-checked → Checked once → Checked · N inputs` (copy
   pending CP-F) — **not** a ladder to climb. **No gamification:** no levels,
   ranks, points, streaks, progress meters, "1 more to reach X" nudges, or
   celebratory moments. One AI-staged pass = **Checked once** at most (the
   lowest honest label), never "Proven." Confident green is warranted only
   once the developer has judged **distinct inputs they brought** — so the
   human's contribution is real, but the page *states* it, it never rewards
   it.
2. **"That's wrong" becomes "improve the module" — a new loop, new
   architecture.** A wrong verdict must let the developer *correct the
   module without editing code*: pin the **expected output** + a *what's
   wrong* note → that correction feeds a **guided re-extraction hint** →
   the failing case flips green when the new output matches. This is a
   feedback channel from the proof loop back into extraction that does not
   exist today. **Decide its depth at CP-F (new open question #10):** ship a
   *real* guided re-extraction this phase, or *capture-and-queue* the
   correction as a pinned failing case now and wire re-extraction later.
   Default recommendation: **capture-and-queue this phase** (store the
   correction + failing target via T-10.3; surface it; defer the
   re-extraction trigger to a follow-up) to keep the phase shippable.
3. **Terminal-only runtime scope this phase.** The sandbox runs
   **terminal/CLI/library one-shot entrypoints only.** Everything else gets
   an **honest "runnable here: not yet"** state (neutral, never red): needs
   network, needs secrets, wants interactive stdin, long-running/non-
   terminating, UI module, or "cannot determine how to run." This is a
   **runnability classification** the runner must produce (see T-10.2
   addendum) and the page must render as a distinct category from a failed
   run.
4. **UI-module runner (T-10.13) is deferred.** In-browser launch ships in a
   later phase. This phase shows the UI-module state as a clearly *future*
   affordance, not a working button. T-10.13 is descoped to "detect + label
   as not-yet-runnable" (see its updated header).
5. **Agent runs ≠ human verdicts in the readout.** T-10.12's
   agent-initiated receipts share the evidence pile but are stated
   separately ("N agent runs · M you checked") and **alone never count as
   human-checked evidence** (new open question #8).
6. **Golden-diff must tolerate non-determinism.** Many modules don't
   reproduce byte-identical output; "differs from golden" must not read as a
   regression when difference is expected (folds into open question #4).

## Future-vision context (disposable software) — run-time seams to protect

This is *context*, not phase scope. A 2026-06-15 engineering conversation
sharpened where the product is going, and "how you run a module" is central
to it — so two seams must stay open while we build this phase. **Do not
build either now; just don't architect them out.**

The direction: modules trend **smaller and lower-level** (e.g. a String
Slugification Utility), and **compose upward** — low-level gunks stack into
**parent gunks**, which the **AI composes** into larger capabilities. Each
utility has two usage paths: the one the **human** gave (the "Call it"
snippet) and the one the **AI discovers** (`get_gunk` + `run_gunk` over
MCP). The payoff verticals are **internal tools** (possibly hosted) and the
headline one, **disposable software for other people** — plus **fewer
tokens**, because an agent team reuses *verified* bricks instead of
re-deriving them.

**Why Phase 10 already serves this (no run-mechanism change needed):**
low-level pure functions are the terminal-only runner's *best* case
(deterministic, no network/secrets, an instant happy-path check); the
per-module coverage loop + the MCP `run_gunk` tool are exactly "let the AI verify a brick
before it builds with it" — the prerequisite for trustworthy composition and
the token-savings story.

**The two seams to protect:**
1. **Composition / parent-gunk runs.** Bundles today are deliberately
   **self-contained** (a core trust property — "Self-contained: Passed"), so
   running a *parent* gunk whose entrypoint calls *child* gunks is a future
   capability, not today's model. The T-10.2 sandbox copies **one** bundle
   into the run dir; design that copy/resolve step so it can later become
   "copy the bundle **+ its resolved gunk-deps**" and so entrypoint
   resolution can later span multiple gunks. Single self-contained modules
   only this phase.
2. **Verified state must eventually be machine-readable.** For an AI to
   *choose* which bricks to compose, each module's evidence/verified state
   must eventually surface over MCP (`get_gunk`). The v6 store (T-10.3) is
   app-only today; T-10.12 already notes the agent-receipt/store overlap.
   Keep this in view — don't lock the evidence data somewhere MCP can never
   reach.

## How to read this document

Written to be executed by an AI agent **with a human ("me") in the loop**.
Each task has the same shape:

- **Task execution (agent prompt):** the literal instruction block.
- **Refining loop:** iterate-until-good cycle.
- **Human-in-the-loop (me):** what I review or provide. The agent **must
  stop at every `[HOLD FOR ME]` gate.**
- **Acceptance:** objective done criteria.

### Working agreement for the agent

1. One task at a time, in order, unless I say otherwise.
2. After any visible change: `swift build`, run the app (`make app` when
   packaging matters), capture a screenshot of the affected surface, paste
   it in your summary. After any engine/mcp change: `bun test` in that
   package.
3. Never proceed past `[HOLD FOR ME]` without my explicit approval.
4. Keep each task PR-sized and reversible.
5. **Scope expands this phase — deliberately.** Phases 8–9 froze
   `engine/`, `mcp/`, and `Store/Schema.swift`. Phase 10 **must** touch all
   three because the whole point is *execution*: a sandbox runner, a new
   MCP run/test tool, and store state for receipts. Those are unlocked
   here, but each risky one ships **behind an ADR and tests** (the sandbox
   model = a new ADR; the MCP run tool = a new ADR or an ADR-0001 amendment;
   the schema change = a forward migration with backfill tests). No other
   relitigating of frozen Phase 8/9 decisions.
6. `swift test` and the relevant `bun test` stay green after every task.
7. Use the frozen design system (`Design/` tokens + components) and the
   **toolbox-v2** styling constraints: glass material on the floating
   controls layer only (breadcrumb bar, toolbars, overlays), solid graphite
   surfaces for content; mono **only** for paths/code/terminal output;
   accent green **only** on earned, meaningful state (agent-ready, a passed
   run, a Proven tier); amber = needs the human; red = failed. Do not
   re-tune the palette — toolbox-v2 is locked.
8. **Safety is a feature, not a footnote.** Anything that executes
   extracted code (T-10.2, T-10.7+, T-10.12, T-10.13) carries the
   first-run consent treatment and respects the sandbox contract from
   T-10.2. Never silently run code, never silently write into the user's
   filesystem outside the sandbox run directory.

## Decisions locked in (do not relitigate)

- **The module surface becomes a full page, not a sheet.** module-run-v1
  reverses toolbox-v2's "detail = centered glass sheet" and T-8.4's interim
  inline pane: clicking a module **navigates** (breadcrumb back, not
  dismiss). Nothing pre-builds the glass-sheet detail container.
- **Console-first; evidence renders inside the console** *(v2 supersedes
  v1's receipt-first/terminal-demoted framing).* The page hero is the **run
  console**; the before/after evidence is the **diff receipt rendered inside
  the console** as terminal *text* (per artifact type — text diff, structural
  JSON diff, audio/metadata compare), not a separate floating card. The
  **coverage ledger** (right rail) states which input classes are proven.
  Provenance, the call-it snippet, the requirements readout, the file list,
  and `view run →` demote into the **advanced footer**.
- **The developer is the judge — and the improver.** A run gets a developer
  verdict (**"That's right" / "That's wrong"**). A "right" verdict **pins a
  golden example**; future runs and source re-extractions diff against it.
  "Wrong" is a first-class amber state (*Needs you*), warmer than "needs
  approval" — and per the 2026-06-15 revision it **opens the improve loop**
  (pin the expected output + note → guided re-extraction or capture-and-
  queue), so the developer corrects the module *without editing code*.
- **The agent is the second runner.** An MCP tool lets the AI system run a
  module's entrypoint in the same sandbox and get the same receipt back, so
  an agent can verify before it uses. This is the user's explicit Phase 10
  ask ("the AI needs to test these modules as well").
- **No "Proven" word, no leveling rule — coverage by input class.** Evidence
  is stated as **coverage across four input classes** (happy path · your own
  inputs · edge cases · adversarial), each a plain count — never a tier to
  climb, no progress bar, no celebration. One AI-staged pass registers as a
  single check under *Happy path* (the lowest honest fact), never "Proven."
  The one consequential claim the page makes is the **sign-off**: whether the
  module is *ready to connect to your agent*, gated on real coverage
  (including at least one input the developer brought). Settled at CP-F in
  [module-run-v2.md](../design/explorations/module-run-v2.md) open question #1.
- **A real terminal, sandbox-bounded.** The expert path is a working
  terminal (developer inputs + one-click example inputs); the guided path
  is a typed input surface. They coexist. The boundary is **sandbox
  guarantees** (fs scope, network, timeouts), stated in the UI, not waved
  at. First-run consent applies to both.
- **UI modules launch the browser** *(eventual; **deferred** per the
  2026-06-15 revision — this phase is terminal-only and only **detects +
  labels** UI modules as not-runnable-here, see T-10.13)*. If a module's
  output *is* UI, running it launches the user's external browser at the
  served surface. In-app preview is explicitly **out**.
- **Two surfaces, never merged.** *Extraction runs* (`view run →`, the
  T-8.6 `RunInspectorView`) answer "what did gunk do to make this." *Smoke
  runs* answer "what does the module do." They link but never share a
  screen.
- **No fabricated usage numbers.** Smoke-run receipts are the first
  *honest* usage signal; they feed the Library `heroRank` `// FUTURE: rank
  by uses/week` seam. Until that seam is wired, ranking stays on its
  documented fallback.
- **Explicitly out:** dependency-graph visualizations, run-history charts,
  in-app code editing, metrics dashboards, a "test suite" UI, REPL of
  arbitrary shell beyond the sandbox-bounded terminal.

## Hard data facts (verified against the codebase — do not fight these)

1. **Nothing executes a module today.** There is no smoke run, no "Call it"
   runner, no sandbox. The only code execution that exists is an *optional*
   build-verify compile check (`engine/src/extract/buildVerify.ts`,
   `spawnSync` of `tsc`/`dart analyze`/etc. in a throwaway `mkdtempSync`
   temp dir) — and the app spawns the engine **without** `--verify-build`
   by default, so most stores have an empty build receipt. T-10.2 builds
   the real runner; do not assume one exists.
2. **The "terminal receipt in the store" is actually trace JSON, not a DB
   column.** The build verify `command` + `log` live in
   `~/.gunk/runs/<runId>/trace.json` (`trace.verification.build[]`), read
   by `BrowseModel.indexBuildVerification` keyed by normalized `bundlePath`,
   surfaced in `ModuleDetailView`'s "Build verification" section. It is the
   *pattern* to imitate (a captured command + log rendered in the UI), but
   smoke-run receipts need **durable per-module storage**, not ephemeral
   trace JSON — that is T-10.3.
3. **Schema is at v5; `gunks` already has `provider` + `model`** (Phase 9
   T-9.2). Adding smoke-run/example/tested state is a **v6** migration
   (app-only — `mcp/src/schema/migrate.ts` `LATEST_VERSION = 4` early-
   returns on higher stores, and every MCP read uses an explicit column
   list, so new columns/tables are invisible to it). The store lives at
   `~/.gunk/store.db`; bundles at `~/.gunk/modules/<gunk_id>/` (**not**
   `~/Library/gunk/bundles/`).
4. **Entrypoints carry symbols.** `RunTrace.Module.surface: [{path, symbol?}]`
   → `BrowseEntrypoint(path:symbol:)` with `label` = `"path · symbol"`
   (`BrowseModel.indexTraces`, fallback `manifestEntrypoints` parsing
   `gunk.yml`). Engine origin: refiner LLM `entrypoints: [{path, symbol}]`
   → `Module.surface`. This feeds the "Call it" snippet (T-10.5) and the
   terminal pre-fill (T-10.7).
5. **Requirements data exists but is not surfaced.** Module detail shows
   shared-dependency *paths* (`RunTrace.Module.sharedDeps`). The engine has
   a real `DependencyManifestParser`
   (`engine/src/analyze/dependencyManifest.ts`: package.json, pubspec,
   requirements.txt, pyproject, go.mod, cargo, Gradle, Maven) but it runs
   only at the pipeline "fingerprints" stage and is **not** persisted per
   module — and `ManifestWriter` writes **empty `deps` stubs** into
   `gunk.yml`. T-10.6 closes this gap.
6. **Module detail is an inline pane, and there is no page navigation.**
   `ModuleDetailView` (private in `BrowseView.swift`) renders in an `HStack`
   right pane when `selectedGunkId` is set; comments mark it "interim" until
   this exact exploration. `AppShellView` uses a `NavigationStack` with only
   `.navigationTitle("gunk")` — **no breadcrumb, no full-page push.** T-10.4
   builds it. Sheets exist for `RunInspectorView`, `MCPSetupView`, and the
   sources panel.
7. **The extraction-run inspector already exists and is correct.**
   `RunInspectorView.swift` (sheet; `RunInspectorContext` = `.all` /
   `.source` / `.mostRecentFailure`), reading `RunTraceStore.recentTraces()`
   from `~/.gunk/runs/<id>/trace.json`; `RunTrace.provider`/`.model` are
   top-level. The module-page `view run →` line is its module-detail entry
   point — reuse it, do not rebuild it.
8. **MCP has exactly four read tools and no run tool.**
   `mcp/src/server/registerTools.ts` wires `list_gunks`, `list_sources`,
   `search_gunks`, `get_gunk`. They open the store via `bun:sqlite`
   (`openDefaultStore()` → `~/.gunk/store.db`) with explicit column lists,
   query, and `db.close()`. T-10.12 adds the first **write/execute** tool —
   the largest change to the MCP contract since Phase 2, hence its own ADR.
9. **The app spawns subprocesses via `Process()`**
   (`SourceProcessingRunner` → `ProcessEngineLauncher`, `EngineLauncher.swift`;
   binary resolved by `EngineBinary.resolve()` → `GUNK_ENGINE_BIN` /
   bundled `gunk-engine` / `bun run` dev). The MCP binary installs to
   `~/.local/bin/gunk-mcp` (`MCPBinary.ensureInstalled`). The sandbox
   runner (T-10.2) follows these spawn/resolve patterns but adds the
   sandbox wrapper they lack.
10. **No Tested/Proven/golden state anywhere in product code.**
    `ModuleCellState` is `.agentReady` / `.needsApproval` / `.notInToolbox`.
    "smoke", "tested", "golden", "proof" appear only in docs. All of it is
    net-new here.
11. **Design system is ready.** `Design/BrandColors.swift`
    (`accent`, `warning`, `danger`, `success`, `providerAccent(for:)`),
    `BrandMotion`, `BrandMetrics`, `ProviderBadge` all exist and are the
    only styling vocabulary to use.

## Checkpoint map

| Gate | What I review | Blocks |
| --- | --- | --- |
| CP-F | Design gate: full module page + **all** smoke-run states + the seven open-question decisions (incl. the coverage model and sandbox-promise copy) | all visual work (T-10.4+) |
| CP-G | The **sandbox/execution contract** (ADR + what the sandbox promises) — security-sensitive | T-10.7+, T-10.12, T-10.13 |
| CP-H | The **store migration** (v6: receipts, examples, test counts) — schema + backfill | T-10.7, T-10.9, T-10.10, T-10.11 |
| CP-I | The first real smoke run **end-to-end** on my real store (consent → run → receipt) | T-10.8+ |
| CP-J | The **coverage sign-off rule** as implemented (which input classes earn *Ready to connect*) | phase exit |
| CP-K | The **MCP run/test tool** exercised by a real agent against my Cursor | phase exit |

---

## T-10.1 — Design gate: the full module page, every run state, the open questions (CP-F)

**Owner:** me (Claude Design) + agent (documentation)
**Checkpoint:** CP-F — **CLEARED 2026-06-15.**

> **Status: done.** The Claude Design HTML export landed and is saved as
> [`module-run-v2.html`](../design/explorations/module-run-v2.html)
> (+ [`module-run-v2-coverage.png`](../design/explorations/module-run-v2-coverage.png)).
> The approved design is recorded in
> [`module-run-v2.md`](../design/explorations/module-run-v2.md): "Proven by
> you" is replaced by the **coverage ledger** (happy path · your own inputs ·
> edge cases · adversarial — coverage, **not** a tier ladder), the **run
> console** is the page hero, and all **ten** open questions are resolved
> into recorded decisions there. Key load-bearing answers for the build:
> runnability is **terminal-only** with Python/Node first and a
> cannot-determine fallback (#9, feeds T-10.2); the improve loop is
> **capture-and-queue** this phase with re-extraction deferred (#10); agent
> runs are counted **separately** and never advance the sign-off alone (#8).
> Build resumes at T-10.2.

### Goal
Get an approved, complete visual + product target before any module-page
work ships. The two existing PNGs show **only** the resting "Proven" state;
this gate produces the missing states and settles the product decisions the
exploration left open. (Phase 8/9 lesson: an approved exploration needs an
explicit doc + decisions, or structural work builds on the wrong look.)

### Files
- `docs/design/explorations/` (the Claude Design **HTML export**
  `module-run-v1*.html` — *source of truth when it lands* — plus new
  state screenshots)
- `docs/design/explorations/module-run-v1.md` (updated: resolve its
  "Open questions" section into decisions, add the new screenshots)

### Task execution (agent prompt)

> 1. Write the revision instruction for Claude Design covering the states
>    the PNGs do **not** show, each as its own screen. **The current driving
>    instruction is
>    [`module-run-v2-instruction.md`](../design/explorations/module-run-v2-instruction.md)**
>    (the empowerment revision); the list below is its checklist:
>    - **The honest evidence readout** (replaces "Proven by you"): each
>      evidence state on the page state line **and** the Library cell, stated
>      as a plain fact (a count/descriptor), **never** as a level, rank, or
>      badge-to-collect — no progress meter, no "next rung" nudge, no
>      celebration. One AI-staged pass = the lowest honest state, never
>      "Proven."
>    - **Smoke run states:** never-tried, **first-run consent** (states the
>      command + working directory + sandbox promise without reading like a
>      scary system dialog), running/streaming terminal, passed (earned
>      green), failed (red), resting receipt.
>    - **The "That's wrong" → correct → fix loop:** the inline "what
>      should it have done?" (pin expected output + note), the "fix it" /
>      guided-re-extraction state, the resting state with an open failing
>      case, and **"Try to break it"** (a failing adversarial input records a
>      plain known-limitation note, not a red failure and not a reward).
>    - **Honest "runnable here: not yet" states** (terminal-only scope, all
>      neutral — never red): needs network, needs secrets, wants interactive
>      stdin, long-running/non-terminating, **UI module (deferred)**, and
>      "cannot determine how to run."
>    - **Typed input surface** (stage 2): prefilled-demo, developer-swapped,
>      invalid input, missing-requirement, file-drop-well.
>    - **The effort spectrum in one composition:** Try it → swap input →
>      *save as example*, without three competing CTAs.
>    - **Saved examples:** the module's named-case list, re-run, diff vs
>      golden, and a **failing/flagged** case; plus the **batch
>      reconciliation** after a re-extraction ("4 pass · 1 broke").
>    - **"How this works"** disclosure: closed (one quiet affordance) and
>      open (analysis layout inside the page).
>    - **Evidence readout** on the Library cell at each state — *must not
>      break the one-trust-verdict-per-cell rule* (it is a quiet factual
>      metric, not a second trust verdict and not a badge-to-collect) —
>      including how **agent runs** read distinctly from human-checked ones
>      ("N agent runs · M you checked").
>    - **Needs-you** on the cell and on the page (warmer than needs-approval).
> 2. Put the seven open questions from `module-run-v1.md` §"Open questions"
>    in front of me as explicit product decisions and record my answers in
>    the updated doc (do not invent them):
>    - the **leveling rule** (what evidence earns each Tested tier; the
>      lowest *honest* label for "one synthesized example passed");
>    - the **sandbox promise** (exactly what the terminal may/may not touch,
>      and the consent + terminal-badge copy);
>    - terminal vs typed inputs (one composition or two tabs; what the
>      terminal pre-fills);
>    - golden-diff semantics per artifact type (text / structural JSON /
>      audio);
>    - the re-extraction-breaks-golden resolution flow (where the developer
>      sees and fixes it);
>    - breadcrumb navigation mechanics (does the grid keep scroll/selection
>      on back; sidebar-badge deep-link → scoped grid → page → back);
>    - where "How this works" lives on the page.
>    Plus the three new questions from the mid-phase revision:
>    - **#8 agent vs human evidence:** how agent-initiated runs (T-10.12)
>      appear in the readout without volume masquerading as human-verified
>      quality (agent runs alone never count as human-checked evidence);
>    - **#9 runnability classification:** what gunk keys on to decide
>      terminal-runnable vs "can't prove here," and how confident it must be
>      before it offers a run button;
>    - **#10 the improve loop's depth:** does a developer correction trigger
>      a real guided re-extraction this phase, or is it captured-and-queued
>      (pinned failing case now, re-extraction wired later — the recommended
>      default).
> 3. Hand the instruction to me; I run the iteration in Claude Design and
>    return the HTML export + screenshots.
> 4. When I return an approved iteration, save the assets into
>    `docs/design/explorations/`, fold the answers into
>    `module-run-v1.md` (verdict line, what is locked, what changed, new
>    constraints), and cross-link it from the roadmap Phase 10 item.

### Human-in-the-loop (me)
- `[HOLD FOR ME]` CP-F: I produce and approve the full set of states and
  answer all seven open questions. No visual/page work (T-10.4+) starts
  before this clears. (T-10.2 and T-10.3 — the sandbox and the store — may
  start now; they are foundation, not visual.)

### Acceptance
- An approved exploration (HTML export + screenshots) covering every
  smoke-run state, the typed-input surface, saved examples, "How this
  works", the Tested tiers, the UI-module state, and Needs-you exists;
  `module-run-v1.md`'s open questions are all resolved into recorded
  decisions; cross-linked from the roadmap.

---

## T-10.2 — Sandbox & execution runner foundation (CP-G)

**Owner:** agent
**Checkpoint:** CP-G — **implementation landed, awaiting Mark's approval.**

> **Status: built, pending CP-G.** The sandbox model is recorded in
> [ADR-0016](../adr/0016-sandbox-execution-model.md) (app-side Swift,
> `sandbox-exec` deny-by-default profile, documented reduced-isolation
> fallback, no unbounded `Process`). The runner lives in
> `app/Sources/GunkApp/Run/` — `SmokeRunResult.swift` (result + runnability
> + `RunInput`), `RunnabilityClassifier.swift` (#9 terminal-only/
> cannot-determine), `EntrypointResolver.swift` (Python/Node first),
> `RunSandbox.swift` (Seatbelt profile + wrap), `SmokeRunner.swift`
> (streaming + buffered core, throwaway bundle copy, scoped writes, no
> inherited env, hard timeout). Tested in `SmokeRunnerTests.swift` (25 cases:
> classification, command resolution, profile, fake-executor orchestration,
> real-`/bin/sh` pass/fail/timeout/cwd). `swift build` + `swift test` green.
> **No store writes, no UI.** The **security-review subagent has run** and its
> three medium findings are addressed (fail-closed when the sandbox can't be
> applied — never a silent downgrade; entrypoint-path validation +
> in-bundle containment; process-group teardown on timeout); see ADR-0016
> §"Hardening from the security review." Still needs Mark to approve the ADR
> before anything calls the runner. **Note:** `sandbox-exec` cannot nest, so
> the live-sandbox path only applies when gunk runs unsandboxed (the normal
> case); CI/agents that run sandboxed exercise the pure logic + fallback.

### Goal
A reusable, **sandbox-bounded** capability to execute a module's entrypoint
against its extracted bundle and capture a structured result (exit status,
stdout, stderr, duration, output artifacts) — with **stated guarantees**
about filesystem scope, network, and timeouts. No UI; this is the engine
the developer's "Try it" (T-10.7) and the agent's MCP tool (T-10.12) both
call. This is the riskiest, highest-leverage piece, so it lands first and
behind a security review.

### Why an ADR
The sandbox model is a hard-to-reverse, security-sensitive decision (what
isolation primitive, what the promise to the user is). It gets its own ADR.

### Files
- `docs/adr/00NN-sandbox-execution-model.md` (new — next free ADR number)
- The runner. **Decide the home in the ADR and state why:** either
  - app-side Swift (`app/Sources/GunkApp/Run/SmokeRunner.swift` +
    `RunSandbox.swift`, spawning via `Process()` like
    `EngineLauncher.swift`, wrapped in `sandbox-exec`/an App-Sandbox-
    compatible profile), or
  - an engine subcommand (`engine/src/run/*` + a `gunk-engine run` CLI
    verb) invoked the way decomposition already invokes the engine.
  Recommend app-side Swift unless the ADR finds a reason it must be the
  engine (the runner needs the macOS sandbox primitives, which the Swift
  app reaches more directly).
- Tests alongside whichever home is chosen
  (`app/Tests/GunkAppTests/SmokeRunnerTests.swift` or
  `engine/test/run.test.ts`).

### Task execution (agent prompt)

> 1. **Write the ADR first** and stop for me: choose the isolation
>    primitive and state the concrete promise — working directory pinned to
>    a throwaway copy of the bundle (never the user's source), network
>    **off** by default, a hard timeout (propose a default, e.g. 30s),
>    output written only inside the run directory, env vars passed
>    explicitly (sensitive ones never echoed). Reference how
>    `buildVerify.ts` already does a throwaway `mkdtempSync` copy as the
>    nearest existing pattern, and how `EngineLauncher`/`MCPBinary` resolve
>    binaries and inherit env — your sandbox tightens these, it does not
>    copy them wholesale.
> 2. Define the result type: `{ runnability, command, exitCode, stdout,
>    stderr, durationMs, timedOut, outputArtifacts: [path], startedAt }`
>    where `runnability` is the classification from step 3b
>    (`terminal-runnable` | `needs-network` | `needs-secrets` |
>    `interactive-stdin` | `long-running` | `ui-module` |
>    `cannot-determine`). Streaming must be supported (incremental
>    stdout/stderr for the live terminal in T-10.7) **and** a buffered
>    one-shot mode (for the MCP tool in T-10.12).
> 3. Resolve the entrypoint command from the stored entrypoints + language
>    (Hard data fact 4): e.g. Python `python <entry>`, Node
>    `node <entry>` / the symbol import form. Where the command can't be
>    derived confidently, return a typed "cannot determine how to run"
>    result rather than guessing — the UI shows that honestly.
> 3b. **Runnability classification (mid-phase revision).** Before running,
>    classify the module into one of: **terminal-runnable** (one-shot CLI/
>    library entrypoint — the only class this phase actually executes), or a
>    typed **not-runnable-here** reason — `needs-network`, `needs-secrets`,
>    `interactive-stdin`, `long-running`, `ui-module`, or
>    `cannot-determine`. Key off existing signals (language, entrypoint
>    shape, parsed dependency manifest from Hard data fact 5, framework
>    hints); when unsure, prefer a not-runnable-here reason over a wrong
>    guess. This classification is the input to the page's neutral "runnable
>    here: not yet" category (never a red failure) and to the deferred
>    T-10.13. Return it on the result type; do not auto-run a non-terminal
>    class.
> 4. Enforce the sandbox: copy the bundle to a run dir under
>    `~/.gunk/runs/smoke/<gunkId>/<timestamp>/`, run there, deny network,
>    apply the timeout, and tear down on completion (keep the captured
>    output, drop the temp copy unless an artifact must persist). **Seam
>    (future-vision):** structure this copy/resolve step so it can later
>    become "copy the bundle **+ its resolved gunk-deps**" for parent-gunk
>    composition (see "Future-vision context" above) — copy a single
>    self-contained bundle now, but don't hard-code the single-bundle
>    assumption into the runner's shape.
> 5. **No store writes here** — this task returns the result object;
>    persistence is T-10.3/T-10.7. **No UI here.**
> 6. Tests against fixtures (no real user data): a passing entrypoint
>    returns exit 0 + captured stdout; a failing one returns non-zero +
>    stderr; a hanging one trips the timeout and reports `timedOut`; a
>    network attempt is blocked; output stays inside the run dir; an
>    un-runnable module returns the typed "cannot determine" result.
> 7. `swift build` + `swift test` (and/or `bun test`). **Run the
>    security-review subagent on the diff** and address findings before the
>    gate.

### Refining loop
- If `sandbox-exec` proves too brittle under the macOS App Sandbox /
  notarization path (it is deprecated), document the fallback in the ADR
  (a constrained `Process` with no network entitlement + scoped working
  dir + timeout) rather than shipping an unbounded `Process` — an
  unbounded runner is not acceptable.
- If streaming and buffered modes diverge, share one core and layer the two
  consumption shapes on top; do not fork the executor.

### Human-in-the-loop (me)
- `[HOLD FOR ME]` CP-G: I approve the ADR (the sandbox promise) and the
  security-review outcome before anything calls this runner.

### Acceptance
- A tested, sandbox-bounded runner returns a structured streaming/buffered
  result, enforces fs scope + no-network + timeout, and refuses to guess
  un-runnable commands; the model is captured in an accepted ADR; security
  review is clean. No UI, no store writes. Build + tests green.

---

## T-10.3 — Store: smoke-run receipts, examples, test counts (v6 migration) (CP-H)

**Owner:** agent
**Checkpoint:** CP-H — **implementation landed, awaiting Mark's review.**

> **Status: built, pending CP-H.** The v6 forward migration lands in
> `app/Sources/GunkApp/Store/Schema.swift` (`version = 6`) — two additive,
> nullable tables, no destructive change, old stores open unchanged. The
> representation decision is written into the migration comment (no separate
> ADR — nothing below is hard-to-reverse):
> - **`module_examples`** is the fixture library the coverage ledger lists.
>   Each row carries an `input_class` (`happy`/`yours`/`edge`/`adversarial`,
>   the CP-F coverage axes), so a **pinned failing case** (open question #10,
>   capture-and-queue) is an example with `expected_output` + `note`, and a
>   **known limit** is an adversarial example with a `note` — no extra tables.
>   `is_golden` is exclusive **per (gunk, input_class)** (the CP-F decision the
>   task sanctioned over "per module", because v2 coverage spans classes).
> - **`smoke_runs`** is the receipt: it stores the CP-F fields verbatim
>   (`runnability` class, `origin` human/agent per #8, exit/duration/
>   output-artifact **path**/log). `passed` is the clean-exit *fact* (nullable
>   when the module was not executed); `verdict` is the developer's separate
>   `right`/`wrong` judgement. `example_id` is the nullable input ref
>   (`ON DELETE SET NULL` — deleting an example never erases its receipts).
>
> The Tested/coverage state stays **derived** (T-10.11 owns the rule); this
> task only stores the inputs it reads — nothing is denormalized. Store API:
> `insertSmokeRun`/`recordSmokeRun` (from a `SmokeRunResult`),
> `mostRecentSmokeRun`, `smokeRuns(limit:)` (capped history), `attachVerdict`,
> `insertExample`, `listExamples`, `markExampleGolden`. **mcp divergence
> confirmed:** v6 is app-only with **no** `mcp/src/schema/v6.sql` — both the
> gunk-mcp and TS-engine migrators pin `LATEST_VERSION = 4` and early-return,
> and every read uses explicit column lists, so v6 is invisible to them
> (parity script unaffected — it only checks v0–v4). T-10.12 will read/write
> these tables explicitly when it lands. Tested in `StoreTests.swift`
> (v5→v6 upgrade leaves empty proof tables; receipt + example round-trips;
> not-executed runs store `nil` passed; golden exclusive per class;
> `ON DELETE SET NULL`). `swift build` + `swift test` green (189 tests);
> schema parity green. **No UI, no mcp/engine changes.** Still needs Mark to
> review the migration on a copy of his real store before CP-H clears.

### Goal
Durable per-module storage for everything the proof loop produces: run
receipts, golden/saved examples, and the per-module test metric the Tested
badge reads — surviving trace pruning, unlike today's build receipt (Hard
data fact 2).

### Why an ADR-adjacent write-up
Following T-9.2's pattern, write the representation decision into the task's
summary (and the migration comment) before coding. No separate ADR unless a
sub-decision proves hard to reverse.

### Files
- `app/Sources/GunkApp/Store/Schema.swift` (**v6** migration — the one
  sanctioned schema change this phase)
- `app/Sources/GunkApp/Store/Models.swift` (new record types)
- `app/Sources/GunkApp/Store/Store.swift` (read/write)
- `app/Tests/GunkAppTests/StoreTests.swift`

### Task execution (agent prompt)

> 1. Design and write up the shape before coding. Proposed tables (refine
>    against the CP-F decisions, but stay additive + nullable):
>    - `smoke_runs`: `id`, `gunk_id`, `input_ref` (which example/input),
>      `command`, `exit_code`, `passed` (nullable until a verdict),
>      `duration_ms`, `output_artifact_path` (nullable), `log` (captured
>      stdout/stderr), `created_at`. (The receipt.)
>    - `module_examples`: `id`, `gunk_id`, `name`, `input` (or input ref),
>      `is_golden` (bool), `verdict` (`right`/`wrong`/null), `created_at`.
>      (Saved/golden examples — the developer's fixture library.)
>    - Optionally `entrypoint_signatures` if input signatures need
>      persistence beyond what the trace/`gunk.yml` already give (decide
>      from CP-F; prefer deriving over storing if the trace suffices).
>    - The **Tested tier** is a *derived* value (count of passing examples,
>      distinct inputs, recency — per the T-10.1 leveling rule), computed in
>      the model layer, **not** a stored denormalized tier unless the
>      leveling rule proves expensive to compute (T-10.11 owns the rule;
>      this task just stores the inputs it needs).
> 2. Add the forward migration to `Schema.swift` (`version = 6`; new tables;
>    no destructive change). Old stores open unchanged.
> 3. **mcp divergence note (flag for CP-H):** v6 is app-only;
>    `mcp/src/schema/migrate.ts` `LATEST_VERSION = 4` early-returns and uses
>    explicit column lists, so it never trips on v6. T-10.12 (the MCP run
>    tool) will read/write these tables explicitly when it lands — note that
>    dependency here, do not pre-build it.
> 4. Store API: insert a receipt, read a module's most-recent receipt + its
>    history (capped — receipts, not a dashboard), insert/list examples,
>    mark an example golden, attach a verdict to a run.
> 5. Tests: an old store opens and upgrades to v6; a receipt round-trips; an
>    example round-trips; marking golden is exclusive per module (or per the
>    CP-F decision); no test touches the real store path.

### Refining loop
- If `output_artifact_path` rows could leak large blobs, store the **path**
  to the artifact in the run dir, never the bytes; prune with the run dir.
- Keep receipt history bounded (e.g. last N) so this never becomes a
  history table feeding a chart — that is explicitly out.

### Human-in-the-loop (me)
- `[HOLD FOR ME]` CP-H: I review the migration on a **copy of my real
  store** — it must open clean, and the new tables must be empty + correct
  on an upgraded store.

### Acceptance
- A v6 forward migration adds receipt/example storage; old stores open
  unchanged; the Store API round-trips receipts and examples with tests; no
  fabricated or denormalized data the leveling rule should derive. Build +
  tests green.

---

## T-10.4 — Full module page + breadcrumb navigation (replaces the inline pane)

**Owner:** agent
**Checkpoint:** none (structural; implements the CP-F page shell)

### Goal
Clicking a module **navigates** to a full page with a breadcrumb
(`‹ Library › <source> › <module>`), replacing the interim inline
`ModuleDetailView` pane. Every existing detail capability moves onto the
page; the proof/run features (T-10.5+) then land on it.

### Files
- `app/Sources/GunkApp/Views/AppShellView.swift` (navigation model:
  push/pop a module-page route; breadcrumb in the controls layer)
- `app/Sources/GunkApp/Views/BrowseView.swift` (selecting a module
  navigates instead of opening the inline pane; grid reclaims full width)
- `app/Sources/GunkApp/Views/ModulePageView.swift` (new — the page; lifts
  the trust readout, files, bundle path, approve/reject, and the
  `view run →` line out of `ModuleDetailView`)

### Task execution (agent prompt)

> 1. Add a module-page route to the shell navigation (extend the existing
>    `NavigationStack` — Hard data fact 6 — with a typed `module(gunkId)`
>    destination). The breadcrumb bar reads as the glass controls layer:
>    `‹ Library` back, then `<source> › <module>`; when scrolled it gains a
>    compact trailing state chip (the trust verdict), per the second PNG.
> 2. Build `ModulePageView` from the module-run-v1 top section: state line
>    (verdict `· ★ Golden` when applicable), title + purpose, provenance
>    line `From <source> · <language> ·` provider badge `Extracted with
>    <model> · <provider> · view run →` (the `view run →` opens
>    `RunInspectorView(.source(sourceId))` — Hard data fact 7, reuse it),
>    and the 3-up trust readout (Confidence / Self-contained / Build).
> 3. **Move, don't duplicate:** lift the trust readout, files list, bundle
>    path + Open-in-Finder, and the approve/reject review block (T-8.4) out
>    of the inline `ModuleDetailView` and into the page. Approve/reject
>    confirmations and animations carry over unchanged.
> 4. Selecting a module from grid **or** list (T-9.3) navigates to the page;
>    with nothing selected the grid owns full width (no resting pane). On
>    back, the grid keeps scroll + selection per the CP-F decision.
> 5. Footer actions row: Open in Finder / Re-run source / **Delete**
>    (destructive, right-aligned, confirmed).
> 6. Delete the inline `ModuleDetailView` pane path once nothing references
>    it (`rg` first). `swift build`, `swift test`, screenshots: the page top
>    matching `module-run-v1-page.png`, the scrolled breadcrumb chip, and
>    back-navigation preserving grid state, at 960pt and default width.

### Refining loop
- If breadcrumb back loses grid scroll/selection, fix the navigation state
  retention rather than re-fetching the grid (per the CP-F decision).
- Keep the page content on solid graphite; only the breadcrumb bar is glass.

### Human-in-the-loop (me)
- I navigate Library → module → back across several modules and confirm the
  page replaces the pane cleanly and grid state survives.

### Acceptance
- Clicking a module opens a full breadcrumb page carrying every former
  detail capability; the inline pane is gone; the `view run →` line opens
  the extraction-run inspector; back preserves grid state; fits at 960pt.
  Build + tests green.

---

## T-10.5 — Copyable invocation snippet ("Call it")

**Owner:** agent
**Checkpoint:** none (smallest feature first)

### Goal
A generated, one-glance "how do I use this" snippet on the module page,
copyable in one click — built from the stored entrypoints + symbols.

### Files
- `app/Sources/GunkApp/Views/ModulePageView.swift` ("Call it" section)
- `app/Sources/GunkApp/Models/BrowseModel.swift` (snippet generation from
  `BrowseEntrypoint` — read-only/derive; no schema)

### Task execution (agent prompt)

> 1. Generate a short (≈2-line) example call per the dominant entrypoint +
>    symbol and language (Hard data fact 4): e.g. Python `from
>    audiobook_content_parsing import parse_epub` / `md =
>    parse_epub("book.epub")`, with a leading `# <purpose>` comment. Where
>    no symbol exists, fall back to the path-based import. Keep the
>    generator pure and tested.
> 2. Render it in a mono block (mono is allowed here — it is code) with a
>    **Copy** button, matching the "Call it" panel in
>    `module-run-v1-proof.png`.
> 3. `swift build`, `swift test`, screenshot the snippet + a copied state.

### Refining loop
- If a module exposes several entrypoints, show the primary one with a quiet
  way to switch — do not dump a wall of snippets.

### Human-in-the-loop (me)
- I copy a snippet and confirm it reads as a real, runnable call.

### Acceptance
- A correct, copyable snippet generated from entrypoints+symbols renders on
  the page; generator is pure + tested. Build + tests green.

---

## T-10.6 — Requirements readout ("To run this elsewhere, you need")

**Owner:** agent
**Checkpoint:** none (absorbs the old Phase 9 dependencies panel)

### Goal
Reshape shared-dependency *paths* into a portability readout: **runtime**
(e.g. `Python ≥ 3.11`), **packages** (e.g. `ebooklib`, `markdownify`),
**env vars** — the right-rail panel in the PNGs.

### Files
- `app/Sources/GunkApp/Views/ModulePageView.swift` (requirements panel)
- `app/Sources/GunkApp/Models/BrowseModel.swift` (requirements derivation)
- Possibly `engine/src/extract/manifestWriter.ts` +
  `engine/src/analyze/dependencyManifest.ts` (persist parsed deps into
  `gunk.yml` so the app reads real packages, not empty stubs — Hard data
  fact 5)

### Task execution (agent prompt)

> 1. Decide the data source and report it: the engine *can* parse real
>    deps (`DependencyManifestParser`) but does **not** persist them per
>    module — `gunk.yml` `deps` is empty stubs today. Either (a) surface
>    real requirements by **persisting** the parsed runtime/packages/env
>    into the bundle manifest at extraction (small engine change, allowed
>    this phase, behind tests), or (b) parse the bundle's own manifest
>    files app-side at view time. Recommend (a) — the data is already parsed
>    upstream; persisting it is faithful and avoids re-parsing. State your
>    choice.
> 2. Render the three-row readout (runtime / packages / env vars) on solid
>    surface, packages as neutral chips (Hard data fact 11), `none` when
>    empty — never invent requirements. Mono only for the version
>    constraint token if shown as code.
> 3. If (a): add the persistence behind engine tests; keep it additive to
>    `gunk.yml` so older bundles without it fall back gracefully (show what
>    is known, omit what is not).
> 4. `swift build` + `swift test` (+ `bun test` if engine touched),
>    screenshot the readout populated and the empty/`none` state.

### Refining loop
- If a language's manifest can't yield a clean runtime/packages split, show
  what is parseable and omit the rest rather than guessing a version.

### Human-in-the-loop (me)
- I check the readout against a real module's actual manifest and confirm it
  is honest (no invented packages/versions).

### Acceptance
- The module page shows a runtime/packages/env-vars readout derived from
  real manifest data (persisted at extraction or parsed from the bundle),
  honest about unknowns; the old "shared-dependency paths" list is replaced.
  Build + tests green.

---

## T-10.7 — Run console ("Run it"): consent → run → streaming console → receipt (CP-I)

**Owner:** agent
**Checkpoint:** CP-I

### Goal
The developer's door. One **Run it** on the module page executes the
entrypoint via the T-10.2 sandbox runner, streams stdout/stderr into the
mono **run console**, and persists a receipt (T-10.3). All states from CP-F:
never-tried, **first-run consent**, running/streaming, passed (earned
green), failed (red), resting receipt. This builds the **run console — the
page hero** (v2, not a demoted disclosure); the coverage ledger (T-10.9)
reads its receipts and the sign-off (T-10.11) reads its coverage.

### Files
- `app/Sources/GunkApp/Views/ModulePageView.swift` (Try it + terminal block
  + receipt states)
- `app/Sources/GunkApp/Run/SmokeRunner.swift` (consumed; built in T-10.2)
- `app/Sources/GunkApp/Models/BrowseModel.swift` (run orchestration, receipt
  read/write via Store)
- `app/Tests/GunkAppTests/BrowseModelTests.swift`

### Task execution (agent prompt)

> 1. **First-run consent** (per CP-F copy): before the first run of a
>    module, show the consent treatment stating the command, the working
>    directory, and the sandbox promise (from the T-10.2 ADR). Record
>    consent per module so subsequent runs don't re-ask.
> 2. Wire **Try it** to `SmokeRunner` in **streaming** mode: render
>    incremental stdout/stderr into a mono terminal block (mono allowed —
>    terminal output), with a running spinner/elapsed indicator. No layout
>    shift when it appears (D15).
> 3. On completion, persist the receipt (T-10.3) and resolve to: **passed**
>    (exit 0 — the receipt line takes earned accent green: "Last tried:
>    passed · 1.8s"), **failed** (non-zero/timeout — red, with the stderr in
>    the disclosure), or **un-runnable** (the typed "cannot determine"
>    result rendered honestly, not as a failure).
> 4. The run console is the page **hero** (v2): a `>_ run console` bar with
>    the resolved entrypoint and a status chip (`idle → running → pass/fail`),
>    the composed command line + streamed stdout/stderr in the console body.
>    It is **not** a collapsed disclosure. The resting state on re-visit
>    shows the last receipt in the console, ready to re-run.
> 5. Keep the two-surfaces rule: this is the *smoke run*; do not merge it
>    with the `view run →` extraction inspector.
> 6. `swift build`, `swift test`, screenshots of every state (never-tried,
>    consent, running, passed, failed, resting receipt) staged via the
>    runner's test seams / `GUNK_DEBUG_*` hooks where live execution is
>    impractical to screenshot deterministically.

### Refining loop
- If streaming output floods the block, virtualize/scroll it; never let it
  grow the page or steal focus.
- If a passed run's green competes with the trust readout's green, the
  console status chip's green is fine (it is earned meaning) but keep one
  *headline* verdict — the coverage ledger + sign-off (T-10.9/T-10.11) own
  the page's honest claim once they land.

### Human-in-the-loop (me)
- `[HOLD FOR ME]` CP-I: I run a **real** module on my machine end-to-end —
  consent once, watch it stream, see the receipt persist and survive an app
  relaunch.

### Acceptance
- Run it executes the entrypoint in the sandbox with first-run consent,
  streams output, persists a receipt that survives relaunch, and renders all
  CP-F states in the run console hero; never-merged with the extraction
  inspector. Build + tests green.

---

## T-10.8 — Intent toolbar + typed input (the developer brings their own input)

**Owner:** agent
**Checkpoint:** none (implements CP-F's intent-toolbar + typed-input design)

### Goal
The empowerment move, expressed as the console's **intent toolbar** (v2):
verb tabs that compose the command and map 1:1 to the coverage classes —
**Shipped example**, **My own input**, **Try to break it** (adversarial),
with a `swap input` affordance. Selecting **My own input** surfaces compact
native controls derived from the entrypoint's input signature — file drop
well, text field, dropdown — **prefilled with the staged demo input**, every
value swappable. The active verb tints the console (green for a normal run,
amber for "break it"). The run button always works untouched (the T-10.7
zero-touch floor is preserved).

### Files
- `app/Sources/GunkApp/Views/ModulePageView.swift` (the intent toolbar +
  input surface + the effort spectrum: Run it → swap input → save as example)
- `app/Sources/GunkApp/Models/BrowseModel.swift` (input signature →
  controls; pass the chosen input to `SmokeRunner`)

### Task execution (agent prompt)

> 1. Build the **intent toolbar** as verb tabs that compose the console
>    command and map 1:1 to the coverage classes (Shipped example / My own
>    input / Try to break it). Under **My own input**, derive the input
>    controls from the entrypoint signature (symbols/params + the CP-F
>    decision on signatures): file-of-type, string, number, choice, env var.
>    Prefill with the AI-staged demo input; every value is swappable in one
>    gesture (not a form-filling session).
> 2. The file drop well accepts the typed file; invalid input and
>    missing-requirement states read as **quiet guidance** ("this entrypoint
>    takes a `.epub`"), not system warnings (CP-F).
> 3. The **effort spectrum** in one composition (no three competing CTAs):
>    zero-touch Run it → swap an input → **save as example** (persists the
>    developer's input + verdict as a named case, **tagged by input class**
>    — `yours`/`edge`/`adversarial` — so it lands in the right coverage node;
>    T-10.10 owns the passing-checks list; this task wires the "save" action
>    and stores it via T-10.3).
> 4. Inputs respect the sandbox boundary (file-size caps, no network, env
>    vars marked sensitive never echoed into receipts — from the T-10.2
>    contract).
> 5. `swift build`, `swift test`, screenshots: prefilled demo, developer-
>    swapped, invalid input, missing requirement, file-drop-well.

### Refining loop
- If a multi-input entrypoint crowds the page, follow the CP-F composition;
  do not invent a new layout. If signatures are unreliable for a module,
  fall back to the terminal path (T-10.7) and say so quietly.

### Human-in-the-loop (me)
- I swap in my own input on a real module and confirm it runs my data, not
  the demo's.

### Acceptance
- The page renders signature-derived input controls prefilled with the demo
  input, all swappable; invalid/missing states are quiet guidance; the
  effort spectrum reads as one composition; inputs respect the sandbox
  boundary. Build + tests green.

---

## T-10.9 — Coverage ledger: input-class spine + in-console diff receipt + developer verdict + known limits

**Owner:** agent
**Checkpoint:** none (the heart of the page; depends on CP-I)

> **Revised 2026-06-16 to match the merged v2 design
> ([module-run-v2.md](../design/explorations/module-run-v2.md), CP-F
> approved).** There is **no "proof card"** anymore. The before/after
> evidence renders **inside the run console** (T-10.7) as terminal text; this
> task builds the **coverage ledger** — the right-rail readout that states,
> plainly and un-gamified, which **classes of input** have actually been
> proven. The salvaged-and-still-true parts of the old proof card live on
> here: the synthesized demo input, artifact-aware before/after rendering,
> the developer verdict (**That's right / That's wrong**), golden pinning +
> diffing, the wrong→fix capture-and-queue loop, and non-determinism
> tolerance — re-housed into the console (diff receipt) and the ledger
> (coverage spine + known limits) instead of a standalone card.

### Goal
The page's right-rail **coverage ledger**: a de-boxed spine — *not* cards,
*not* a progress meter — with one node per **input class** (**happy path ·
your own inputs · edge cases · adversarial**), each a plain count, mapping
1:1 to the console's intent-toolbar verbs (T-10.8). Plus: the before/after
**diff receipt rendered inside the run console** as terminal text, the
developer **verdict** that pins a golden / opens the wrong→fix loop, and the
**Known limits** record. This is what makes a module *demonstrate* coverage
instead of *assert* a badge. The sign-off gate (`Connect to my agent`) it
feeds is T-10.11.

### Files
- `app/Sources/GunkApp/Views/ModulePageView.swift` (coverage-ledger rail:
  class spine + known-limits record; the in-console **diff receipt** +
  artifact renderers; the verdict zone in the console footer; the inline
  correction inside the console body)
- `app/Sources/GunkApp/Models/BrowseModel.swift` (coverage derivation per
  input class; golden diff; verdict → Store; known-limit / failing-case
  capture via T-10.3)
- Synthesized-demo generation: `engine/src/run/demo.ts` (new) **or** an
  app-side LLM call — decide and report (the engine already owns LLM access
  at extraction; generating a representative demo input there and persisting
  it is the faithful place, but it is an engine change — behind tests)

### Task execution (agent prompt)

> 1. **Synthesized demo input (the Happy path check).** Generate a small,
>    representative input for the module (the "1-chapter EPUB") so the
>    Shipped-example verb has something to prove against with zero developer
>    effort. Decide where it is generated (engine at extraction, cached; or
>    app-side on first open) and persist it (T-10.3 / bundle run dir, tagged
>    `input_class = happy`). Mark it clearly as `Demo staged by gunk`. A
>    single passing demo run is **one check under Happy path** — never
>    "Proven."
> 2. **The coverage ledger (right rail).** Render the **class spine** —
>    airy, hairlines, lists; explicitly *not* cards and *not* a progress
>    bar — one node per input class, each a plain fact with a count:
>    - **Happy path** — the shipped/synthesized demo (e.g. `1`).
>    - **Your own inputs** — distinct inputs the developer *brought* and
>      judged, with the `yours` provenance (e.g. `2 checks · 2 of your books
>      checked`).
>    - **Edge cases** — a **gap state** (dashed ring) until covered
>      (`Boundary inputs untested`), never red.
>    - **Adversarial** — a gap/amber state until exercised (`Try to break it
>      with bad input`), never red.
>    Each node maps 1:1 to a T-10.8 intent verb and links to "test →" it.
>    The counts come from T-10.3 (`module_examples.input_class` +
>    `smoke_runs`); derive them, never fabricate. **No tier ladder, no
>    level, no "1 more to unlock," no celebration** (the locked decision +
>    open question #1).
> 3. **In-console diff receipt + artifact rendering.** After a passing run,
>    render the before/after **inside the run console** as terminal *text*
>    (before / after columns), per output kind (CP-F + module-io-prompt §1):
>    markdown rendered (not source), JSON pretty-printed, audio as a playable
>    clip, image as an image, plain text plain. This replaces v1's separate
>    proof card — the console is the single evidence surface (T-10.7 hero).
> 4. **Developer verdict (console footer).** **That's right** pins the run
>    as a **golden example** (stored T-10.3, tagged by the active input
>    class — `is_golden` is exclusive **per (gunk, input_class)** per the
>    T-10.3 decision); **That's wrong** opens the **inline correction inside
>    the console body** (terminal-styled: a textarea for the **expected
>    output**, a one-line *what's wrong* note, **Pin failing case**), sets
>    the amber **Needs you** state, and **captures-and-queues** the
>    correction (open question #10): store the expected output + note + the
>    breaking input via T-10.3 and surface it as a **flagged/failing check**
>    in the ledger with a **fix** action. The guided re-extraction trigger is
>    a **deferred seam** — design the "fixing…" state but do **not** wire a
>    real re-extraction this phase.
> 5. **Golden diff + non-determinism.** Subsequent runs (and source
>    re-extractions) diff their output against the golden per the CP-F
>    per-artifact semantics (text diff / structural JSON / audio-metadata
>    compare — open question #4). When a module is marked
>    **non-deterministic**, diff **semantically/loosely** (or
>    informational-only) so "differs from golden" never reads as a
>    regression. Verdict stays **binary** (right/wrong); the note carries
>    nuance. A re-extraction break surfaces as a **flagged row** in the
>    ledger (batch reconciliation "4 pass · 1 broke", open question #5) —
>    on this page, not the Library cell.
> 6. **Known limits.** Render the recorded boundaries from "Try to break it"
>    (e.g. `known not to handle: empty file`) with a count and an empty
>    state. A known limit is an **honest record, not a failure — never red**
>    (it is an adversarial example carrying a `note`, per T-10.3).
> 7. `swift build`, `swift test` (+ `bun test` if engine touched),
>    screenshots: the coverage ledger (gap + covered classes), the in-console
>    diff receipt for each artifact kind, the right/wrong verdict + inline
>    correction, a pinned-golden resting state, a golden-diff match vs break,
>    and the known-limits record (populated + empty).

### Refining loop
- If an output kind has no clean renderer yet, fall back to plain text in
  the console (never a raw log dump as the only evidence) and leave a
  documented seam.
- If synthesized-demo generation is slow, cache it once and reuse; the
  Happy-path check must feel instant, not like summoning a model.
- The ledger is a **readout, not a dashboard** — if a class node grows busy,
  keep it a plain fact + count and push detail into the passing-checks list
  (T-10.10); never add charts or meters.

### Human-in-the-loop (me)
- I judge a real run, pin a golden, re-run, and confirm the diff statement
  is truthful; I confirm the ledger states coverage as plain facts (no
  level, no nudge) and that "right" reads as *my* judgement, not a reward.

### Acceptance
- The module page renders a coverage ledger (class spine per input class +
  known limits, all derived from T-10.3, never fabricated); the before/after
  evidence renders inside the run console as the artifact and takes a
  developer verdict that pins a golden / opens the capture-and-queue wrong
  loop; future runs diff against golden per artifact type with
  non-determinism tolerated; nothing reads as a tier ladder or "Proven".
  Build + tests green.

---

## T-10.10 — Passing checks: the coverage ledger's named-case list

**Owner:** agent
**Checkpoint:** none

> **Revised 2026-06-16 to match the merged v2 design.** These "saved
> examples" are the coverage ledger's **passing-checks list** (v2): each a
> dot + case name + a `yours` violet badge for developer-brought inputs + a
> relative time + a hover **re-run**; a failing/flagged case reads red with a
> **fix** action. They feed the per-class coverage counts (T-10.9) and the
> sign-off (T-10.11).

### Goal
Every developer action persists as an asset: a developer's input + verdict
becomes a **named, re-runnable check** pinned to the module and tagged by
**input class** — these are the coverage ledger's **passing-checks list**.
The module lists its checks, re-runs them, and diffs each against golden.

### Files
- `app/Sources/GunkApp/Views/ModulePageView.swift` (passing-checks list +
  re-run + per-check diff state, inside the coverage ledger)
- `app/Sources/GunkApp/Models/BrowseModel.swift` (examples read/write via
  Store T-10.3)
- `app/Tests/GunkAppTests/BrowseModelTests.swift`

### Task execution (agent prompt)

> 1. Render the module's checks (from T-10.3): name, the `yours` provenance
>    badge for developer-brought inputs, last verdict, last-run status, a
>    re-run action. The golden example is marked; failing/flagged checks read
>    red with a **fix** action.
> 2. Re-running an example uses `SmokeRunner` with that example's stored
>    input and diffs against golden (T-10.9), updating the receipt.
> 3. Keep it **receipts, not a dashboard** — a bounded list of named cases,
>    no charts, no run-history graph (explicitly out).
> 4. `swift build`, `swift test`, screenshots: the examples list, a re-run,
>    a matching example, and a broken (Needs-you) example.

### Refining loop
- If the list grows long, cap/scroll it per the CP-F "how many before
  clutter" decision; do not turn it into a management console.

### Human-in-the-loop (me)
- I save two examples, re-run both, and confirm they persist and diff
  correctly.

### Acceptance
- Saved examples list, re-run, and diff against golden; bounded and
  receipt-like (no dashboard); round-trip tested. Build + tests green.

---

## T-10.11 — Coverage state + the agent-connection sign-off (CP-J)

**Owner:** agent
**Checkpoint:** CP-J — **sign-off rule implemented, pending Mark's review.**

> **Revised 2026-06-16 to match the merged v2 design.** There is **no Tested
> badge and no leveling rule** (open question #1: "there is no leveling rule
> — there is a coverage readout"). The honest verdict the page makes is the
> **sign-off**: whether the module is *ready to connect to your agent*. This
> task derives the coverage state from T-10.3 data, drives the page's
> `Connect to my agent` gate + the breadcrumb bar-state chip
> (`In review` → `Ready to connect`), and expresses the same honest signal —
> quietly — on the Library cell. No tiers, no points, no "Proven".
>
> **Status: sign-off rule built (2026-06-16).** The pure derivation lives in
> `app/Sources/GunkApp/Models/CoverageState.swift` (`CoverageState.derive` +
> `BrowseModel.coverageState(for:)`), and `CoverageLedgerView` + the
> `ModulePageView` breadcrumb chip now read it from one source (the earlier
> duplicated, `≥3 classes` rule is removed). The **locked threshold** is
> applied: *ready to connect* = **Happy path covered + at least one of Your
> own inputs checked, nothing failing**; edge/adversarial deepen coverage but
> never gate it; a lone synthesized happy-path pass never unlocks it; a
> `wrong`/pinned-correction case blocks it. Tested in
> `CoverageStateTests.swift` (10 cases). `swift build` + `swift test` green
> (233 tests). **Still open within this task:** the quiet **Library-cell**
> coverage expression (`ModuleCell`) and the `heroRank` usage seam — do
> before CP-J closes.

### Goal
The honest verdict: a **coverage state** derived from which input classes
are actually proven (happy path · your own inputs · edge cases ·
adversarial), gating the **sign-off** — the greyed/locked `Connect to my
agent` flips to the earned green `Connect to my agent` **only when coverage
is honestly sufficient** (spans classes, **including at least one input the
developer brought**). It drives the module-page sign-off block + the
breadcrumb bar-state chip, and expresses quietly on the Library cell
*without* breaking the one-trust-verdict-per-cell rule. It is also the first
**honest** usage signal for the Library `heroRank` `// FUTURE` seam (still
never fabricate usage numbers).

### Files
- `app/Sources/GunkApp/Models/BrowseModel.swift` (the `coverageState`
  derivation — the sign-off rule; the `heroRank` seam update)
- `app/Sources/GunkApp/Views/ModulePageView.swift` (the sign-off block:
  locked `Not ready to connect` → earned `Connect to my agent`; the
  breadcrumb bar-state chip `In review` → `Ready to connect`)
- `app/Sources/GunkApp/Views/ModuleCell.swift` (quiet cell expression of the
  coverage signal — provenance/metric, not a second trust verdict)
- `app/Tests/GunkAppTests/BrowseModelTests.swift`

### Task execution (agent prompt)

> 1. Implement the **coverage sign-off rule** from CP-F as a **pure, tested**
>    derivation over T-10.3 data (examples + pass state by `input_class` +
>    recency). It is an **honest coverage readout**, **not** a gamified
>    ladder: no levels, points, streaks, or "next rung" nudges — it states
>    which classes are covered as plain facts. The **sufficiency threshold**
>    for the *ready to connect* sign-off is **Happy path covered + at least
>    one of Your own inputs checked** (the locked copy: "Cover happy path and
>    your own inputs to reach a confident sign-off"). Edge cases and
>    adversarial deepen coverage but are **not** required to unlock the
>    sign-off. A single synthesized Happy-path pass is **never** sufficient on
>    its own (it has no developer-brought input) and never reads as "Proven".
>    Encode the rule that **agent-initiated runs
>    alone never count as human-checked coverage** and never advance the
>    sign-off on their own (open question #8). Isolate it behind one
>    `coverageState` function with a comment pointing at the CP-F decision.
> 2. Drive the **sign-off block** on the module page: the locked state
>    (`Not ready to connect`, greyed `Connect to my agent`, with the honest
>    "cover … to reach a confident sign-off" line) flips to the earned green
>    `Connect to my agent` only when `coverageState` says sufficient. Wire
>    the breadcrumb **bar-state chip** to the same source (`In review`, amber,
>    while incomplete → `Ready to connect`, green). No layout shift on change.
> 3. Express the coverage signal on `ModuleCell` quietly — it must not
>    compete with the `.agentReady`/`.needsApproval`/`.notInToolbox` trust
>    verdict (Hard data fact 10). It is a metric/provenance mark, like the
>    provider badge — never a second trust verdict, never a badge to collect.
> 4. **Honest usage seam:** wire smoke-run receipts as the input the
>    `heroRank` `// FUTURE: rank by uses/week` seam was waiting for *only if
>    CP-F says so*; otherwise leave the seam and note that receipts are now
>    available to it. Never fabricate counts.
> 5. `swift build`, `swift test`, screenshots: the locked sign-off + amber
>    `In review` chip, the earned `Connect to my agent` + green `Ready to
>    connect` chip, and the quiet coverage signal on the cell; confirm a
>    single passing demo never unlocks the sign-off.

### Refining loop
- If the coverage signal visually competes with the trust verdict on the
  cell, shrink it / move it to the metric slot rather than escalating it; the
  trust verdict wins the cell.
- If the sufficiency threshold is ambiguous, defer to the HTML/CP-F decision
  rather than inventing a rule; the sign-off must never be easier to earn
  than the design states.

### Human-in-the-loop (me)
- `[HOLD FOR ME]` CP-J: I confirm the sign-off threshold matches my CP-F
  decision — that `Connect to my agent` stays locked until real coverage
  (incl. an input I brought) and that a single passing demo never unlocks it.

### Acceptance
- A pure, tested coverage-state derivation gates the `Connect to my agent`
  sign-off + the breadcrumb chip and expresses quietly on the cell without
  breaking the one-trust-verdict rule; a single passing demo never unlocks
  the sign-off; agent-only runs never advance it; usage seam handled without
  fabrication; nothing reads as a tier ladder or "Proven". Build + tests
  green.

---

## T-10.12 — MCP run/test tool: the agent tests modules too (CP-K)

**Owner:** agent
**Checkpoint:** CP-K — **implementation landed, awaiting Mark's CP-K wiring.**

> **Status: built, pending CP-K.** The safety posture is recorded in
> [ADR-0017](../adr/0017-mcp-run-tool.md) (Proposed): **one sandbox, two
> callers** — the runner stays the app-side Swift `SmokeRunner` (ADR-0016, not
> forked/re-ported), and the MCP tool reaches it through a thin headless
> `gunk run` verb (`app/Sources/GunkApp/Run/SmokeRunCLI.swift`, wired into
> `GunkAppMain` like the icon export) that runs the same executor **buffered**
> and prints a JSON receipt. Consent posture: **the sandbox is the consent** —
> an agent run needs no prior human first-run consent but is *strictly more*
> constrained (always sandboxed; the reduced-isolation fallback is **never**
> available — it fails closed; pinned explicitly in `SmokeRunCLI` and
> re-checked at the TS boundary). Returns `{ passed, runnability, isolation,
> exitCode, durationMs, timedOut, command, stdout, stderr, output }` — buffered,
> **no live stream**; non-terminal classes return a typed "not runnable here",
> not a failure. **Return-only this phase** (no MCP store writes — the v6
> agent-receipt write is a documented seam). The tool lives in
> `mcp/src/tools/run_gunk.ts` (+ `mcp/src/lib/manifest.ts` for `gunk.yml`
> entrypoint/package reads), opens the store the existing way
> (`getGunk`, explicit columns), and resolves the binary via `GUNK_RUN_BIN`.
> Tested in `mcp/test/tools/run_gunk.test.ts` + `mcp/test/lib/manifest.test.ts`
> (pass/fail/not-runnable/not-found/no-bundle/reduced-fallback-refused/request
> resolution; no real store, no real spawn) and
> `app/Tests/GunkAppTests/SmokeRunCLITests.swift` (decode → run → encode round
> trips; agent origin forced; timeout clamp). `bun test` (64) + `swift build` +
> `swift test` (239) green; typecheck/lint/format clean. End-to-end verified:
> `echo <req> | GunkApp run` on a live Python module returns a passing,
> `sandbox-exec`-isolated, agent-origin receipt. The **security-review subagent
> ran** and found **no medium+ issues**; its three optional hardenings (explicit
> agent posture, TS-side reduced-fallback refusal, output cap) are applied.
> Still needs Mark to wire `GUNK_RUN_BIN` into his real Cursor and confirm CP-K.

### Goal
The user's explicit ask: **the AI system tests modules as well.** Add the
first MCP **execute** tool so an agent can run a module's entrypoint in the
same T-10.2 sandbox and get the receipt back — verifying a module *works*
before it uses it, and (optionally) writing the receipt to the same store
the developer's runs use, so human and agent evidence accumulate together.

### Why an ADR
This is the largest change to the MCP contract since Phase 2 (the first
non-read tool). ADR-0001 frames MCP as the user-visible contract; an
execute tool needs an ADR (or an ADR-0001 amendment) covering the safety
posture (consent model for agent-initiated execution, sandbox reuse, what
the tool returns).

### Files
- `docs/adr/00NN-mcp-run-tool.md` (new — next free ADR number)
- `mcp/src/tools/run_gunk.ts` (new — `RUN_GUNK_TOOL` + handler, following
  the `get_gunk.ts` pattern)
- `mcp/src/server/registerTools.ts` (register the new tool)
- The runner: if T-10.2 chose **app-side Swift**, the MCP tool needs a
  callable path to it — decide and document (shell out to a `gunk-engine
  run` verb, or move the sandbox core into the engine so both the app and
  MCP call it). **State the chosen architecture in the ADR.**
- `mcp/test/run_gunk.test.ts` (new)

### Task execution (agent prompt)

> 1. **Write the ADR first** and stop for me. Resolve where the runner
>    lives so both the app (T-10.2) and MCP can call it without duplicating
>    the sandbox — recommend a single engine-level `run` core both invoke,
>    even if T-10.2 wrapped it app-side first (reconcile, do not fork the
>    sandbox). Cover: agent-execution consent posture (does the agent's run
>    require the human's prior first-run consent for that module?), what the
>    tool returns (pass/fail + captured output + duration, **not** a live
>    stream), and timeouts.
> 2. Define `run_gunk` (name per ADR): input `{ gunkId, input? }`, output a
>    structured receipt `{ passed, exitCode, durationMs, output, command }`.
>    It opens the store the existing way (`openDefaultStore()`, explicit
>    column lists — Hard data fact 8), resolves the bundle + entrypoint, and
>    invokes the shared sandbox runner in **buffered** mode (T-10.2).
> 3. Respect the sandbox contract exactly (no network, scoped fs, timeout).
>    Honor the consent decision from the ADR — an agent must not be a way to
>    bypass the human first-run consent if the ADR says consent is required.
> 4. Optionally persist the receipt to the v6 `smoke_runs` table (tagged as
>    agent-initiated) so human + agent evidence share the coverage readout —
>    only if the ADR approves MCP writes; otherwise return-only this phase.
> 5. Tests against fixtures: a passing module returns a passing receipt; a
>    failing one returns a failing receipt; an un-runnable one returns the
>    typed "cannot determine" result; the sandbox boundary holds; the store
>    read uses explicit columns. No test touches the real store.
> 6. `bun test` (mcp). **Run the security-review subagent** on the diff
>    (agent-initiated code execution is the highest-risk surface in the
>    phase) and address findings.

### Refining loop
- If reconciling the runner home (app vs engine) is large, prefer moving
  the sandbox core into the engine in this task and having the app's
  `SmokeRunner` (T-10.2) call it too — one sandbox, two callers — over
  shipping two sandboxes.

### Human-in-the-loop (me)
- `[HOLD FOR ME]` CP-K: I wire the tool into my real Cursor and confirm an
  agent can call `run_gunk`, gets an honest pass/fail receipt, and **cannot**
  exceed the sandbox or skip required consent.

### Acceptance
- A tested MCP `run_gunk` tool executes a module in the shared sandbox and
  returns an honest receipt; the safety posture is captured in an accepted
  ADR; one sandbox serves both app and MCP; security review is clean.
  `bun test` green.

---

## T-10.13 — UI-module runner: detect UI modules, launch the browser

**Owner:** agent
**Checkpoint:** none
**Status: DEFERRED (mid-phase revision 2026-06-15).** The in-browser
*launch* moves to a later phase. This phase ships **terminal-only**
execution; a UI module is **detected and labeled** as a `ui-module`
not-runnable-here class (T-10.2 step 3b) and the page shows it as a clearly
*future* affordance — **not** a working run button. Only step 1 (detection)
and the page's deferred-state label are in scope now; steps 2–3 (actually
serving + `NSWorkspace.open`) are out until the follow-up phase. Keep the
goal below as the eventual target.

### Goal (eventual — not this phase)
If a module's output *is* UI, running it **launches the user's external
browser** at the module's served surface. In-app preview is explicitly out.

### Files
- `app/Sources/GunkApp/Views/ModulePageView.swift` (the UI-module run
  affordance + the "launching browser" state from CP-F)
- `app/Sources/GunkApp/Run/SmokeRunner.swift` (a served-surface run mode, or
  detection + `NSWorkspace.open(url)` after the server is up)
- `app/Sources/GunkApp/Models/BrowseModel.swift` (UI-module detection flag)

### Task execution (agent prompt)

> 1. Detect UI modules from existing signals (language/framework/entrypoint
>    heuristics — report what you key on; do not invent store state beyond a
>    derived flag, or persist a `isUIModule` flag via T-10.3 if a derived
>    flag is unreliable).
> 2. For a UI module, the run affordance starts the served surface in the
>    sandbox (respecting the T-10.2 contract — a UI server needs a port;
>    state how the sandbox handles local-port-but-no-external-network) and,
>    when it is up, opens the user's default browser at the URL
>    (`NSWorkspace.shared.open`). Show the "launching browser" state from
>    CP-F; do not embed a web view.
> 3. The receipt for a UI run records that it launched (and the URL),
>    distinct from a pass/fail data run.
> 4. `swift build`, `swift test`, screenshot the UI-module affordance + the
>    launching state.

### Refining loop
- If detection is noisy, prefer a quiet "Open in browser" action on
  plausible UI modules over a wrong automatic classification; never
  auto-launch without the consent gate.

### Human-in-the-loop (me)
- I run a real UI module and confirm it opens in my browser, not in-app.

### Acceptance
- UI modules are detected and run by launching the external browser at the
  served surface (no in-app preview); the launch state and receipt are
  honest; consent respected. Build + tests green.

---

## T-10.14 — "How this works" on-demand analysis

**Owner:** agent
**Checkpoint:** none

### Goal
A quiet, single disclosure on the module page that opens an AI-written
analysis of the module's design (data flow in → transform → out, key
functions, what it touches, its limits). Rule: **"if they want to see it" —
never in their face**; generated once at extraction and cached so opening
feels instant.

### Files
- `app/Sources/GunkApp/Views/ModulePageView.swift` (the disclosure, closed
  + open)
- `engine/src/analyze/*` + persistence (generate + cache the analysis at
  extraction) **or** app-side cached generation — decide and report
- `app/Sources/GunkApp/Store/...` (cache the analysis text — reuse T-10.3 if
  a column/table fits, additive)

### Task execution (agent prompt)

> 1. Generate the analysis text once (engine at extraction is the faithful
>    place — it already has LLM access and the bundle; persist + cache it).
>    The input signature (T-10.8) is the short form; this disclosure is the
>    long form.
> 2. Render it behind **one** quiet affordance ("How this works"), opening
>    inside the page (not a modal, not a chatbot). Mono only for the code
>    references inside it.
> 3. Opening must be instant (read the cache; never block on a live model
>    call at view time).
> 4. `swift build`, `swift test` (+ `bun test` if engine touched),
>    screenshots: closed (one affordance) and open (analysis layout).

### Refining loop
- If the cached analysis is missing on older modules, show a quiet "not
  analyzed yet" with a way to generate on demand — do not auto-summon a
  model on every page open.

### Human-in-the-loop (me)
- I open "How this works" on a real module and confirm it is instant,
  accurate-enough, and stays out of the way until asked.

### Acceptance
- A single quiet disclosure opens a cached AI analysis inside the page,
  instant on open, generated once at extraction; never in the user's face.
  Build + tests green.

---

## T-10.15 — Cleanup, regression pass, retro

**Owner:** agent
**Checkpoint:** phase exit

### Task execution (agent prompt)

> 1. Delete dead code this phase orphaned (the inline `ModuleDetailView`
>    pane path if T-10.4 fully replaced it, any superseded scaffolding).
>    `rg` for references first.
> 2. Full pass at 960×600 and default window size: the module page and every
>    run state (consent, streaming, passed, failed, resting receipt, intent
>    toolbar + typed inputs, in-console diff receipt per artifact kind,
>    coverage ledger + known limits, passing-checks list, sign-off locked +
>    `Ready to connect`, UI-module not-runnable label, "How this works"),
>    plus back-navigation grid state — no layout shifts, no clipped controls.
> 3. Confirm the toolbox-v2 constraints still hold (graphite surfaces, mono
>    only for paths/code/terminal, accent green only on earned meaning,
>    glass on the controls layer only) and the two-surfaces rule (smoke run
>    ≠ extraction inspector) is intact.
> 4. Confirm the ADRs (sandbox, MCP run tool) are Accepted and linked from
>    the roadmap; confirm `mcp/` still ignores the v6 store cleanly.
> 5. Check off completed Phase 10 items in `docs/roadmap.md`.
> 6. Write `docs/retros/phase-10.md`: what shipped, what slipped, what we
>    learned, what we're cutting.

### Acceptance
- No dead code, ADRs accepted + linked, roadmap current, retro written,
  build + all package tests green.

---

## Task order and dependencies

```mermaid
flowchart LR
    t1[T-10.1 design gate CP-F]
    t2[T-10.2 sandbox runner CP-G]
    t3[T-10.3 store v6 CP-H]
    t4[T-10.4 module page]
    t5[T-10.5 call-it snippet]
    t6[T-10.6 requirements readout]
    t7[T-10.7 smoke run core CP-I]
    t8[T-10.8 typed inputs]
    t9[T-10.9 coverage ledger]
    t10[T-10.10 saved examples]
    t11[T-10.11 coverage sign-off CP-J]
    t12[T-10.12 MCP run tool CP-K]
    t13[T-10.13 UI-module launch]
    t14[T-10.14 how this works]
    t15[T-10.15 cleanup + retro]

    t1 --> t4
    t2 --> t7
    t3 --> t7
    t4 --> t5
    t4 --> t6
    t4 --> t7
    t7 --> t8
    t7 --> t9
    t9 --> t10
    t3 --> t9
    t9 --> t11
    t10 --> t11
    t2 --> t12
    t3 --> t12
    t2 --> t13
    t4 --> t13
    t4 --> t14
    t5 --> t15
    t6 --> t15
    t8 --> t15
    t11 --> t15
    t12 --> t15
    t13 --> t15
    t14 --> t15
```

**T-10.2 (sandbox) and T-10.3 (store) are foundation and start
immediately** — before CP-F clears (they have no visual surface). They are
also the riskiest pieces (code execution + a schema change), so front-load
them like the engine work was front-loaded in Phases 3–5. **CP-F gates all
page/visual work (T-10.4+).** T-10.5 and T-10.6 are small and independent
once the page (T-10.4) exists. The proof loop is a chain:
T-10.7 → T-10.8/T-10.9 → T-10.10 → T-10.11. **T-10.12 (the agent's door)**
needs only the sandbox + store and can run in parallel with the developer-
facing chain. T-10.13 and T-10.14 are independent page features. T-10.15
closes the phase.

Two ADRs are produced in-phase: the **sandbox/execution model** (T-10.2,
CP-G) and the **MCP run tool** (T-10.12, CP-K). Both are security-sensitive
and ship behind the security-review subagent.
