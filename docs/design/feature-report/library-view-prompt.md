# Design prompt — module library view

> **Status update (2026-06-11):** this brief has been answered once —
> [explorations/toolbox-v1.md](../explorations/toolbox-v1.md) locked the
> cell content/IA but its styling was rejected as "robotic futuristic."
> The next iteration is a *restyle only*; use the verbatim revision
> instruction at the bottom of that doc.

You are redesigning the **module library view** for gunk, a macOS app. A
grid-of-folders version was already designed and rejected. Your job is to
fix the *content of a module cell*, not the grid — the grid layout itself
is fine.

## Why the folder grid failed

It treated modules as static storage: folder icons, names, one green
checkmark, open-and-look affordances. After you've looked inside once,
there's no reason to come back. The view had no "so what?"

## The reframe to design around

A module is not a folder — it's a **capability the user has extracted,
verified, and handed to their AI agent** (via MCP). The human isn't the
module's end user; the agent is. So this view is not a file browser — it's
a **roster of your agent's toolbox**. Each cell must answer, at a glance:

1. **What can my agent do with this?** Show the module's *purpose* line
   ("stitches audio segments with crossfade"), not just its name. Names
   alone force users to memorize what each module does.
2. **Can it be trusted?** Today one ambiguous green checkmark collapses an
   entire trust pipeline. Make the states distinct: confidence score,
   self-containment (passed / needs attention / unverified), build
   verification (passed / failed / skipped), and approval. The meaningful
   axes are *agent-ready vs. not* and *verified vs. needs attention* —
   "runnable" is a secondary trait, so kill the folder-icon vs.
   play-icon split.
3. **Is my agent actually using it?** Usage telemetry ("pulled 14× this
   week") doesn't exist yet — include it as a clearly-flagged future-data
   element, and make sure the cell still works without it.
4. **Which model made this?** Each module states the model that created it,
   with the provider's logo (OpenAI / Anthropic / Ollama). It's provenance,
   not trust — keep it subtle (a small mark, not a badge competing with the
   trust states).

## Constraints

- Keep search and the 12-module-scale grid density.
- Open-in-Finder, run, re-run, delete are secondary actions — they belong
  in a detail view, not on the cell.
- Use only data that exists: name, purpose, tags, language, confidence %,
  approval/extraction state, self-containment + build verification
  results, source it came from. (Usage stats are one flagged exception;
  creating model/provider is the other — the run record tracks it but
  modules aren't linked to runs yet, so design it knowing the wiring is a
  small store change, not a fantasy feature.)
- Existing visual language stays: dark glass surfaces, green accent,
  status badges, tag chips.

## Deliverable

The anatomy of one module cell (and its hover/selected states), plus how
the grid communicates the two trust axes at scan distance — e.g. can I
spot the one module that needs attention in a wall of twelve without
reading every cell?
