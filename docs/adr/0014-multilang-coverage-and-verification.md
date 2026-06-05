# ADR-0014: Multi-language coverage and verification

- **Status:** Accepted
- **Date:** 2026-06-05
- **Deciders:** Mark Kohler

## Context

ADR-0012 made decomposition capability-centric: parse source, build structure,
survey candidates, expand graph closures, refine, then enforce deterministic
quality gates. ADR-0013 moved that pipeline into `gunk-engine`, a TypeScript/Bun
engine that owns analysis, decomposition, extraction, evals, and trace output.

Phase 5 keeps both decisions. This ADR extends, not supersedes, ADR-0012 and
ADR-0013.

The acute symptom is language coverage. The engine is hard-wired to 5 languages
and a web-centric surface model: Go, JS/TS/TSX, Python, and Swift.
Flutter/Dart, Kotlin/Android, Java, Gradle, and mobile manifests fall through to
weak fallback analysis. That produces near-zero symbols, sparse graphs, empty
fingerprints, signal-free repo maps, weak survey hypotheses, and quality-gate
rejections as trivial or surface-less.

The deeper disease is that moduleness is asserted, never tested. In ADR-0012,
"module" is operationally enforced by stacked heuristics: survey, graph closure,
refine, and quality gates. Those are useful correlates, but they do not prove a
bundle stands alone. `confidence` is the model grading its own answer, and
`cohesion` is import coupling, not capability coherence. Extraction already
creates bundles, but today its result does not feed back into accept/reject.

### Part A — gating diagnostic (code-derived)

Traced over a representative 10-file Flutter fixture (7 `.dart` files in `lib/`,
`pubspec.yaml`, a Groovy `build.gradle`, a Kotlin `MainActivity.kt`,
`AndroidManifest.xml`). The deterministic stages need no API key.

- **scan:** ~10/10 source files kept; `build/`, `.dart_tool/`, `.gradle/`
  correctly ignored. **No meaningful loss.**
- **symbols:** 0/10 files use a real grammar -> **0% parse coverage**; fallback
  yields ~8 class symbols, **0 functions/methods, 0 exports**.
- **graph:** only `../`-prefixed Dart imports resolve (by accident of the `""`
  exact-suffix match; `extensions` has no `.dart`/`.kt`). `main.dart`'s imports
  both fail; ~5/12 intra-repo imports become edges; rest are fragile textual
  class-name edges. **0 edges touch Kotlin/Gradle/manifest.**
- **fingerprints:** routes 0, publicExports 0, importedDependencies 0
  (`pubspec.yaml`/Gradle not in `MANIFEST_BASENAMES`), capabilityHints 0,
  envVars 0, configKeys 0 -> **`hasPublicSurface` false for 10/10 files.**
- **repoMap:** no truncation on a small repo, but **zero `routes:`/`hints:`/
  `exports:`/`env:` lines** — structurally present, signal-free.
- **survey/refine/gates (projected):** signal-free map + exact-path filter ->
  few hypotheses survive; survivors rejected as `missingSurface`.

**Decision gate: GO — coverage-broken, not structurally broken.** The pipeline
shape is language-agnostic; fixing coverage should restore signal. Verdicts:
(a) language coverage CONFIRMED-primary; (b) ignore rules REFUTED; (c) import
resolution CONFIRMED-contributing; (d) web-centric surface + unparsed manifests
CONFIRMED-primary; (e) repo-map truncation REFUTED for small repos (real for
large); (f) survey path-filter PLAUSIBLE-secondary.

## Decision

### Coverage policy

Parse-driven structure stays. Adding a language means following the existing
per-language pattern:

- a tree-sitter grammar loaded by `gunk-engine`
- node-type collectors for symbols, functions/methods, exports, imports, and
  entrypoints
- ecosystem import resolution for relative, package, bare, generated, and
  platform-specific references
- manifest and lexicon entries for dependencies, capability hints, config, and
  non-web public surfaces

Coverage fixes should restore signal to the existing structure-first pipeline,
not replace it with language-specific decomposition paths.

### Verification feedback

`gunk-engine` adds a deterministic self-containment signal that backstops the
heuristic `confidence` and `cohesion` gates. A candidate module is
self-contained when:

- its internal imports resolve within the extracted bundle plus declared shared
  files and external dependencies
- its claimed entrypoint exists in the bundle
- the claimed entrypoint is public or exported according to that language's
  surface rules

This signal may change accept/reject: a self-contained low-cohesion module can
survive, and a non-self-contained tangle can be downgraded. The heavy build
check is eval-only and optional at runtime; it never gates a run.

The `trace.json` schema is extended, never broken. Verification fields are
additive and optional so existing Swift Runs-tab decoding remains
backward-compatible.

### Eval policy

Per-stage signal floors fail loudly. The eval suite must catch near-zero parse
coverage, missing graph density, empty surface fingerprints, and rejected
modules before those losses hide inside aggregate precision/recall.

The Phase 4 baseline in `docs/retros/phase-4-eval-baseline.md` is a hard floor:
`express-saas` and `next-media` stay at 1.00 file precision, 1.00 file recall,
1.00 tag accuracy, and 0 trivial false positives.

CI runs deterministically with no API key by replaying recorded LLM calls.

## Consequences

### Positive

- Moduleness becomes a tested property, not just a survey/refine/gate assertion.
- New languages are mechanical additions to the parse, import, manifest, and
  lexicon layers.
- Failures show up as numbers: parse coverage, graph density, surface signal,
  self-containment, build verification, and regression scorecards.
- ADR-0012's rubric remains the definition of a real module, with verification
  as a new deterministic backstop.
- ADR-0013's engine boundary remains intact: Phase 5 work lands in
  `gunk-engine`, with trace and NDJSON contracts extended compatibly.

### Negative

- The engine has another stage to build, maintain, trace, and explain.
- Replay tapes become part of eval maintenance.
- Each language now needs enough import, manifest, and public-surface knowledge
  for self-containment to be meaningful.
- Additive trace fields must stay in sync with Swift Runs-tab decoding and
  schema-parity checks.
