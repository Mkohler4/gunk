# ADR-0008: Gunks are modules

- **Status:** Accepted
- **Date:** 2026-06-04
- **Deciders:** Mark Kohler

## Context

ADR-0001 used "gunk" loosely to mean a useful piece of old code the user wants
their AI tools to reuse. The Phase 2 walking skeleton stored dropped folders in
a `gunks` table, and the MCP tools returned folder-level results. That was a
good skeleton, but it leaves the product pointed at the wrong noun.

The value of gunk is not remembering that an old project exists. The value is
lifting the reusable modules inside that project: auth flows, payment handlers,
UI kits, scrapers, dashboards, CLI utilities, API layers, email senders, search
helpers, and so on. If Cursor asks for Google OAuth, returning an entire old
repo is still expensive and noisy. Returning the extracted auth module is the
product.

ADR-0007 added a first tag taxonomy on top of the folder-level schema. This ADR
does not edit or delete ADR-0007; it records the product decision that makes the
next schema migration more substantial than "folders with tags."

## Decision

**A gunk is an AI-extracted reusable module, not a dropped folder.**

The Phase 3 vocabulary is:

| Term | Meaning |
|------|---------|
| **source** | A folder the user explicitly dropped into gunk. It is raw material. |
| **gunk** | An extracted reusable module that belongs to a source. |
| **bundle** | The physical folder for a gunk: selected files plus a `gunk.yml` manifest. |
| **tag** | A taxonomy label on a gunk, such as `auth`, `payments`, or `ui-kit`. |

This supersedes the folder-level terminology in ADR-0001. It also makes the
folder-level schema from ADR-0006 and the transitional tag schema from ADR-0007
inputs to a new module-level schema, rather than the final data model.

Concretely:

- Dropped folders become `sources`.
- Extracted modules become `gunks`.
- The app decomposes a source into one or more gunks.
- Each gunk can have tags, files, confidence, provenance, approval state, and a
  bundle path.
- MCP tools expose module-level results, not whole dropped folders.

## Consequences

### Positive

- **The product noun matches the user value.** Users want reusable auth,
  payments, UI, and similar pieces, not a list of stale repos.
- **MCP context becomes smaller and sharper.** `search_gunks("auth")` can return
  the extracted auth module instead of the entire source project.
- **Bundles become portable.** A gunk can be copied, inspected, approved,
  removed, and returned to AI tools independently of its source.
- **Future UI is clearer.** Browse views group modules by tag while still
  tracing each module back to the dropped source.

### Negative

- **The schema needs a breaking migration.** The existing `gunks` table name is
  no longer correct for dropped folders. A later ADR must define the exact
  migration from folder-level rows to source and module rows.
- **The decomposition engine becomes central.** If module boundaries are poor,
  the product feels poor. This increases the importance of approval,
  re-classification, provenance, and confidence thresholds.
- **Old documentation can be confusing.** ADR-0001 and early Phase 2 issues use
  "gunk" in the old folder-level sense. Future docs should use "source" for
  dropped folders.

### Constraints this locks in

- `gunk.app` is responsible for decomposing dropped sources into module-level
  gunks.
- The app remains the only writer to the shared store; MCP remains a reader.
- MCP v1 tools must return module-level objects and add search over module
  names, purposes, and tags.
- Extracted bundles live under `~/.gunk/modules/` and contain only selected
  module files, not the whole source project.

## Supersedes / amends

- Supersedes ADR-0001's folder-level use of the word "gunk."
- Supersedes ADR-0006's assumption that the `gunks` table represents dropped
  folders.
- Amends ADR-0007 by making its tag taxonomy apply to module-level gunks rather
  than folder-level gunks in the next schema.

## Related

- ADR-0001: What is gunk? *(Accepted; terminology superseded here)*
- ADR-0002: Stack and runtime *(Accepted)*
- ADR-0004: Drag-in over file-watch *(Accepted)*
- ADR-0006: SQLite schema v0 *(Accepted; folder-level model superseded here)*
- ADR-0007: SQLite schema v1 tags *(Accepted; transitional schema)*
- `docs/tasks/phase-3-ai-decomposition.md`
