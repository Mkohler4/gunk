# Design prompt — gunk layout redesign

> Copy everything below this line into Claude, with the seven feature-report
> documents in this folder attached (README + 01–07).

---

You are redesigning the entire layout of **gunk**, a macOS (SwiftUI) app.
The app works end-to-end but its current layout is confusing to use. You
have been given a complete, code-accurate feature report (README plus seven
per-page documents) describing every surface, control, behavior, state, and
known problem as the app exists today. Treat those documents as ground
truth — do not invent features that aren't in them, and do not assume data
exists that they don't mention.

## What gunk is

gunk turns dropped folders of code into **modules**: an LLM engine
decomposes the folder, verifies each module (self-containment, build),
scores its confidence, and — once a module is auto-accepted or manually
approved — **extracts** it so an AI agent can use it through an MCP server.
The journey is: drop a folder → engine processes → modules appear →
low-confidence modules wait for human review → approved modules become
**Agent-ready** (visible to the user's agent via MCP).

## The central design thesis (this is the reframe your redesign must express)

**A module is not a folder. It is a capability the user has extracted,
verified, and handed to their agent.** The human is not the module's end
user — the agent is. The human's job is intake (drop folders) and trust
(review what the engine wasn't sure about). The payoff — "this is now
available to your agent" — is the emotional core of the product and is
nearly invisible in the current app.

Consequences you should design around:

- The modules surface is a **roster of capabilities**, not a file browser.
  Each module's identity is its *purpose* ("stitches audio segments with
  crossfade"), not its file tree. A Finder-style grid of folder icons is
  explicitly the wrong metaphor — it was tried and rejected.
- **Trust is the human's real work.** The verification pipeline
  (confidence score → self-containment → build verification → approval →
  extraction) must be legible, not collapsed into a single ambiguous
  checkmark. "Agent-ready vs. not" and "verified vs. needs attention" are
  the meaningful axes; "runnable" is a secondary trait.
- **The payoff moment needs a stage.** Today, run completion is an
  8-second sidebar chip and manual approval gives zero feedback. Approving
  a module and seeing it become agent-ready should feel like the point of
  the product.
- **Review is the highest-stakes interaction** and currently the worst
  surface: Reject permanently deletes with no confirmation, sits 6 pt from
  Approve, and the reviewer can't inspect the module before deciding.

## What must be fixed (drawn from the report's "known problems" sections)

1. The sidebar status strip is four features in one chip (MCP health, live
   progress, completion toast, failure alert) with a different click
   target per state. Decompose it.
2. Approval and Runs were never re-skinned and feel like a different app.
   The redesign must bring every page onto one visual and structural
   system.
3. Destructive actions (reject module, delete module, delete source) are
   one-click and irreversible. Design confirmation/undo patterns.
4. Confidence percentages appear everywhere with no threshold context; the
   threshold slider in Settings is unlabeled and disconnected from the
   Approval concept it controls.
5. Runs is a developer debug panel disconnected from everything (no links
   run↔modules, no auto-refresh during a run, raw milliseconds). Decide
   whether it stays a page, becomes a drawer/inspector, or folds into
   sources/modules history.
6. The Modules page's three-pane density (everything caption-sized)
   dictates the whole app's geometry (960×600 minimum, fixed sidebar,
   padding hacks). Relaxing this page relaxes the app.
7. Empty, filtered-empty, processing, and error states are inconsistent
   page-to-page; several errors inject above content and shift layout.

## Constraints

- macOS desktop app, SwiftUI. Light on chrome; supports drag-and-drop from
  Finder and onto the Dock icon.
- **The whole window is a drop target.** Dragging a folder anywhere over
  the app raises a full-window drop overlay floating above the current
  view; nothing in the underlying layout moves or reflows. Drops work from
  any section. Design the overlay's idle-drag and ready-to-drop states.
- A frozen brand visual system exists (dark glass surfaces, accent green,
  glass cards, status badges, tag chips, brand buttons, wordmark). You are
  redesigning **layout, information architecture, hierarchy, and flows** —
  not the visual language. Use the existing component vocabulary.
- Minimum window 960×600 today; you may propose changing it if your layout
  justifies it.
- **Data constraint:** design only with state the app already has —
  sources, modules (name, purpose, tags, language, confidence,
  approval/extraction state, bundle path, files, dependencies,
  entrypoints, verification results), run traces (stages, timings, counts,
  errors), processing progress, and the five settings health checks.
  **Exception:** agent *usage* telemetry ("your agent pulled this module
  14× this week") does not exist yet — you may include it in designs, but
  it must be clearly flagged as a future-data feature and the layout must
  not collapse without it.
- You may restructure navigation entirely — the current five sections
  (Sources, Modules, Approval, Runs, Settings) are not sacred. Merging,
  renaming, nesting, or demoting surfaces is allowed as long as every
  capability in the feature report remains reachable.

## Deliverables

1. **Information architecture** — the new navigation model: what the
   top-level surfaces are, what lives where, landing behavior, and how the
   core journey (drop → process → review → agent-ready) flows through it.
2. **Per-surface layout specs** — for each surface: purpose, primary
   action, content hierarchy, structural wireframe (ASCII or description),
   and exactly where each feature from the report's inventory now lives.
   Account for every feature; if you cut one, say so and justify it.
3. **State specifications** — empty, first-run, processing, filtered-empty,
   error, and transient/celebration states for each surface, with one
   consistent system for all of them.
4. **The payoff design** — the specific moment-by-moment treatment of run
   completion and module approval, including the unconfigured-MCP variant.
5. **Destructive action patterns** — confirmation/undo design for reject
   and the two deletes.
6. **Open questions** — anything where you need a product decision rather
   than a design decision.

Work from the feature report's "known problems & quirks" lists as your
issue backlog; every problem should be resolved, consciously deferred, or
argued against in your output.
