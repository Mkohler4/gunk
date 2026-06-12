# Design prompt — module inputs, outputs & on-demand analysis (trust loop, stage 2)

> Product definition + paste-ready design prompt, the sequel to
> [`smoke-run-prompt.md`](smoke-run-prompt.md). Copy everything below the
> divider into the Claude design chat (it has the smoke-run context). This
> file is the repo's record of the 2026-06-12 follow-up ideation ("inputs
> into a module / outputs from a module / the developer is the judge") so
> the design chat, the roadmap, and the eventual task brief can't drift.
>
> **Stage 3 exists and corrects this prompt:**
> [`module-run-v1.md`](../explorations/module-run-v1.md) (same day, after
> the first designs came back). Two reversals to carry forward: (1) one
> pinned golden example must **not** read as "Proven" — the claim scales
> with an accumulating testing metric (the Phase 10 leveling rule), and
> (2) the "no REPL or arbitrary terminal" rule below is **rescinded** —
> the module page gets a real terminal with developer-supplied and
> example inputs, bounded by sandbox guarantees instead. Where the two
> disagree, stage 3 wins.

---

You designed the smoke run: one **Try it** button, a canned invocation,
streamed output, a pass/fail receipt. We pressure-tested it and found the
flaw: **the developer contributes nothing.** AI wrote the test, AI runs the
test, AI judges the result — the human's click is ceremony, and a green
"Passed" the developer didn't earn doesn't build trust. This prompt evolves
the feature in two moves. Design both; they're one surface.

## Move 1 — the receipt replaces the terminal (revision of what you drew)

The primary evidence of a run is a **before/after artifact**, not a log:

- The receipt shows **the input and what the module made of it**, rendered
  *as the thing*: markdown rendered (not source), JSON pretty-printed,
  audio as a playable clip, an image as an image. For TTS Audio Stitcher
  the receipt is a **play button** — you hear the module work.
- Under the receipt, the developer's verdict: **"That's right" / "That's
  wrong."** A "right" verdict **pins the run as the module's golden
  example** — stored ground truth. Future runs (and source re-runs) diff
  against it: "still matches your golden output" is a quality statement no
  confidence percentage can make. A "wrong" verdict is a first-class state
  too (amber, feeds review — judging behavior, not AI's self-assessment).
- The terminal block, the run command, and raw stdout/stderr **demote to a
  disclosure** for the developer who wants to interrogate. One artifact,
  one verdict; everything else is footnotes.
- New cell/detail state vocabulary: *Extracted → Proving… → Proven*
  (earned green, receipt attached) or ***Needs you*** (amber: it ran, but
  only a human can say whether the output is right). "Needs you" names the
  developer's irreplaceable role — design it warmer than "needs approval."

## Move 2 — inputs belong to the developer (the new stage)

A module has **inputs, outputs, and a design**. The smoke run staged the
inputs for you; that's the zero-effort floor, not the ceiling. Sometimes
there *can't* just be a run button — the module takes a file, a string, a
flag — and the developer must be free to bring their own. This is the
empowerment moment: *feed it YOUR epub.*

1. **Typed input surface, not a terminal.** At extraction time the engine
   derives each entrypoint's **input signature** (from symbols/params and
   the AI analysis below): file of type X, string, number, choice, env
   var. Render it as compact native controls — a file drop well, a text
   field, a dropdown — **prefilled with the AI-staged demo input**, every
   value swappable. The run button always works untouched (stage-1 floor
   preserved); replacing an input is one gesture, not a form-filling
   session.
2. **The effort spectrum.** Zero-touch *Try it* (AI's staged input) →
   *swap an input* (developer's own data) → ***save as example*** (the
   developer's input + verdict becomes a named, re-runnable case pinned to
   the module — their fixture library). Every developer action persists as
   an asset; nothing they do is a transient click.
3. **Outputs are artifacts.** Same receipt rendering as Move 1. File
   outputs land in the sandboxed run directory with explicit *Save
   result…* / *Reveal in Finder* affordances — never silently written
   into the user's world.
4. **Boundaries, stated calmly.** Some inputs are allowed, some are not:
   types constrained by the signature, file-size caps, no network by
   default, no arbitrary flags, env vars marked sensitive and never
   echoed into receipts. The stage-1 first-run consent treatment carries
   over; boundary violations read as quiet guidance ("this entrypoint
   takes a `.epub`"), not as system warnings.

## The on-demand AI analysis ("How this works")

Somewhere in the detail there is an AI-written analysis of the module's
design: data flow (in → transform → out), the key functions, what it
touches, its limits. The rule is **"if they want to see it" — never in
their face.** It lives behind a single quiet disclosure (e.g. *How this
works*), opens inside the detail sheet, and is generated once at
extraction and cached — opening it must feel instant, not like summoning a
chatbot. The input signature in Move 2 is the *short form* of this
analysis; the disclosure is the long form. Mono only for the code
references inside it.

## Data truth (design only with this)

- Exists today: entrypoints with symbols; bundle on disk; shared-dep
  paths; build command + log; extraction traces; confidence/approval.
- New store state this feature adds: input signatures per entrypoint;
  smoke-run receipts (input ref, output artifact, duration, verdict);
  golden/saved examples; the cached analysis text.
- Still future: agent usage telemetry. Never fabricate usage numbers.

## What NOT to design

A REPL or arbitrary terminal; in-app code editing; dependency graphs;
multi-step pipeline builders; a "test suite" UI. The developer supplies
*data and judgment*, never code, flags, or shell.

## Visual constraints (toolbox-v2 is law)

Neutral graphite; glass on the floating controls layer only; accent green
only on earned, meaningful state (Proven); amber = needs the human; red =
failed; mono only for paths/code/terminal. The detail is moving into the
centered glass sheet (radius 22, blur 50) — all of this lives there.

## Deliverables

1. The receipt treatment per output kind: rendered markdown, pretty JSON,
   playable audio, image, plain text — plus the verdict buttons and the
   pinned golden-example resting state.
2. The typed input surface: prefilled-demo, developer-swapped, invalid
   input, and missing-requirement states; file drop well behavior.
3. The effort spectrum in one composition: Try it → swap input → save as
   example, without three competing CTAs.
4. Saved examples: how a module's named cases list, re-run, and diff
   against golden output.
5. The *How this works* disclosure: closed (one quiet affordance) and
   open (the analysis layout inside the sheet).
6. *Needs you* on the Library cell and in detail (must not break the
   one-trust-verdict-per-cell rule).
7. Open questions — product decisions you need, explicitly listed (e.g.
   how many saved examples before it's clutter, what diffing "matches
   golden" means per artifact type, multi-input entrypoints, timeout UX).
