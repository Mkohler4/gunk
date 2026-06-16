# Revision instruction — module page v2: the proof you *build* (CP-F input)

Date: 2026-06-15 · Status: **DRAFT — pending Mark's approval before it goes
to Claude Design.** This is the T-10.1 deliverable (step 1): the literal
instruction to feed Claude Design. It revises
[module-run-v1.md](module-run-v1.md) (the two resting "Proven by you"
screens) and is the input to checkpoint **CP-F**.

> **Why a v2 instruction.** The v1 screens show one resting state and call
> it **"Proven by you."** That is the exact thing
> [module-run-v1.md §"Proven is earned, not declared"](module-run-v1.md)
> says is wrong: *nobody tests a module once.* "Proven by you" after a
> single AI-staged run reads as a sticker, not real evidence — and it makes
> the developer's click ceremony, the same flaw stage 2 already caught.
> This iteration replaces the sticker with the plain truth about what
> testing has actually happened, and gives the developer real tools to
> interrogate and correct the module — without editing code in-app (still
> out).
>
> **Not a game.** The metric is **not** gamified: no levels, ranks, XP,
> streaks, progress bars, "1 more to unlock," or celebratory moments. The
> developer tests because they need to trust the thing before they ship it,
> not to fill a meter. The readout *describes* the evidence honestly; it
> never rewards, ranks, or nudges.
>
> **Scope this round (locked, do not relitigate):** the page shell,
> breadcrumb, trust readout, requirements readout, call-it snippet, and the
> graphite/glass/mono/green visual law are all locked by
> [toolbox-v2](toolbox-v2.md) and [module-run-v1.md](module-run-v1.md).
> Design **three** new things on top of them: (1) the **honest evidence
> readout** that replaces "Proven by you," (2) the **"That's wrong" →
> correct → improve** loop, and (3) the **honest can't-prove-here states**
> for modules the sandbox can't fairly run. **Runtime scope for this phase
> is terminal/CLI/library modules only** — UI modules and network/secret/
> interactive modules get an honest "not runnable here yet" state, not a
> full run surface (see §3).

---

## The verbatim revision instruction (paste into Claude Design)

> You are iterating on the **gunk** macOS module page (dark, native-Tahoe).
> You already designed v1: a full module page with a breadcrumb, a trust
> readout, a Proof card showing a synthesized before/after, a real terminal,
> and a `Proven by you` resting state. The page shell, the breadcrumb, the
> trust readout, the "To run this elsewhere" requirements rail, the "Call
> it" snippet, and the visual law (graphite content surfaces; glass only on
> the floating controls layer; accent green `#5fe08c` **only** on earned
> meaning; amber = needs the human; red = failed; mono only for
> paths/code/terminal) are all **locked** — do not redraw or relitigate
> them. Design **three** new things on top of that page, and the states they
> need. The thesis of this whole iteration: **the page tells the plain
> truth about how much a module has actually been tested — no more, no
> less.** A module that ran once is not "proven"; a developer who clicked
> one AI-staged button has not verified anything. The developer's real job
> is to bring real inputs, judge real output, and correct real mistakes;
> the page states the resulting evidence honestly and never dresses it up as
> a score, a level, or an achievement.
>
> ### 1. Honest evidence, stated plainly (replaces "Proven by you")
> Kill the `Proven by you` sticker. Replace it with a **plain, factual
> readout of what testing has actually happened** — shown on the module page
> state line and (quietly) on the Library cell. This is a *description*, not
> a score: **no levels, ranks, points, streaks, progress bars, "1 more to
> reach X" nudges, or celebratory moments.** It simply tells the developer
> (and later the agent) exactly how much trust is warranted. Here is the
> shape to design against (these are honest descriptions of evidence, not
> ranks to climb — refine the copy):
> - **Untested** — never run, or run with no human judgment.
> - **Ran, not checked** — it executed (AI-staged demo) but no human has
>   judged the output. Neutral/quiet — **never green.**
> - **Checked once** — the developer judged one run *right* (one golden).
>   Stated as the modest fact it is: "you've seen it work on one input."
>   **This is exactly what the old screens wrongly called 'Proven.'** It
>   must read as a plain fact, not a verdict, and **must not** be dressed up
>   as a milestone.
> - **Checked · N inputs** — the developer has judged several **distinct**
>   inputs right, including at least one they **brought themselves** (not
>   just the staged demo). State the count plainly. Confident green is
>   warranted only here, where real human judgment across real inputs backs
>   it.
> - (Optional) note when the checked inputs **held through the last
>   re-extraction** — again as a stated fact, not a trophy.
>
> Design: the state line for each evidence state; the Library-cell
> expression **without breaking the one-trust-verdict-per-cell rule** (it is
> a quiet factual metric beside the trust verdict — like a count — never a
> second verdict and never a badge to collect). Do **not** design a
> progression affordance that nudges the developer to "earn" the next state;
> the run/save/input controls are simply available for a developer who
> genuinely wants more confidence. Also show how **agent-initiated runs**
> (the MCP `run_gunk` tool) appear in the same evidence pile, stated
> separately and factually — e.g. "12 agent runs · 3 you checked" — so
> agent volume can never read as human-checked evidence.
>
> ### 2. "That's wrong" is a doorway, not a dead end
> Today a wrong verdict just sets amber "Needs you." Make it the point where
> the developer can actually *fix the module* without editing code. When the
> developer hits **That's wrong**, open a small inline flow (inside the
> page, not a modal, not a chatbot):
> - **"What should it have done?"** — let the developer pin the **expected
>   output** (paste/edit the corrected artifact) and/or write a one-line
>   *what's wrong* note. This becomes a **failing example with a target** —
>   a regression case, not just a complaint.
> - **"Fix it"** — the developer's correction (expected output + note +
>   the input that broke it) becomes a **guided re-extraction hint**: gunk
>   re-runs extraction *steered by the developer's correction*. Design the
>   "re-extracting with your correction…" state and the resolution: the
>   failing case **resolves to passing when the new output matches the
>   target**. This is "fix the module yourself" — the developer steers the
>   AI by example + intent, never by writing code.
> - The failing case **stays pinned** as a known regression target until it
>   passes. Show the resting state of a module that has an open correction
>   ("1 case you flagged is still failing").
>
> Also design a quiet **"Try to break it"** path: a developer can feed a
> weird/adversarial input to find where the module breaks. A failing input
> here is **not a red error** — it records a **known limitation** as a plain
> note ("known not to handle: empty file") visible to the developer and the
> agent later. No reward, no score — just an honest record of the boundary.
>
> ### 3. Honest "can't prove this here" states (terminal-only scope)
> This phase runs **terminal/CLI/library modules only** — one-shot
> entrypoints the sandbox can fairly execute (network off, scoped fs,
> timeout). Many real modules don't fit that, and the page must say so
> **honestly and calmly**, never as a failure or a scary warning. Design a
> shared **"runnable here: not yet"** treatment (quiet, informational, with
> the reason and the call-it snippet so the developer can run it themselves)
> for each of:
> - **Needs the network / a live API** (sandbox is network-off) — "this
>   module's job is to call out; prove it where it has network."
> - **Needs secrets/credentials** not present in the sandbox.
> - **Wants interactive stdin** (a CLI that prompts) — the one-shot runner
>   can't answer prompts.
> - **Long-running / doesn't terminate** (a server, watcher, TUI) — the
>   timeout isn't a failure, it's a category.
> - **UI module** (output *is* a browser surface) — for now show a calm
>   "UI modules launch in your browser — coming next phase" placeholder, not
>   a run button (the in-app launch is **deferred**, design it as a clearly
>   future affordance, greyed/labeled).
> - **gunk genuinely can't determine how to run it** — honest "we can't
>   tell how to run this" resting state with the call-it snippet, not an
>   error.
> These must never use red (red = a real failed run). They are a distinct,
> neutral category: "the sandbox is the wrong room for this proof."
>
> ### 4. The states the v1 screens never showed (still required)
> In the same iteration, also deliver the run-loop states the original PNGs
> omitted, now consistent with the evidence readout above: never-tried;
> **first-run
> consent** (states command + working directory + the sandbox promise, calm
> not scary); running/streaming terminal; passed (earned green); failed
> (red, with stderr in the disclosure); resting receipt; the **typed input
> surface** (prefilled demo, developer-swapped, invalid input, missing
> requirement, file-drop well); the **effort spectrum in one composition**
> (Try it → swap input → save as example, no three competing CTAs); the
> **saved-examples** list (named cases, re-run, diff vs golden, and a
> **failing/flagged** case); and the **"How this works"** disclosure (closed
> = one quiet affordance, open = analysis inside the page).
>
> ### Visual constraints (all locked)
> Neutral graphite content surfaces; **glass only on the floating controls
> layer** (breadcrumb bar, overlays); accent green only on genuinely
> warranted confidence (output checked across real inputs, a passed run) —
> never on a single AI-staged pass; amber = needs the human (a wrong
> verdict, an open correction); red = a failed run **only** (never the
> can't-run states); mono only for paths/code/terminal; **zero layout
> shift** when run states appear/disappear; everything fits the **960pt**
> minimum window. No game treatments (no badges-to-collect, progress meters,
> or level-up animations). Mark anything not-yet-real (agent telemetry
> counts, UI launch) as explicitly future — never fabricate usage numbers.
>
> ### Deliver dark-mode screenshots of
> (a) the evidence readout at each state — Untested, Ran-not-checked,
> Checked-once, Checked·N-inputs — on the page state line and on the Library
> cell, plus how agent runs read separately from human-checked ones;
> (b) the "That's wrong" → correct → "fix it"/re-extract → resolved flow,
> including the resting state with an open failing case, and the "Try to
> break it" known-limitation note; (c) each "can't prove this here" state
> (network, secrets, interactive, long-running, UI-deferred,
> cannot-determine); (d) the omitted run-loop states from §4. Plus the HTML
> export.

---

## Edge cases this instruction must force the exploration to settle

Derived from the v1 screens, the locked decisions, and the codebase facts in
the Phase 10 brief — not invented. These are where "follow the exploration"
needs an actual answer before T-10.4+ build.

1. **"Proven by you" after one run is the headline bug.** The v1 resting
   state is exactly the "Checked once" fact (one golden) wearing the
   confident word. The exploration must show the *full range of honest
   evidence states* so a single AI-staged pass can never wear it again —
   without turning the range into a game. (module-run-v1 §"Proven is earned"
   + Phase 10 "Proven is earned, not declared".)
2. **The developer must really *do something* — not be nudged to.** Stage 2
   found that AI-writes / AI-runs / AI-judges makes the click ceremony. The
   answer is real agency (bring your own input, the wrong→fix loop), **not**
   a progress meter that pushes them to "earn" a higher state. The design
   makes the developer's contribution legible by stating it factually, never
   by gamifying it.
3. **"Wrong" needs a resolution flow, not just an amber dot.** Open
   question #5 (re-extraction breaks golden) and the new developer-initiated
   "this is wrong, improve it" flow are the same machinery: a correction →
   guided re-extraction → the case flips. The design must show where the
   developer sees and resolves it on the page.
4. **Right/wrong is too coarse.** Real testing has "close, but this one
   field is off." Decide whether there is a partial/flag state or whether
   "wrong + a note on what's off" covers it (prefer the latter — keep the
   verdict binary, let the note carry nuance).
5. **Non-deterministic modules break golden-diff.** Many modules (LLM-
   wrapped, time/random) won't reproduce byte-identical output. "Differs
   from golden" must not read as a regression when difference is expected.
   The design needs a per-module "this is non-deterministic" affordance, or
   a semantic/looser diff statement — settle which (ties to open question
   #4, golden-diff semantics per artifact type).
6. **Terminal-only scope = honest can't-run states, not failures.** Network/
   secrets/interactive/long-running/UI/cannot-determine are a **neutral
   category**, never red. The design must establish that category visually
   so a perfectly good API-client module doesn't look broken.
7. **UI modules are deferred this phase.** module-run-v1 §4 and roadmap say
   UI modules launch the browser; Mark's call is to ship terminal-only first
   and add the UI launch later. Design the UI-module state as a clearly
   *future* affordance, not a working button.
8. **Agent runs and human runs share one evidence pile (T-10.12).** The
   readout mixes MCP `run_gunk` receipts with human verdicts. Volume from an
   agent must not masquerade as human-verified quality — design the visual
   separation ("N agent runs · M you checked") and the rule that agent runs
   alone never count as human-checked evidence.
9. **Re-extraction reconciles a whole corpus, not one golden.** When the
   source re-extracts, *every* saved example re-runs. The page needs a batch
   reconciliation state ("4 pass · 1 broke after re-extraction"), not just a
   single golden break.
10. **Multi-entrypoint modules.** v1 assumes "the entrypoint." Decide how
    Try-it / saved examples behave when a module exposes several
    entrypoints/symbols (pick one with a quiet switch; examples scoped per
    entrypoint).

---

## Open questions mapping (the v1 seven, plus what v2 adds)

The seven from [module-run-v1.md §"Open questions"](module-run-v1.md) still
need answers at CP-F. v2 sharpens and adds to them:

- **#1 leveling rule** → answered by the **honest evidence readout** above:
  plain descriptors of what testing happened (lowest honest label for "one
  synthesized example passed" = **Checked once**, never "Proven"). Confirm
  the copy and what evidence each descriptor states. **It describes
  evidence; it does not rank, reward, or nudge — no gamification.**
- **#2 sandbox promise** → the **terminal-only scope** + the **can't-prove-
  here** category set its real boundary; confirm consent + terminal-badge
  copy.
- **#3 terminal vs typed inputs** → still to settle (one composition or two
  tabs; what the terminal pre-fills).
- **#4 golden-diff semantics** → now also must cover **non-determinism**
  (edge case #5).
- **#5 re-extraction breaks golden** → folded into the **wrong→fix loop** +
  the **batch corpus reconciliation** (edge case #9).
- **#6 breadcrumb navigation mechanics** → unchanged; still to settle.
- **#7 where "How this works" lives** → unchanged; still to settle.
- **NEW #8** — agent vs human evidence separation in the readout (edge case 8).
- **NEW #9** — the runnability classification: what gunk keys on to decide
  terminal-runnable vs can't-prove-here (language/entrypoint/manifest
  signals), and how confident it must be before it offers a run button.
- **NEW #10** — the "improve the module" loop's contract: does a developer
  correction trigger a real guided re-extraction this phase, or is it
  captured-and-queued (a flagged case) with re-extraction wired later? (This
  is the architecture question routed to the Phase 10 task doc.)

---

## After approval (to do once Mark clears CP-F)

- Save the HTML export + state screenshots into
  `docs/design/explorations/` (e.g. `module-run-v2-*.png`,
  `module-run-v2.html`).
- Fold the answers into [module-run-v1.md](module-run-v1.md) (or a v2 doc):
  verdict line, what's locked, what changed, the resolved open questions.
- Update [phase-10-run-and-test-modules.md](../../tasks/phase-10-run-and-test-modules.md)
  T-10.1 state list and the new open questions; cross-link from the roadmap
  Phase 10 item.
