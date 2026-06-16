# Module run exploration v1 — the module page, the proof loop, the terminal

Date: 2026-06-12 · Designed in Claude Design · Status: **SUPERSEDED by
[module-run-v2.md](module-run-v2.md) (CP-F, 2026-06-15).** The v2 HTML
export landed and won: "Proven by you" is dead, the run console is the hero,
and the resting badge is replaced by the honest **coverage ledger**. v1 is
retained for lineage — read v2 for the locked design and the resolved open
questions.

> **Source of truth.** The reference screens are in this folder:
> [`module-run-v1-page.png`](module-run-v1-page.png) (top of the page) and
> [`module-run-v1-proof.png`](module-run-v1-proof.png) (proof card, call-it,
> footer). Mark will add the Claude Design HTML export alongside
> (`module-run-v1*.html`); **when the HTML lands, it wins** over both the
> PNGs and this prose — same rule as toolbox-v2.
>
> Lineage: this is stage 3 of the developer trust loop. Stage 1 =
> [`smoke-run-prompt.md`](../feature-report/smoke-run-prompt.md) ("Try it"
> + receipts). Stage 2 = [`module-io-prompt.md`](../feature-report/
> module-io-prompt.md) (receipt-first evidence, developer verdict, typed
> inputs, on-demand analysis). Stage 3 grows the surface to a full page
> and **corrects two stage-2 calls** — see "What changed" below.

![Module page — top](module-run-v1-page.png)
![Module page — proof card and call-it](module-run-v1-proof.png)

## Verdict in one line

Clicking a module no longer opens a pane or a sheet — it navigates to a
**full module page** (breadcrumb `‹ Library › <source> › <module>`) whose
spine is *proof*: trust readout, a Proof card with a synthesized
before/after example, a real terminal for developer-driven runs, and a
testing metric that accumulates — which is **a phase of work, not a task**.

## The page at a glance (what the screens show, top → bottom)

1. **Breadcrumb bar** — `‹ Library` back button, then
   `Immersive-Audiobook-Local-MVP › Audiobook Content Parsing`. The
   Library remains the only top-level room; the module page is *inside*
   it. When scrolled, the bar gains a compact trailing state chip
   (`Proven`, second screen).
2. **State line** — `Proven` (green) `· ★ Golden` over the module title
   and purpose. (Vocabulary under revision — see "Proven is earned, not
   declared" below.)
3. **Provenance line** — `From <source> · Python ·` coral provider badge
   `Extracted with Claude Sonnet 4 · Anthropic · view run →`. The
   `view run →` affordance **is the T-8.6 extraction-run inspector entry
   point** — the two-surfaces rule (extraction runs ≠ module runs) holds.
4. **Trust readout, 3-up** — Confidence 95% / Self-contained Passed /
   Build Skipped, exactly the toolbox-v2 detail-sheet spec, now resident
   on the page.
5. **"Proven by you" banner** — green tinted: "A golden example is pinned
   — re-extractions are diffed against it. Connect MCP in Settings to
   make it callable." (Copy under the same vocabulary revision.)
6. **Proof card** (the heart of the page):
   - Header: `Proof` + `✓ Proven by you` chip, `Demo staged by gunk ·
     synthesized a 1-chapter EPUB`, **Edit input** button.
   - Body: side-by-side **Synthesized input → Output**, rendered as the
     thing (text/markdown here), not as a log.
   - Footer: `★ Golden example pinned — every re-run is diffed against
     this. Proven by you · just now` + **Re-run**.
   - Demoted disclosure: `>_ Command & raw log` — the terminal-ish
     evidence exists but is not in your face.
7. **Right rail** — "To run this elsewhere, you need" (runtime ≥ 3.11,
   packages, env vars) and "4 files in this capability" with the
   mono bundle path.
8. **Call it** — the copyable invocation snippet, mono, with comment.
9. **Footer actions** — Open in Finder / Re-run source / Delete
   (destructive, right-aligned).

## What changed from the pinned plans (record these; decisions are Mark's)

### 1. Full page, not a glass sheet

toolbox-v2 pinned module detail as a centered glass sheet
(`.overlay`/`.sheet`, radius 22, blur 50), and T-8.4 shipped its inline
pane as "interim until T-8.6's glass sheet." This exploration replaces
the sheet with **in-place navigation to a full page** — breadcrumb back,
not dismiss. `[HOLD FOR ME]` this is a direct revision of toolbox-v2's
"Beyond the Library" section; nothing should pre-build the sheet
container while this is open. (T-8.6 itself — the *extraction-run*
inspector — is unaffected in substance; its module-detail entry point
becomes the `view run →` line shown here.)

### 2. "Proven is earned, not declared" — the testing metric

Mark's correction of stage 2, verbatim intent: *one passing example with
a "Proven by you" badge is not how software works.* One pinned golden
example must **not** read as "Proven."

- The vocabulary must scale with evidence: a module carries **a count of
  examples and their pass state** (e.g. "3 examples · 3 passing"), not a
  binary blessed state.
- The roadmap's Phase 10 "Tested badge **leveling rule** (badge tier
  scales with how much the module was tested)" is the already-pinned home
  for this — the proof loop feeds it. What earns each tier (number of
  examples? distinct inputs? developer-supplied vs synthesized? recency
  across re-extractions?) is an open product decision, `[HOLD FOR ME]`.
- Golden examples remain the mechanism (verdicts pin ground truth;
  re-runs diff against it). What changes is the *claim* the UI makes on
  top of them.

### 3. A real terminal, with developer inputs

Stage 2 said "no REPL or arbitrary terminal — the developer supplies data
and judgment, never shell." **Reversed.** The module page gets a **fully
functioning terminal**: the developer can throw their own inputs at the
module, and **example inputs** are staged for one-click use. The typed
input surface (stage 2) and the terminal coexist — the input form is the
guided path, the terminal is the expert path. Boundary moves from "no
shell" to **sandbox guarantees** (what the sandbox promises — fs scope,
network, timeouts — is an open question the design must state, not wave
at). First-run consent from stage 1 still applies.

### 4. UI modules launch a browser

If a module's output *is* UI, it does not render in-app for now — running
it **launches the user's browser** at the module's served surface. This
revises the Phase 10 roadmap item "UI-module runner: detect UI modules
and launch/preview them from the app" → detect and **launch externally**;
in-app preview is explicitly out for now.

### 5. Scope: this is a phase, not a task

T-8.6 as written (RunsView → extraction-run inspector) stays a small
task. Everything else on this page is **Phase 10 grown into a real
phase**: full-page module detail (a navigation-model change to the
Library), the proof card + golden diffing, the synthesized-demo pipeline,
the typed input surface, the terminal + sandbox, example-input staging,
the testing metric/leveling rule, the browser launch for UI modules, and
the store state for all of it. Phase 10 needs its own task-list doc
(like `phase-8-shell-and-ia-restructure.md`) once the HTML lands and the
open questions below are decided.

## What the screens *confirm* (no change)

- **Two surfaces, never merged**: `view run →` (extraction receipt) vs
  the Proof card (module behavior).
- **Trust readout** content (confidence / self-containment / build) and
  the **requirements readout** and **call-it snippet** from stage 1.
- **Receipts, not dashboards** — no charts, no history graphs anywhere.
- Visual law: graphite surfaces, green only on earned meaning, mono only
  for paths/code/terminal, generous radii. The breadcrumb bar reads as
  the floating controls layer (glass) over solid content.

## Store/state implications (new, none exist today)

Input signatures per entrypoint · synthesized demo fixtures · run
receipts (input ref, output artifact, duration, verdict) · golden/saved
examples · per-module test counts for the leveling rule · cached
"how this works" analysis text · UI-module detection flag.

## Open questions (for the next design/product pass)

1. Leveling rule: what evidence earns each tier, and what is the lowest
   honest label for "one synthesized example passed"?
2. Sandbox promise: exactly what the terminal may and may not touch, and
   how the UI states it (consent copy, badge on the terminal block).
3. Terminal vs typed inputs: one composition or two tabs? What does the
   terminal pre-fill (the call-it snippet? the staged example command?)?
4. Golden diffing semantics per artifact type (text diff vs structural
   JSON diff vs audio — byte-compare? duration tolerance?).
5. Re-extraction flow: when a re-run breaks the golden diff, where does
   the developer see and resolve it (this page? the Library cell? the
   review/needs-you state)?
6. Breadcrumb navigation mechanics at the Library level: does the grid
   keep scroll/selection state on back? Deep-link from sidebar badge →
   scoped grid → page → back?
7. Where the on-demand "How this works" analysis lives on this page (it
   is absent from these two screens — still required, still hidden by
   default).
