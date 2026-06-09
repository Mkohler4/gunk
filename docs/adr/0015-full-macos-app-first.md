# ADR-0015: Full macOS app first

- **Status:** Accepted
- **Date:** 2026-06-09
- **Deciders:** Mark Kohler

## Context

Earlier roadmap language described `gunk.app` as a menubar utility with a
secondary popover. ADR-0009 moved the product away from menubar-only by making
the Dock recycling-bin surface the primary ingestion target, and the current app
already launches with regular app activation.

That direction needs to be explicit. The next product priority is not more
background wiring or a tiny accessory. It is a legitimate macOS app users can
open, understand, and use directly.

## Decision

`gunk.app` is a full macOS app first.

The default user-facing surface is a regular Dock app with windows, navigation,
drop/import flows, module browsing, module detail, settings, runs/debugging, and
approval workflows. A menubar item may remain as a secondary shortcut, but it is
not the product's primary UI.

AI-tool auto-wiring is valuable, but it moves behind the app shell in priority.
Manual MCP setup can continue to serve early developer testing until the app is
good enough to deserve one-click setup.

## Consequences

### Positive

- The product can be judged as an actual Mac app, not a hidden utility.
- Browse, approval, settings, and run traces have enough room to be usable.
- The Dock recycling-bin metaphor stays visible and understandable.
- Future onboarding can happen inside the app instead of in docs and config
  snippets.

### Negative

- The app surface has more design and QA burden than a menubar popover.
- One-click AI-tool wiring slips until the core app experience is coherent.
- Existing roadmap/task specs that say "menubar app" are stale and must be
  treated as historical context unless superseded by newer docs.

## Current product priorities

1. Full macOS app shell and navigation.
2. Clear source import/drop flow.
3. Browse modules by source, tag, and status.
4. Module detail showing owned files, shared dependencies, entrypoints,
   self-containment, and bundle path.
5. Approval queue and re-run/reclassify controls.
6. Settings for providers, model, local store, and MCP config status.
7. Packaging, signing/notarization, and update path.
8. One-click AI-tool wiring after the above feels real.

## Supersedes / amends

- Supersedes ADR-0002's "menubar app" wording for the primary app surface.
- Amends ADR-0009: the Dock surface remains primary for ingestion, but the
  app's main experience is a full windowed macOS app.

## Related

- ADR-0002: Stack and runtime *(Accepted; app surface superseded here)*
- ADR-0009: Dock recycling-bin surface *(Accepted; amended here)*
- ADR-0013: AI pipeline moves to a TS/Bun engine *(Accepted)*
