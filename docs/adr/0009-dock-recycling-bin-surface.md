# ADR-0009: Dock recycling-bin surface

- **Status:** Accepted
- **Date:** 2026-06-04
- **Deciders:** Mark Kohler

## Context

ADR-0003 says gunk should be ambient: the happy-path user should not have to
remember commands or leave their flow. ADR-0004 says ingestion is explicit
drag-in, not passive filesystem watching. The Phase 2 app implemented that as a
menubar app with a drop zone, which proved the mechanics but left the primary
action hidden behind a small status item.

Phase 3 turns gunk into a visible act of recycling useful code. The user should
be able to throw an old project into gunk the way they throw a file into the
Trash. A Dock-resident recycling-bin icon communicates the product metaphor and
creates a large, familiar drop target.

## Decision

**The primary drop target is a Dock recycling-bin icon.**

Concretely:

- `gunk.app` switches from an accessory/menubar-only footprint to a regular
  Dock app by setting `NSApp.setActivationPolicy(.regular)`.
- The Dock icon is a recycling bin with at least three states:
  - empty: no extracted modules yet
  - full: at least one extracted module exists
  - processing: decomposition or extraction is running
- Users drop folders onto the Dock icon to register sources and start
  decomposition.
- The menubar item remains, but its job shifts to Browse, Settings, cost
  visibility, and other secondary controls.

This keeps ADR-0004's explicit drag-in model. The app still only knows about
folders the user gives it; there is no broad watched root and no filesystem
auto-discovery. It also keeps ADR-0003's ambient principle: the user performs a
familiar OS gesture, not a terminal command.

## Consequences

### Positive

- **The product metaphor is obvious.** Old projects go into the recycling bin;
  useful modules come back out.
- **The drop target is easier to hit.** The Dock is larger and more familiar
  than a menubar popover.
- **Processing state has a home.** The Dock icon can show empty/full/processing
  state and a badge count without opening a window.
- **Browse and Settings get cleaner roles.** The menubar remains useful without
  carrying the primary ingestion action.

### Negative

- **Gunk becomes more visible.** A regular Dock icon is a larger footprint than
  the previous menubar-only utility.
- **The app feels less like a background agent.** Some users prefer utilities
  that never appear in the Dock. We accept this because the product needs a
  memorable drop surface.
- **Dock behavior needs testing.** Icon state, badges, folder drops, and launch
  activation all have macOS-specific edge cases.

### Constraints this locks in

- `gunk.app` must use `.regular` activation policy for the Phase 3 experience.
- Dock-drop handling is the primary ingestion path.
- The menubar must not disappear; it remains the place to browse modules,
  re-classify sources, approve low-confidence modules, configure providers, and
  view cost.
- Any future no-Dock mode is an optional preference, not the default Phase 3
  product shape.

## Supersedes / amends

- Amends ADR-0002's app surface from a menubar-only app to a regular Dock app
  plus menubar controls.
- Amends ADR-0003 by making the ambient surface a visible Dock drop target
  instead of an entirely background/menubar utility.
- Preserves ADR-0004's explicit drag-in constraint.

## Related

- ADR-0002: Stack and runtime *(Accepted; app surface amended here)*
- ADR-0003: Ambient over invoked *(Accepted; surface amended here)*
- ADR-0004: Drag-in over file-watch *(Accepted; preserved here)*
- ADR-0008: Gunks are modules *(Accepted)*
- `docs/tasks/phase-3-ai-decomposition.md`
