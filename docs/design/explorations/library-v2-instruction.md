# Revision instruction — Library list view + global processing animation (CP-D)

Date: 2026-06-14 · Status: **CP-D CLEARED.** This is the T-9.1 deliverable
(step 1): the literal instruction fed to Claude Design. The approved
exploration it produced is [library-v2.md](library-v2.md) (with embedded
screenshots and the `library-v2-library.html` source).

> **Scope.** This phase introduces exactly **two** net-new looks: a **list
> (vs. grid) view** of the Library, and a **single global animated processing
> state**. Everything else in the Library is locked by
> [toolbox-v2](toolbox-v2.md) (cell anatomy, palette, grouped grid, hero,
> provider mark) and must not be relitigated. The cell itself
> (`Views/ModuleCell.swift`) is reused as-is. Ground truth for cell content:
> [library-view-prompt.md](../feature-report/library-view-prompt.md).

---

## The verbatim revision instruction (paste into Claude Design)

> You are iterating on the **gunk** macOS Library (dark, native-Tahoe). The
> grid is locked — see the attached toolbox-v2 mockup. Design **two** things on
> top of it, nothing else.
>
> **1. A list view of the same Library data.**
> One row per module, denser than the grid, on the same **solid graphite**
> content surface (cards scroll beneath the floating glass toolbar). Each row
> reuses the cell's existing data, no new fields:
> - one **trust verdict** (Agent-ready / Needs approval / Not in toolbox) —
>   one verdict per row, same vocabulary as the cell;
> - the **name** (prominent), then the **purpose** line (truncated to one line
>   in the row);
> - **`via <model>`** provenance + the **provider mark** (today a small
>   provider-accent color square; design it so a real provider *logo* can drop
>   into the same slot later without a relayout);
> - **tags** (system-font pills, condensed — show what fits, overflow as `+N`).
> - Keep it scannable: at a wall of ~12 rows I must still spot the one
>   **Needs approval** row instantly (carry the amber treatment), and the
>   **Not in toolbox** rows stay dimmed.
>
> The `Project | Model` grouping headers and the ordering carry over from the
> grid. **Decide explicitly what happens to the per-group "hero" (most-used)
> cell in a list** — a row can't be 2× wide and taller. Either flatten it
> (no hero in list) or mark the lead row subtly; pick one and state it as a
> locked constraint. Show: list grouped by Project, list grouped by Model, a
> list with search active, and a list containing a Needs-approval row and a
> Not-in-toolbox row.
>
> Also design the **grid/list toggle** that lives in the Library appbar
> (segmented or icon-pair), and say where it sits in the already-busy single-
> row appbar (title + count, `Project | Model`, search, model picker). Default
> is grid.
>
> **2. A single global animated processing state.**
> While a folder is decomposing, one element animates and reads as "alive"
> without stealing the window — the app stays fully browsable. There must be
> **exactly one** live-run indicator. Today the shell already has these
> processing-related surfaces, and your design must **reconcile, not add a
> fourth**:
> - a **transient processing element** pinned in the sidebar above the MCP chip
>   (spinner + source name + linear progress + "N% · N found");
> - a **pulsing accent dot** on the Library sidebar row;
> - a **run-end toast** (bottom-center, over the detail area) that reports the
>   truthful "N modules added / N need review / failed" outcome;
> - a **persistent MCP chip** pinned at the sidebar bottom (this is *not*
>   processing — leave its job alone, just don't collide with it).
>
> Show the live-run element in these states, because processing is now
> **strictly one-at-a-time with a queue**:
> - one folder running (the animated state);
> - a folder running **with others waiting** — surface queue depth ("1 of 3"
>   or "2 waiting"); there is no "N sources running at once" anymore;
> - the moment it finishes and **resolves into the existing run-end toast**.
> The animation is quiet feedback, not the headline — it must not compete with
> the module cells/rows for scan attention or with the MCP chip. Give a
> **reduced-motion** fallback (a static or minimal-motion variant).
>
> Constraints (all locked, do not change): neutral graphite content surfaces;
> **glass only on the floating controls layer** (sidebar, toolbar, overlays) —
> the live-run animation lives there, never on a content card; accent green
> `#5fe08c` only on meaningful positive state; mono only for paths/code;
> **zero layout shift** when the animation appears/disappears; everything must
> fit the **960pt minimum window** beside the 232pt sidebar.
>
> Deliver dark-mode screenshots of: (a) the list view in both groupings, with
> search and a needs-approval row; (b) the grid/list toggle in the appbar;
> (c) the global processing animation running, the queued state, and its
> hand-off to the toast.

---

## Edge cases this instruction must force the exploration to settle

These are derived from the current code/roadmap, not invented. They are the
places where "follow the exploration" needs an actual answer before T-9.3 /
T-9.4 build.

1. **There are three processing signals today, not one.** The task text only
   names "the persistent MCP chip and the transient processing element." In
   code (`AppShellView.swift`) the live run is *also* a pulsing dot on the
   Library sidebar row (`SidebarProcessingIndicator`) and resolves into a
   bottom-center run-end toast (`RunToastView`). The "single global animated
   state" has to declare which of these survive and how they relate — otherwise
   we ship a fourth indicator instead of reconciling.

2. **Concurrency is real right now.** Each drop spawns its own
   `Task { await runner.process(source:) }` (`AppRuntime.process(source:)`), so
   folders genuinely run in parallel today — `processingStatus` even has a
   `"N sources"` branch. T-9.4 makes it one-at-a-time, so the design must show a
   **queue-depth** state ("1 of 3" / "2 waiting"), and that old "N sources"
   wording dies. The exploration drives what the queued state looks like.

3. **Provider mark set = the real three + neutral.** The provider mark covers
   **OpenAI, Anthropic, Ollama** (the only wired `LLMProvider`s) plus a
   **neutral fallback** (Ollama is local → neutral, no brand logo). **Google/
   Gemini is excluded** — it is not a wired provider, so it does not get a mark
   until it actually ships, even though T-9.2's text and the toolbox-v2 palette
   still mention it (a stale reference for **T-9.2** to reconcile, not a Library
   look this phase designs around). Design the mark slot so the T-9.2 logo can
   replace the color square **without relayout**, because T-9.3 (list) and T-9.2
   (logos) are independent — the list may ship while the mark is still just a
   color badge.

4. **The hero doesn't translate to a list.** The grid's per-group "most-used"
   hero is a 2×-wide, taller cell. A list row can't be. The exploration must
   pick: flatten the hero in list mode, or mark the lead row subtly — and lock
   it, so T-9.3 isn't left guessing.

5. **No fabricated usage.** Usage telemetry still doesn't exist. The grid's
   `N uses this week` is illustrative/fallback only; the list row must not
   present an invented usage number as real. Density comes from real fields
   (verdict, name, purpose, provenance, tags), with usage staying a
   flagged-future element if shown at all.

6. **Toast is the completion surface — don't regress it.** The animation must
   resolve into the **existing** run-end toast, whose "N added" is a truthful
   store diff (engine's mid-run "N found" telemetry must never become the
   completion claim — a real bug T-8.7 fixed). The animation owns *live* state
   only; the toast owns *done*.

7. **960pt + zero layout shift (D15).** Both list and grid must fit at the
   960pt minimum window beside the 232pt sidebar, and the live-run element must
   appear/disappear with no reflow. The toast already sits bottom-center
   specifically because at 960pt the module-detail action row owns the
   bottom-trailing corner; the processing animation's placement must respect the
   same crowding.

---

## After approval (done — CP-D cleared 2026-06-14)

T-9.1 steps 2–3 completed:
- screenshots saved into `docs/design/explorations/` (`library-v2-list.png`,
  `library-v2-processing.png`, `library-v2-toast-success.png`,
  `library-v2-toast-failure.png`) plus the `library-v2-library.html` source;
- [library-v2.md](library-v2.md) written in the toolbox-v2 format, covering
  both the list view and the global processing animation;
- cross-linked from the roadmap Phase 9 item.

CP-D no longer blocks T-9.3 / T-9.4 visual work — they may proceed against the
locked constraints in [library-v2.md](library-v2.md).
