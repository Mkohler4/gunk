# Phase 13 — Walkthrough / onboarding (+ carried-over stretches)

This phase delivers the first-launch experience: a branded, animated intro
that ends on a plain screen with exactly two choices — drop a folder, or
browse the marketplace. It is built last on purpose; it needs marketplace
content (Phase 12) and the final IA to point at.

Roadmap: [docs/roadmap.md → Phase 13](../roadmap.md). The onboarding tasks
themselves are **not yet broken down** — this doc currently only carries the
graph-view stretch moved out of Phase 9. The onboarding task list will be
written when this phase comes up.

## Carried-over stretches

### Module relationship graph view (from Phase 9, was T-9.6)

**Owner:** agent
**Checkpoint:** none (explicit stretch — cut freely)

Moved here from
[Phase 9](phase-9-library-v2-and-processing-states.md) on 2026-06-14: it is
the lowest-value, "looks-good-only" item in the redesign arc and was
deferred so Phase 9 could close on the load-bearing work (durable
attribution, list view, processing queue, Dock badge). It carries no
acceptance pressure and is cut without ceremony if it competes with the
Library for attention.

#### Goal
A graph view where same-repo modules cluster as one entity and clicking a
cluster morphs it into that module's files. **Explicitly low value**
(roadmap: "looks-good-only") — time-boxed, behind a toggle, and cut the
moment it competes with the Library for attention.

#### Files
- `app/Sources/GunkApp/Views/` (new graph view, opened from a Library
  affordance — not a new top-level section)
- `app/Sources/GunkApp/Models/BrowseModel.swift` (read-only: existing
  source/module/files relationships; no new data)

#### Task execution (agent prompt)

> 1. `[HOLD FOR ME]` Confirm with me that this is worth starting before any
>    code — it is the lowest-priority item in the arc and ships only if the
>    surrounding phase work is done and solid.
> 2. Build a graph from data that **already exists** (sources → modules →
>    owned files); invent no new store state and no usage edges.
> 3. Open it from a quiet Library affordance (not a new sidebar section).
>    Same-repo modules cluster; click-through morphs a cluster into the
>    module's files.
> 4. `swift build`, `swift test`, screenshot the graph and the
>    cluster→files morph.

#### Refining loop
- If it reads as a tech demo rather than something useful, **stop and cut
  it** — say so plainly in the summary. This item has no acceptance pressure.

#### Human-in-the-loop (me)
- I decide go/no-go up front, and again on the first screenshot.

#### Acceptance
- Either a graph view built strictly on existing data behind a quiet
  affordance, or a documented decision to cut it. No new store state. Build +
  tests green.
