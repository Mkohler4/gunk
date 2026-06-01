# ADR-0004: Drag-in over file-watch

- **Status:** Accepted
- **Date:** 2026-06-01
- **Deciders:** Mark Kohler

## Context

An earlier draft of gunk's ingestion model had the macOS app point at a code
directory (e.g., `~/code`) and continuously watch it via a filesystem watcher.
On reflection, this model has serious problems:

1. **Permissions.** Watching arbitrary user directories triggers macOS Full
   Disk Access prompts and a bad first-run experience.
2. **Privacy surface.** "This app is reading my whole code folder" is a
   reasonable concern even if all processing is local. The opt-in surface
   should be much smaller.
3. **Battery + CPU cost.** Continuous watching of arbitrary trees is wasteful
   when most of those projects will never become gunk.
4. **Ambiguity.** The user has no clear mental model for "what's in gunk." Is
   it everything in `~/code`? Just things over a confidence threshold? Just
   things classified successfully? It depends on internal heuristics, and that
   is bad UX.
5. **Implementation complexity.** Filesystem watching at the level of
   `~/code` involves ignore rules, debouncing, handling renames/moves, dealing
   with `node_modules`, and a long tail of cross-platform edge cases.

## Decision

**Gunk only knows about folders the user has explicitly dropped onto the app.**

Concretely:

- The macOS app's primary onboarding surface is a drop zone: "Drag folders
  you want gunk to know about onto this window."
- Each drop is an explicit ingestion event. The user sees what they're
  giving to gunk in the moment they give it.
- Removal is also explicit: the user clicks a button or hits delete on a
  module in the browse view.
- There is **no path config**, **no `~/code` setting**, **no watched roots**,
  **no auto-discovery**.
- We do not call any filesystem-watching API in v0. No `chokidar`, no
  `fs.watch`, no `FSEvents`, no `kqueue`.

### What about updating an existing gunk?

If the user wants gunk to refresh its view of a folder they've already
dropped, they can either:

- Drop the folder again (idempotent — gunk recognizes the path and re-ingests).
- Click "Re-classify" on the module in the browse view.

This is more friction than auto-watching, and that's fine. It's also more
honest about cost: re-classification spends LLM tokens. Making the user
trigger it means they know when they're spending money.

We may add an opt-in "auto-refresh this folder when files change" toggle
*per-folder* in a future version, after the basic drop-and-use product is
loved. That would be a per-folder file watcher, scoped to one ingested
directory, with explicit user consent. Not v0.

## Consequences

### Positive

- **No Full Disk Access prompt at first run.** The user grants implicit access
  when they drop a folder. macOS handles the rest via standard file-open
  semantics.
- **Crisp mental model.** "Things in gunk are things I dropped on gunk." Done.
- **No surprise CPU/battery cost.** Work happens at drop-time, then stops.
- **No ignore-rule complexity.** No `node_modules` heuristics, no `.gitignore`
  parsing, no large-file size thresholds. The user picked the folder; we
  process it.
- **Privacy story is trivial.** "Gunk only sees what you give it. We don't
  scan your filesystem."

### Negative

- **Manual updates.** If the user actively edits code in an ingested folder
  and wants gunk to keep up, they have to re-trigger. Mitigation: make
  re-trigger a one-click affordance.
- **Discoverability.** A user with 100 abandoned projects can't bulk-import
  by pointing at a parent folder. Mitigation: dropping a parent folder
  containing N projects is fine — gunk descends into it once at drop-time
  and registers each as a separate gunk. The constraint is "no continuous
  watching," not "no bulk import."
- **No "set it and forget it" passive accumulation.** The user is involved
  in deciding what's gunk. We argue this is a feature, not a bug — passive
  accumulation gave us the original problem (sprawl) in the first place.

### Constraints this locks in

- The macOS app's primary screen is the drop zone.
- The MCP server is purely read-only from the user's perspective; only the
  app writes to the store.
- The app must make re-classification of an ingested folder easy and obvious.
- Any future "watching" feature is per-folder, per-user-consent, and gets its
  own ADR.

## Revisit triggers

This ADR should be reopened only if user research shows that drag-in is
materially worse than passive watching — for example, if alpha users
consistently say "I'd use gunk more if it just saw all my projects." In
that case the right answer is probably an opt-in, scoped, per-root watcher
behind a clear toggle, not a return to broad filesystem watching.

## Related

- ADR-0001: What is gunk? *(Accepted)*
- ADR-0002: Stack and runtime *(Accepted)*
- ADR-0003: Ambient over invoked *(Accepted)*
