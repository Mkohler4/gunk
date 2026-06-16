# Module run exploration v2 — the run console + coverage ledger (CP-F)

Date: 2026-06-15 · Designed in Claude Design · Status: **CP-F approved by
Mark — the HTML export landed, so v2 is the source of truth.** Supersedes
[module-run-v1.md](module-run-v1.md) wherever they differ (same rule as
toolbox-v2: when the HTML lands, the HTML wins).

> **Source of truth.** The reference artifact is the Claude Design HTML
> export in this folder:
> [`module-run-v2.html`](module-run-v2.html) (the full page, every run
> state, interactive). The resting "adversarial / in review" state is
> captured in [`module-run-v2-coverage.png`](module-run-v2-coverage.png).
> The driving brief was
> [`module-run-v2-instruction.md`](module-run-v2-instruction.md). When the
> HTML and this prose disagree, **the HTML wins.**
>
> Lineage: stage 1 = [`smoke-run-prompt.md`](../feature-report/smoke-run-prompt.md)
> ("Try it" + receipts). Stage 2 =
> [`module-io-prompt.md`](../feature-report/module-io-prompt.md)
> (receipt-first, developer verdict, typed inputs). Stage 3 v1 grew the
> surface to a full page and pinned "Proven by you." **v2 kills "Proven by
> you"** and replaces the single resting badge with an honest, un-gamified
> **coverage ledger**.

![Run console — adversarial / in-review state](module-run-v2-coverage.png)

## Verdict in one line

Clicking a module navigates to a **full module page** whose hero is a real,
sandbox-bounded **run console** (left) paired with a **coverage ledger**
(right) that states — plainly, never as a score — **which classes of input
have actually been proven**. Trust is not a badge you earn in one click; it
is coverage across *happy path · your own inputs · edge cases ·
adversarial*, and an agent connection is offered only when that coverage is
honestly sufficient.

## The page at a glance (what the HTML shows, top → bottom)

1. **Breadcrumb bar** (glass, floating controls layer) — `‹ Library` back
   button, crumb `Immersive-Audiobook-Local-MVP › Audiobook Content
   Parsing`, and a trailing **bar-state chip** that reflects the honest
   verdict (`In review`, amber, when coverage is incomplete; green
   `Ready to connect` only when it is sufficient). No layout shift as it
   changes.
2. **Slim title row** — module name, one-line purpose, a quiet
   `Python capability` language badge. Deliberately understated so it does
   not compete with the console.
3. **The run console** (`.console`, the hero — its own near-black world,
   `--con #0c0c0e`, deeper than the page):
   - **Console bar:** `>_ run console`, the resolved entrypoint
     (`parser.py:parse_epub`, mono), and a status chip that cycles
     `idle → running (spinner) → pass (green) / fail (red)`.
   - **Intent toolbar** — verb tabs that *compose the command* and map
     1:1 to the coverage classes: **Shipped example**, **My own input**,
     **Try to break it** (adversarial). A `swap input` affordance sits on
     the right. The active verb tints the console (green for a normal run,
     amber for "break it").
   - **Console body** (mono): the composed command line
     (`$ gunk run parser.py:parse_epub --in corrupt.epub`), streamed
     stdout/stderr, a one-line hint, and — after a passing run — the
     **diff receipt** rendered as terminal *text* (before / after columns),
     not as boxes.
   - **Console footer** — the single action zone. It cycles **Run** →
     **verdict**. The run button is green (amber for "break it");
     after a run the footer hosts the verdict (`That's right` /
     `That's wrong`). First-run consent is shown here (command + working
     directory + the sandbox promise) before the first execution.
   - **Inline correction** (the "that's wrong" doorway) opens *inside* the
     console body, terminal-styled: a textarea to pin the **expected
     output**, a one-line *what's wrong* note, and **Pin failing case**.
4. **The coverage ledger** (right rail — airy, de-boxed: a spine,
   hairlines, lists; explicitly *not* cards and *not* a progress meter):
   - Header **Coverage** + the thesis line: *"Trust isn't one run — it's
     knowing each class of input behaves."*
   - **Class spine** — one node per **input class**, each a plain fact
     with a count, never a level to climb:
     - **Happy path** — the shipped/synthesized demo (e.g. `1`).
     - **Your own inputs** — distinct inputs the developer *brought* and
       judged (e.g. `2 checks · 2 of your books checked`). The `yours`
       provenance is tracked.
     - **Edge cases** — gap state (dashed ring) until covered
       (`Footnote-heavy EPUBs untested`).
     - **Adversarial** — gap/amber until exercised
       (`Try to break it with bad input`).
   - **Passing checks** — the named-case list (each: a dot, the case name,
     a `yours` violet badge for developer-brought inputs, a relative time,
     hover **re-run**). A **failing/flagged** case reads red with a **fix**
     action.
   - **Known limits** — recorded boundaries from "Try to break it"
     (`known not to handle: empty file`), with a count and an empty state.
     **Never red** — a known limit is an honest record, not a failure.
   - **Sign-off** — a statement, not a card: **Not ready to connect**
     (locked, greyed `Connect to my agent`, with *"Cover happy path and your
     own inputs to reach a confident sign-off"*) → flips to the ready
     state (green `Connect to my agent`) only when coverage is sufficient.
5. **Advanced footer** (`<details>`, fully demoted) — the module's
   provenance, the requirements readout ("to run this elsewhere"), the
   file list with the mono bundle path, and the `view run →` extraction-run
   inspector entry. This is where the v1 trust-readout / requirements /
   call-it content now lives, quiet by default.

## What changed from v1 (record these — decisions are Mark's)

### 1. "Proven by you" is dead → coverage by input class
v1's resting state showed one synthesized run wearing `✓ Proven by you`.
v2 deletes that badge entirely. The page now states evidence as **coverage
across classes of input** (happy path / your own / edge / adversarial),
each a plain count. There is **no tier ladder, no level, no progress bar,
no "1 more to unlock," no celebration.** One AI-staged pass registers as a
single check under *Happy path* — the lowest honest fact — and explicitly
**not** as "proven."

### 2. The hero is the run console, not the proof card
v1 led with a before/after proof card and demoted the terminal. v2 makes
the **run console the hero** (the locus of everything) and renders the
before/after **diff receipt inside it** as terminal text. The verbs that
compose the command (shipped example / my own input / try to break it) are
the same axes the coverage ledger scores — input and evidence are one
surface, not two.

### 3. "That's wrong" is a doorway, captured-and-queued
A wrong verdict opens an inline correction (expected output + note) that
**pins a failing case** with a target. This phase **captures and queues**
the correction (stores the failing case + expected output + note, surfaces
it as a flagged check); the guided **re-extraction trigger is a designed
but deferred seam** (the "fixing…" state exists in the HTML; wiring it to a
real re-extraction is a follow-up). See open question #10.

### 4. Terminal-only scope → honest "runnable here: not yet"
The console only executes **terminal/CLI/library one-shot** modules.
Everything else (needs network / needs secrets / interactive stdin /
long-running / UI / cannot-determine) gets a **neutral** "runnable here:
not yet" treatment with the reason and the call-it snippet — **never red**
(red is reserved for a real failed run).

### 5. The agent connection is the honest verdict
There is no abstract "Proven" word anywhere. The one consequential claim
the page makes is the **sign-off**: whether the module is *ready to connect
to your agent*. That is gated on real coverage, so the verdict is earned by
evidence, not declared by a click.

## What v1 confirmed and v2 keeps (no change)

- **Full page, not a glass sheet.** Clicking a module navigates (breadcrumb
  back), it does not open a sheet. Nothing pre-builds the sheet container.
- **Two surfaces, never merged.** `view run →` (extraction receipt) lives in
  the demoted advanced footer; the console answers "what does the module
  do." They link, never share a screen.
- **The developer is the judge.** A run gets a `That's right` / `That's
  wrong` verdict; "right" pins a golden/example, future runs diff against it.
- **Visual law (toolbox-v2, locked).** Graphite content surfaces; glass only
  on the floating controls layer (breadcrumb bar, toasts, overlays); accent
  green `#5fe08c` only on genuinely earned confidence (a passed run, real
  coverage, a warranted agent connection) — never on a single AI-staged
  pass; amber = needs the human / an open correction; red = a failed run
  **only**; mono only for paths/code/terminal. Zero layout shift; fits the
  960pt minimum window.

## Open questions — resolved (CP-F decisions)

The seven from [module-run-v1.md §"Open questions"](module-run-v1.md) plus
the three new ones from the mid-phase revision, settled against the v2
design. These are the recorded answers; T-10.4+ builds against them.

1. **Leveling rule (#1).** **There is no leveling rule — there is a coverage
   readout.** Evidence is stated as coverage across four input classes
   (happy path · your own inputs · edge cases · adversarial), each a plain
   count. The lowest honest label for "one synthesized example passed" is a
   single check under **Happy path** — never "Proven." Confident green / the
   *ready to connect* sign-off is warranted only when **Happy path is covered
   and at least one of Your own inputs is checked** (the locked copy: "Cover
   happy path and your own inputs to reach a confident sign-off"). Edge cases
   and adversarial deepen coverage but are **not** required to unlock the
   sign-off. The readout **describes**; it never ranks, rewards, or nudges.
2. **Sandbox promise (#2).** Scope is **terminal/CLI/library one-shot
   entrypoints only**. The sandbox runs against a **throwaway copy** of the
   bundle (never the user's source), with **network off**, a **hard
   timeout**, writes confined to the **run directory**, and env passed
   explicitly (secrets never echoed). The promise is stated at first-run
   consent in the console footer (command + working directory + the three
   guarantees) and the concrete model is pinned in **ADR-0016** (T-10.2).
3. **Terminal vs typed inputs (#3).** **One composition, not two tabs.** The
   run console *is* the surface; the intent toolbar's verbs (shipped example
   / my own input / try to break it) compose the command, and "my own input"
   surfaces the typed/file-drop input inline. The terminal pre-fills the
   resolved **call-it invocation** for the active verb; the developer edits
   the args in place.
4. **Golden-diff semantics + non-determinism (#4, #5/edge).** The diff
   receipt is **per artifact type**: text → textual diff; structural JSON →
   structural (key/value) diff; audio/binary → metadata/duration compare,
   not byte compare. A module the developer marks **non-deterministic** is
   diffed **semantically/loosely** (or the diff is informational only), so
   "differs from golden" never reads as a regression when difference is
   expected. Verdict stays **binary** (right/wrong); the *note* carries
   nuance — no partial state.
5. **Re-extraction breaks golden (#5).** Folded into the wrong→fix loop and a
   **batch corpus reconciliation**: when the source re-extracts, every saved
   check re-runs and the page reports the batch ("4 pass · 1 broke"). A
   broken check surfaces as a **flagged/failing** row in the coverage ledger
   with a **fix** action — the developer sees and resolves it on this page,
   not the Library cell.
6. **Breadcrumb navigation mechanics (#6).** Back returns to the Library and
   **preserves grid scroll + selection**. A sidebar-badge deep-link opens a
   **scoped grid** → module page → back returns to that scoped grid. (Locked
   as intent; exact state-restoration is a T-10.4 implementation detail.)
7. **Where "How this works" lives (#7).** In the **demoted advanced footer**
   (`<details>`), closed by default — one quiet affordance that expands the
   analysis inside the page. It does not compete with the console.
8. **Agent vs human evidence (#8).** Agent-initiated runs (the MCP `run_gunk`
   tool, T-10.12) share the evidence pile but are stated **separately and
   factually** ("N agent runs · M you checked"). **Agent runs alone never
   count as human-checked coverage** and never advance the sign-off on their
   own. Until that telemetry is real, the counts are not fabricated.
9. **Runnability classification (#9).** gunk classifies **terminal-runnable**
   only when all hold: (a) a supported language with a known one-shot
   interpreter (**Python / Node first** this phase); (b) a confidently
   resolvable entrypoint (path, optionally a symbol); (c) **no** dependency-
   manifest or framework signal of network / secrets / interactive stdin /
   long-running server / UI. When any signal says otherwise it returns the
   matching **not-runnable-here** reason; when it cannot tell, it returns
   **cannot-determine** and the page shows the call-it snippet with **no run
   button** rather than guessing. The classifier and its signal set are
   specified in ADR-0016 and built in T-10.2.
10. **Improve-loop depth (#10).** **Capture-and-queue this phase.** A
    developer correction pins a failing case (expected output + note + the
    input that broke it) via the store (T-10.3) and surfaces it as a flagged
    check. The **guided re-extraction trigger is deferred** — the HTML
    designs the "fixing…" state as a forward seam, but this phase does not
    wire a real re-extraction. This keeps the phase shippable.

## Store / state implications (carried forward to T-10.3, v6 schema)

Per-entrypoint input signatures · synthesized demo fixtures · run receipts
(input ref, output artifact, duration, exit, verdict, **runnability class**,
**run origin: human | agent**) · saved/golden examples tagged by **input
class** (happy / yours / edge / adversarial) · pinned **failing cases**
(expected output + note + breaking input) · **known limits** records ·
cached "how this works" analysis · the non-determinism flag. The evidence
state must stay reachable by MCP eventually (`get_gunk`) — see the Phase 10
"verified state must be machine-readable" seam.

## Hand-off

- **CP-F:** cleared by this doc + the landed HTML export.
- Build order resumes at **T-10.2** (sandbox runner + ADR-0016), then the
  store (T-10.3 / CP-H), then the page itself (T-10.4+).
- Cross-linked from [docs/roadmap.md → Phase 10](../../roadmap.md) and
  [phase-10-run-and-test-modules.md](../../tasks/phase-10-run-and-test-modules.md)
  T-10.1.
