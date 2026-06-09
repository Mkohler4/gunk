# Phase 5 retro: multi-language evals and verification feedback

Phase 5 turned moduleness into something the engine can prove across more than
TypeScript. The important shift is that the quality gate is no longer just
asking whether a module looks coherent. It now has deterministic evidence from
symbol extraction, import resolution, manifests, repo-map survey coverage, and
self-containment.

## What shipped

- Tree-sitter symbol extraction for Dart, Kotlin, and Java, with import/export
  support good enough for mobile and JVM feature slices.
- Manifest parsing for pubspec, Gradle, Maven POMs, and the existing web/server
  manifests so external dependencies are visible to self-containment.
- Multi-language fixtures for Flutter/Dart, Kotlin/Android, Java service, mixed
  monorepo, and a large Java repo, each with golden modules and negative traps.
- Deterministic offline replay evals, including repo-map chunking/map-reduce for
  large repos.
- Quality-gate feedback from self-containment: failed import or entrypoint
  verification downgrades/rejects modules, while verified modules with real
  entrypoints can survive weak graph cohesion.
- Additive `trace.json` verification fields for `selfContainment` and optional
  `build` results.

## Final scorecard

Committed `cd engine && bun run eval` results:

| Fixture | Expected | Actual | File precision | File recall | Tag accuracy | Trap FPs | Self-containment |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| express-saas | 2 | 2 | 1.00 | 1.00 | 1.00 | 0 | 2/2 pass |
| next-media | 2 | 2 | 1.00 | 1.00 | 1.00 | 0 | 2/2 pass |
| flutter-app | 2 | 2 | 1.00 | 1.00 | 1.00 | 0 | 2/2 pass |
| kotlin-android | 2 | 2 | 1.00 | 1.00 | 0.75 | 0 | 2/2 pass |
| java-service | 2 | 2 | 1.00 | 1.00 | 0.75 | 0 | 2/2 pass |
| mixed-monorepo | 3 | 3 | 1.00 | 1.00 | 0.83 | 0 | 3/3 pass |
| large-repo | 2 | 2 | 1.00 | 1.00 | 0.75 | 0 | 2/2 pass |

The non-1.00 tag scores are expected right now: some golden labels such as
`orders` and `reports` are domain names that are not in the persisted tag
taxonomy, so the engine keeps the supported tags and the gate relies on file
precision/recall plus trap checks for those fixtures.

## Real Flutter capability

`flutter-app` proves a genuine multi-file mobile module, not a file-level chunk:

- Module: `Email password authentication`
- Tags: `auth`, `mobile`
- Files:
  - `lib/features/auth/auth_controller.dart`
  - `lib/features/auth/auth_repository.dart`
  - `lib/features/auth/auth_state.dart`

The controller imports the repository and state object. The repository imports
`firebase_auth` and `flutter_secure_storage`, signs in with email/password,
stores the session user, and restores cached sessions. The state file is owned
because it is part of the feature surface, not emitted as a standalone type trap.

## What changed from the Phase 4 floor

Phase 4 proved the capability-centric pipeline on two web fixtures:
`express-saas` and `next-media`. Phase 5 keeps both at perfect precision,
recall, tag accuracy, and zero trap false positives, while adding five more
fixtures across mobile, JVM, mixed-language monorepos, and large-repo survey
chunking.

The gate is stricter than before. A plausible module can now fail if it claims a
fake entrypoint, omits an internal collaborator, or imports an undeclared
external dependency. The useful counterweight is that sparse but real modules,
like JVM controller/service pairs or mobile controller/store slices, can pass
when deterministic self-containment verifies the module boundary.

## Build verification

Build verification remains eval/trace feedback, not a decomposition gate. Some
fixtures are intentionally partial and report skipped or failed builds. The
quality contract for Phase 5 is self-containment plus scorecard floors, not
successful fixture compilation.

## Follow-ups

- Decide whether domain labels such as `orders` and `reports` should become
  taxonomy tags or stay as names/anchors.
- Keep adding manifest parsers only when they feed deterministic verification or
  capability hints.
- Use the proxy-agreement metrics to find where gate heuristics still disagree
  with self-containment evidence.
