# ADR-0005: Monorepo layout

- **Status:** Accepted
- **Date:** 2026-06-01
- **Deciders:** Mark Kohler

## Context

ADR-0002 commits us to two executables in two different languages:

- `gunk-mcp` (TypeScript on Bun)
- `gunk.app` (Swift / SwiftUI)

They share a SQLite database (`~/.gunk/store.db`) as their only contract.
We need to decide whether they live in:

- **A single repo** with `mcp/` and `app/` subdirectories, or
- **Two separate repos** (`gunk-mcp` and `gunk-app`).

## Decision

**Monorepo.** Both packages live under this repo at the root level:

```
gunk/
├── mcp/                # TypeScript on Bun (gunk-mcp)
│   ├── src/
│   ├── test/
│   ├── package.json
│   ├── tsconfig.json
│   └── README.md
├── app/                # Swift / SwiftUI (gunk.app)
│   ├── Sources/
│   ├── Tests/
│   ├── Package.swift
│   └── README.md
├── docs/               # ADRs, roadmap, task specs (existing)
├── .github/            # CI, issue/PR templates
└── (root)              # README, LICENSE, CHANGELOG, etc.
```

CI runs both packages' test suites on every PR. The shared SQLite schema
contract is owned by the `mcp/` package (its source-of-truth migration
files) and consumed by the `app/` package via Swift bindings against the
same schema.

## Why monorepo, not split

- **Schema lives in one place.** The two sides share a SQLite contract; a
  monorepo makes it impossible for them to drift across separate repo
  release cadences.
- **One set of issues, one project board, one CHANGELOG.** Cross-cutting
  features ("expose new field via MCP and surface it in the app") become
  a single PR, not a coordination problem.
- **One set of ADRs.** Architecture lives at the repo root and applies to
  both packages.
- **Simpler for solo dev.** One clone, one branch, one PR review surface.
- **Simpler for outside contributors** later. They see the whole product
  in one place.
- **Trivial to split later** if scale demands. We can extract `mcp/` into
  its own repo with `git filter-repo` if v1 grows enough to warrant it.
  Going from split to merged is much harder.

## Why not split

We considered split repos and rejected them because the costs (above)
clearly dominate the (modest) benefits at v0:

- Independent release cadence — not needed yet; the two ship together.
- Independent issue trackers — not needed; we have ~10 issues total.
- Cleaner isolation per language ecosystem — Bun and Swift coexist in a
  monorepo cleanly via subdirectories with separate tool configs.

## Consequences

### Positive

- Single source-of-truth repo.
- Schema contract enforceable via cross-package tests if we want them.
- Easier first-time-contributor onboarding ("clone this one repo").
- Simpler CI: one workflow file with two parallel jobs.
- One CHANGELOG, one roadmap, one set of ADRs — alignment by construction.

### Negative

- Slightly more complex CI than a single-language repo (need both Bun and
  Swift toolchains in one workflow). This is a 5-line cost.
- A `git clone` includes both languages' code even if a contributor only
  cares about one. Acceptable given the small project size.
- No language-specific homepage on GitHub. Acceptable; the root README is
  the homepage.

### Constraints this locks in

- Both packages share one Git history; commits must be scoped via
  Conventional Commits with package prefixes (`feat(mcp): ...`,
  `feat(app): ...`, `chore: ...` for cross-cutting).
- CI runs both packages' tests on every PR, even if a PR only touches one.
  This is intentional — we never want a cross-cutting break to slip
  through.
- Releases are tagged at the repo level; both packages share a version
  number until/unless we decide otherwise in a future ADR.

## Revisit triggers

Reopen this ADR if:

- One package grows >10× the other and lifecycle pressure emerges.
- Outside contributors materially want to fork one package without the
  other.
- We add a third package (e.g., a Linux UI shell) and the layout becomes
  cramped.

## Related

- ADR-0001: What is gunk? *(Accepted)*
- ADR-0002: Stack and runtime *(Accepted)*
