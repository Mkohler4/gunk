# Phase 5 — Multi-language coverage, AI evals, and verification feedback

> The phase where gunk stops going blind on whole repos in languages it cannot
> parse (Flutter/Dart, Kotlin, Java), and — more importantly — stops *asserting*
> what a module is and starts *testing* it. We build multi-language evals that
> fail loudly on signal loss, close the language-coverage gaps, then add a
> verification stage that proves an extracted bundle actually stands alone and
> feeds that real signal back into the accept/reject decision.

**Scope: engine + evals only.** All work lands in the `gunk-engine` package
([ADR-0013](../adr/0013-ts-decomposition-engine.md)). No app/UI changes. The
NDJSON contract and `trace.json` schema are **extended, never broken**; MCP <->
Swift <-> engine schema parity (`scripts/check-schema-parity.sh`) and engine
determinism (`temperature: 0`, stable sorting) hold throughout.

**We do not regress.** The Phase 4 baseline
([phase-4-eval-baseline.md](../retros/phase-4-eval-baseline.md)) — `express-saas`
and `next-media` at 1.00 file precision/recall/tag accuracy with zero trivial
false positives — is a hard floor for every task.

**Demo at end of phase:**

1. From a clean state, run the engine on a real Flutter repo:
   `cd engine && bun run src/index.ts <repo> --provider <p> --model <m> --db /tmp/p5.db --gunk-home /tmp/p5 --json --trace`.
2. The trace shows non-zero parse-coverage on `.dart`/`.kt` files, a real graph,
   and **>= 2 accepted modules** (e.g. Authentication, User/API).
3. The eval suite runs deterministically in CI with **no API key** (replayed
   LLM calls) and **fails loudly** if any fixture drops below its signal floor.
4. Every accepted module passes a deterministic **self-containment** check, and a
   module that does not stand alone is downgraded rather than silently accepted.

If that works end-to-end, Phase 5 is done.

---

## The two problems this phase fixes

### Acute (symptom): the engine is hard-wired to 5 languages and a web surface

`languageKindForPath` ([`models.ts`](../../engine/src/models.ts)) and the loaded
tree-sitter grammars only cover Go, JS/TS/TSX, Python, Swift. A Flutter repo is
mostly Dart (+ Kotlin/Java/Gradle), all of which become `"unknown"` -> regex
fallback. The fallback finds `class X` but **no functions/methods and zero
exports**, so the cascade is: near-zero symbols -> sparse graph -> empty
fingerprints/routes -> a signal-free repo map -> survey proposes almost nothing
-> quality gates reject the rest as trivial.

A second bias compounds it: even with perfect parsing, the fingerprints that give
a module a "surface" are JS/Python-web-centric (HTTP routes, a `stripe ->
payments` lexicon). A mobile/CLI/SDK codebase can parse fine and still look
surface-less to the `missingSurface`/triviality gates.

### Deeper (disease): moduleness is asserted, never tested

Fixing parsing does not fix the root problem: **the pipeline never knows what a
module is.** "Module" is the fixed point of four stacked heuristics, each a
*correlate* of moduleness, not moduleness itself:

- **survey** proposes from a budgeted text summary — it never sees code.
- **expansion** defines the boundary purely topologically (BFS <= 3 import hops,
  <= 25 files) — a graph cutoff, not a semantic one.
- **refine** judges from <= 32k chars of truncated content.
- **quality gates** are the real operational definition
  ([`qualityGate.ts`](../../engine/src/decompose/qualityGate.ts)): a module is
  `hasSurface AND cohesion >= 0.35 AND not-all-trivial AND confidence >= 0.7 AND
  not-duplicate`. `hasSurface` is JS/web fingerprints; `cohesion` measures import
  coupling, not capability coherence; `classify` is literal path/string matching;
  `confidence` is the LLM grading its own homework; the `0.35`/`0.7`/`0.85`
  constants are unfalsifiable within a single run.

Ground truth only ever enters **offline and human-dependent**: the hand-authored
`expected.json` fixtures and `needsApproval` manual review. The pipeline
*extracts* bundles (stage 11) but extraction is best-effort and **never feeds
back** into accept/reject. The real test of "is this a reusable capability" is
operational — extract it and see if it stands alone (imports resolve, it builds,
its claimed entrypoint exists). This phase adds that loop.

---

## Part A — gating diagnostic (code-derived)

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

---

## Dependency graph

```
T-5.0  ADR-0014 (coverage + eval floors + verification feedback)
   │
   ▼
T-5.1  Multi-language golden + negative fixtures (Dart/Kotlin/Java/monorepo/large)
   │
   ▼
T-5.2  Per-stage signal metrics in scorecard + trace; near-zero-signal guard
   │
   ▼
T-5.3  Offline replay eval harness + eval CLI/report + CI gate
   │
   ├──────────────► (coverage; turns the red fixtures green)
   ▼
T-5.4  Dart symbol extraction (tree-sitter-dart grammar + collectors)
   │
   ▼
T-5.5  Dart import resolution (.dart ext + package:/bare/lib specifiers)
   │
   ├──► T-5.6  pubspec.yaml + Gradle manifests + Dart/mobile lexicon
   │
   ├──► T-5.7  Kotlin + Java coverage (same pattern)
   │
   ▼
T-5.8  Generalize surface / relax non-web gates (no new trivial FPs)
   │
   ├──────────────► (verification; makes moduleness a tested property)
   ▼
T-5.9  Deterministic self-containment verifier (imports + entrypoint)
   │
   ├──► T-5.10 Build verification (eval-only / optional runtime, sandboxed)
   │
   ▼
T-5.11 Gate feedback: wire self-containment into the quality gate
   │
   ▼
T-5.12 Proxy re-examination: tune/replace cohesion/surface/classify
   │
   ├──► T-5.13 Large-repo repo-map chunking / map-reduce survey
   │
   ├──► T-5.14 Prompt/quality improvements (coverage fixed first)
   ▼
T-5.15 Phase-5 eval gate + ARCHITECTURE update + retro + roadmap
```

---

## Phase complete checklist

- [ ] All tasks merged to `main`, CI green (incl. schema-parity + engine job)
- [ ] No app/UI changes; NDJSON + `trace.json` schema extended, not broken
- [ ] ADR-0014 accepted and linked from the ADR index
- [ ] Multi-language fixtures exist; the eval suite runs deterministically in CI
      with no API key and **fails loudly** below each fixture's signal floor
- [ ] Flutter fixture: **parse-coverage >= 90%** of `.dart` files yield >= 1 real
      symbol incl. functions/methods; **>= 2 accepted modules** at
      **file_recall >= 0.8**
- [ ] Kotlin/Java/mixed-monorepo fixtures each produce >= 1 accepted module with
      non-zero parse-coverage and edge density
- [ ] **100% of accepted modules pass deterministic self-containment** across all
      fixtures; every golden module's bundle builds in the eval-only build check
- [ ] Gate feedback demonstrably flips >= 1 decision (a self-contained low-cohesion
      mobile module survives; a non-self-contained tangle is downgraded)
- [ ] Regression floor intact: `express-saas`/`next-media` stay at 1.00/1.00/1.00
      with 0 trivial false positives
- [ ] `engine/docs/ARCHITECTURE.md` updated; phase-5 retro committed with numbers

---

## Tasks

### T-5.0 — ADR-0014 (multi-language coverage + eval floors + verification feedback)

**Status:** Not started
**Owner:** Codex

#### Goal
Ratify the Phase 5 direction before building it: language coverage is a symptom;
the structural fix is a **verification-feedback** loop that defines moduleness as
a tested property (a bundle that stands alone), backstopping the heuristic gates.

#### Why
Adding a verification stage that can change accept/reject is a hard-to-reverse
architectural decision. It needs its own ADR extending — not superseding —
[ADR-0012](../adr/0012-capability-centric-decomposition.md) (the rubric/gates) and
[ADR-0013](../adr/0013-ts-decomposition-engine.md) (the engine boundary).

#### Prerequisites
None.

#### Files
- `docs/adr/0014-multilang-coverage-and-verification.md` (NEW; Status: Accepted)
- `docs/adr/README.md` (index)

#### Execution steps
1. Capture the Part A diagnostic + go/no-go decision verbatim.
2. State the coverage policy: parse-driven structure stays; new languages = a
   grammar + node-type collectors + ecosystem import resolution + manifest/lexicon.
3. Define **verification feedback**: a deterministic self-containment signal
   (imports resolve within bundle+declared deps; claimed entrypoint exists/is
   public) backstops `confidence`/`cohesion`; a heavy build check is eval-only and
   never gates a run. The `trace.json` schema is extended, never broken.
4. State the eval policy: per-stage signal floors fail loudly; the Phase 4
   scorecard is a hard floor; CI runs deterministically via replayed LLM calls.

#### MCP touchpoints
None (documentation only).

#### Tests required
None — documentation only.

#### Execution objective
The ADR is the canonical contract T-5.1 → T-5.15 align to.

#### Definition of done
- [ ] ADR-0014 accepted, linked from the index, extends ADR-0012/0013
- [ ] Includes the diagnostic, the verification-feedback contract, and eval floors
- [ ] PR title: `docs: ratify multi-language coverage + verification feedback (ADR-0014)`

---

### T-5.1 — Multi-language golden + negative fixtures

**Status:** Not started
**Owner:** Codex

#### Goal
Add whole-repo, multi-language fixtures that encode the failure we are fixing: a
Flutter/Dart app, a Kotlin/Android module, a Java service, a mixed monorepo, and
one large repo (for truncation). Each has hand-labeled `expected.json` and
negative traps. Keep `express-saas`/`next-media` as the regression floor.

#### Why
The eval harness can only catch the Flutter failure if a Flutter repo is in the
corpus. These fixtures are the red tests the coverage tasks (T-5.4 → T-5.8) turn
green, and the corpus the verification tasks measure against.

#### Prerequisites
T-5.0.

#### Files
- `engine/test/fixtures/flutter-app/` (NEW; `lib/**.dart`, `pubspec.yaml`,
  `android/**` Kotlin + Gradle + `AndroidManifest.xml`)
- `engine/test/fixtures/kotlin-android/`, `engine/test/fixtures/java-service/`,
  `engine/test/fixtures/mixed-monorepo/`, `engine/test/fixtures/large-repo/` (NEW)
- `engine/test/fixtures/<each>/expected.json` (modules -> {tags, files} +
  `must_not_be_modules: [...]`, matching `loadExpected` in
  [`scorecard.ts`](../../engine/src/eval/scorecard.ts))

#### Execution steps
1. Author each fixture as a small but realistic project with >= 2 genuine
   capabilities and >= 1 trap (a lone types file / a `utils/` dir / generated).
2. Hand-label `expected.json` for each; the large-repo fixture is sized to exceed
   the default 20k-token (~80k-char) repo-map budget.
3. Do **not** wire them into assertions yet (coverage is not implemented) — they
   land with T-5.2's signal metrics so the failure is visible as numbers.

#### MCP touchpoints
None.

#### Tests required
- [ ] `evalGate.test.ts` loads each new fixture's `expected.json` without error
- [ ] a smoke test confirms each fixture scans to a non-empty file list

#### Execution objective
Running the offline stages over `flutter-app` reproduces ~0% parse-coverage and a
signal-free repo map (the documented failure), now as a committed fixture.

#### Definition of done
- [ ] 5 multi-language fixtures + `expected.json` + traps committed
- [ ] Existing fixtures untouched; `loadExpected` parses every new label file
- [ ] PR title: `test(engine): multi-language golden + negative fixtures`

---

### T-5.2 — Per-stage signal metrics + near-zero-signal guard

**Status:** Not started
**Owner:** Codex

#### Goal
Extend the scorecard beyond final precision/recall with **per-stage signal
metrics** read off `trace.json`, and make a run that produces near-zero signal
**fail loudly** instead of silently returning nothing.

#### Why
The Flutter failure was invisible because the only number was the final score. A
parse-coverage / edge-density / hypothesis-count floor turns "produced nothing"
into a red test.

#### Prerequisites
T-5.1.

#### Files
- `engine/src/eval/scorecard.ts` (add a `SignalMetrics` struct + extractor)
- `engine/src/trace/trace.ts` (ensure `stages[].counts` + a `parseCoverage` count
  are recorded; extend `trace.json`, do not break existing fields)
- `engine/src/analyze/symbolExtractor.ts` (mark fallback vs real-grammar files so
  parse-coverage is measurable, e.g. a `viaFallback` flag on `FileSymbols`)
- `engine/test/scorecard.test.ts` (extend)

#### Execution steps
1. Add a `viaFallback`/`parsed` signal to symbol extraction so "files with >= 1
   real (non-fallback) symbol" is computable; surface the count in `trace.json`.
2. Compute `SignalMetrics` from a trace: parse-coverage %, graph edge density,
   survey hypothesis count, mean/median expansion closure size, and a
   gate-rejection histogram keyed by `QualityGateReason`.
3. Add `assertSignalFloor(metrics, floor)` that throws a descriptive error when a
   metric is below a fixture-declared floor.

#### MCP touchpoints
None for the SQLite store. **`trace.json` gains fields** read by the Swift Runs
tab ([`RunTrace.swift`](../../app/Sources/GunkApp/Engine/RunTrace.swift)) — keep
new fields additive/optional so Swift decoding stays backward-compatible.

#### Tests required
- [ ] `scorecard.test.ts > computes parse-coverage from a trace`
- [ ] `scorecard.test.ts > builds a gate-rejection histogram`
- [ ] `scorecard.test.ts > assertSignalFloor throws below the floor`

#### Execution objective
Scoring the `flutter-app` trace reports ~0% parse-coverage and trips the floor.

#### Definition of done
- [ ] Signal metrics computed from `trace.json`; near-zero-signal trips a failure
- [ ] `trace.json` extension is additive; Swift decoding unaffected
- [ ] PR title: `feat(engine): per-stage signal metrics + near-zero-signal guard`

---

### T-5.3 — Offline replay eval harness + eval CLI/report + CI gate

**Status:** Not started
**Owner:** Codex

#### Goal
Make the eval suite deterministic in CI **without API keys** by recording and
replaying real LLM calls from `trace.json`, expose an `eval` report, and wire the
multi-language fixtures + signal floors into the engine CI job.

#### Why
Live LLM calls are non-deterministic and key-gated. Replay (extending the
`QueuedClient` pattern in [`evalGate.test.ts`](../../engine/test/evalGate.test.ts))
lets coverage and verification work be gated reproducibly.

#### Prerequisites
T-5.2.

#### Files
- `engine/src/eval/replayClient.ts` (NEW; an `LLMClient` that replays
  `llmCalls[].responseJson` from a saved `trace.json`, matched by `stage`/order)
- `engine/src/eval/runEval.ts` (NEW) + `engine/src/index.ts` (add an `eval`
  subcommand/report) — preserve the existing CLI contract
- `engine/test/fixtures/<each>/recorded-trace.json` (NEW; committed replay tapes)
- `.github/workflows/ci.yml` (engine job runs the eval over all fixtures)

#### Execution steps
1. Implement `ReplayClient` reading a fixture's recorded trace; assert the prompt
   shape matches so a stale tape fails loudly rather than silently mismatching.
2. Add an `eval` report (scorecards + signal metrics per fixture) usable locally
   and in CI; hold the Phase 4 baseline as a floor.
3. Extend the `engine` CI job to run the eval; keep it key-free and deterministic.

#### MCP touchpoints
None.

#### Tests required
- [ ] `evalGate.test.ts > replays recorded LLM calls deterministically`
- [ ] `evalGate.test.ts > stale replay tape fails loudly`
- [ ] eval report holds `express-saas`/`next-media` at the 1.00 baseline

#### Execution objective
`bun test` (and the CI engine job) runs every fixture through the full pipeline
with no network and a stable scorecard.

#### Definition of done
- [ ] Replay harness + `eval` report + CI gate landed; deterministic, key-free
- [ ] PR title: `feat(engine): offline replay eval harness + CI gate`

---

### T-5.4 — Dart symbol extraction (tree-sitter-dart)

**Status:** Not started
**Owner:** Codex

#### Goal
Parse `.dart` files with a real grammar so symbols (classes, functions, methods)
and top-level public declarations are extracted instead of the class-only regex
fallback.

#### Why
0% parse-coverage on Dart is the primary root cause. `tree-sitter-wasms` already
ships `out/tree-sitter-dart.wasm`, so this is wiring + a node-type collector.

#### Prerequisites
T-5.1 (fixture), T-5.2 (parse-coverage metric to prove it).

#### Files
- `engine/src/models.ts` (add `"dart"` to `LanguageKind`; `.dart` ->
  `dart` in `languageKindForPath`)
- `engine/src/analyze/symbolExtractor.ts` (import `tree-sitter-dart.wasm`; add to
  `GRAMMAR_WASM`/`GRAMMARS`/`grammarFor`; add a `collectDart` node-type collector;
  route `dart` in the `extract` switch)
- `engine/test/symbolExtractor.test.ts` (extend)

#### Execution steps
1. Embed the Dart wasm with `with { type: "file" }` (matching the existing
   grammars so the compiled binary stays node_modules-free).
2. Write `collectDart`: map Dart node types (`class_definition`,
   `function_signature`/`method_signature`, `function_body`-bearing decls, top-level
   functions) to `Symbol`s; treat non-underscore-prefixed top-level declarations as
   exports (Dart's privacy convention).
3. Confirm the offline smoke path still runs without `node_modules` (CI
   `engine-binary` job parity).

#### MCP touchpoints
None.

#### Tests required
- [ ] `symbolExtractor.test.ts > extracts Dart classes, methods, and functions`
- [ ] `symbolExtractor.test.ts > treats public top-level decls as exports`
- [ ] `symbolExtractor.test.ts > underscore-prefixed members are not exported`

#### Execution objective
`flutter-app` parse-coverage jumps from ~0% to near-100% of `.dart` files with
real functions/methods/exports.

#### Definition of done
- [ ] Dart parsed by tree-sitter; symbols + exports extracted and tested
- [ ] Binary smoke test (no node_modules) still passes
- [ ] PR title: `feat(engine): Dart symbol extraction (tree-sitter)`

---

### T-5.5 — Dart import resolution

**Status:** Not started
**Owner:** Codex

#### Goal
Resolve Dart imports to in-repo files: handle the `.dart` extension, `package:`
self-references into `lib/`, and bare/`lib`-relative specifiers — so the code
graph has real edges instead of ~5/12.

#### Why
Sparse edges starve expansion closures and depress cohesion. `main.dart`'s
intra-repo imports currently both fail. This is hypothesis (c).

#### Prerequisites
T-5.4.

#### Files
- `engine/src/analyze/importResolver.ts` (add `.dart` to `extensions`; resolve
  `package:<pkgName>/x.dart` to `lib/x.dart` when `<pkgName>` matches the
  package name from `pubspec.yaml`; resolve bare `lib`-relative specifiers)
- `engine/src/analyze/symbolExtractor.ts` (Dart import collection: capture
  `package:`, `dart:`, and relative specifiers with correct `resolvedTarget`)
- `engine/test/codeGraph.test.ts` (extend)

#### Execution steps
1. Add `.dart` (and prepare `.kt`/`.java` for T-5.7) to the resolver extensions.
2. Pass the package name (from the manifest) so `package:self/...` maps into
   `lib/`; leave third-party `package:` specifiers as external deps.
3. Verify `main.dart` now links to `screens/`/`services/` and the Auth closure
   pulls service + model + client.

#### MCP touchpoints
None.

#### Tests required
- [ ] `codeGraph.test.ts > resolves Dart relative and package-self imports`
- [ ] `codeGraph.test.ts > third-party package: imports stay external`
- [ ] `codeGraph.test.ts > flutter-app main.dart links to its screens/services`

#### Execution objective
`flutter-app` edge count rises and the Auth/User capability closures contain
their real collaborators.

#### Definition of done
- [ ] Dart imports resolve to in-repo files; external deps preserved
- [ ] PR title: `feat(engine): Dart import resolution`

---

### T-5.6 — pubspec.yaml + Gradle manifests + Dart/mobile lexicon

**Status:** Not started
**Owner:** Codex

#### Goal
Parse `pubspec.yaml` and Gradle manifests so a Flutter/Android repo's
dependencies are recognized, and add Dart/mobile capability-lexicon entries so
imports map to capability hints (the surface the gates look for).

#### Why
`pubspec.yaml`/Gradle are absent from `MANIFEST_BASENAMES`, so `firebase_auth`,
`stripe`, `http` are never recognized -> zero capability hints (hypothesis (d)).

#### Prerequisites
T-5.4.

#### Files
- `engine/src/analyze/dependencyManifest.ts` (add `pubspecYaml` + `gradle` kinds
  and parsers; `dependencies:` block of pubspec, `implementation '...'` in Gradle)
- `engine/src/decompose/pipeline.ts` and `engine/src/ingest/contextBuilder.ts`
  (add `pubspec.yaml`, `build.gradle`, `build.gradle.kts` to `MANIFEST_BASENAMES`)
- `engine/src/analyze/capabilityLexicon.ts` (add `firebase_auth`->auth,
  `stripe_*`/`flutter_stripe`->payments, `http`/`dio`->network, etc.)
- `engine/test/capabilityFingerprint.test.ts` (extend)

#### Execution steps
1. Parse pubspec `dependencies`/`dev_dependencies` and Gradle dependency
   declarations into `DependencyManifest.dependencies`.
2. Register the manifest basenames in both manifest-collection sites.
3. Add mobile/Dart lexicon entries so imported deps produce capability hints.

#### MCP touchpoints
None.

#### Tests required
- [ ] `capabilityFingerprint.test.ts > parses pubspec.yaml dependencies`
- [ ] `capabilityFingerprint.test.ts > parses Gradle dependencies`
- [ ] `capabilityFingerprint.test.ts > maps firebase_auth/stripe to hints`

#### Execution objective
`flutter-app` fingerprints carry `importedDependencies` + capability hints, and
the repo map shows `hints:` lines for the first time.

#### Definition of done
- [ ] pubspec + Gradle parsed; mobile lexicon hints produced
- [ ] PR title: `feat(engine): pubspec + Gradle manifests and mobile lexicon`

---

### T-5.7 — Kotlin + Java coverage

**Status:** Not started
**Owner:** Codex

#### Goal
Extend symbol extraction and import resolution to Kotlin and Java using the same
per-language collector pattern, so mixed Android/JVM repos parse.

#### Why
A Flutter repo's `android/` half and JVM monorepos are Kotlin/Java; both are
currently `"unknown"`. Grammars ship in `tree-sitter-wasms`.

#### Prerequisites
T-5.4, T-5.5.

#### Files
- `engine/src/models.ts` (add `"kotlin"`, `"java"`; `.kt`/`.java` mapping)
- `engine/src/analyze/symbolExtractor.ts` (load `tree-sitter-kotlin.wasm`,
  `tree-sitter-java.wasm`; add `collectKotlin`/`collectJava`; package-statement +
  import handling)
- `engine/src/analyze/importResolver.ts` (`.kt`/`.java`; package/path mapping)
- `engine/test/symbolExtractor.test.ts`, `engine/test/codeGraph.test.ts` (extend)

#### Execution steps
1. Wire both grammars and collectors (classes, objects, functions; `public`/
   default visibility -> exports for Java/Kotlin).
2. Resolve Kotlin/Java imports against the source set (package-dir convention).
3. Validate on `kotlin-android` and `java-service` fixtures.

#### MCP touchpoints
None.

#### Tests required
- [ ] `symbolExtractor.test.ts > extracts Kotlin classes/functions`
- [ ] `symbolExtractor.test.ts > extracts Java classes/methods`
- [ ] `codeGraph.test.ts > resolves Kotlin/Java package imports`

#### Execution objective
`kotlin-android` and `java-service` reach non-zero parse-coverage and edge density.

#### Definition of done
- [ ] Kotlin + Java parsed, exported, and import-resolved; fixtures green
- [ ] PR title: `feat(engine): Kotlin and Java coverage`

---

### T-5.8 — Generalize surface / relax non-web gates

**Status:** Not started
**Owner:** Codex

#### Goal
Give mobile/CLI/SDK code a real "surface" (public APIs, app/widget entrypoints,
dependency-hint anchors) or relax the `missingSurface`/`singleFileWithoutOwnedSurface`/
triviality gates for ecosystems with no HTTP routes — without re-admitting trivial
false positives.

#### Why
Even fully parsed, a mobile capability has no Express/Next route, so
`hasSurface` ([`qualityGate.ts`](../../engine/src/decompose/qualityGate.ts)) is
false and good modules are rejected. This is the language bias baked into the
definition itself.

#### Prerequisites
T-5.4 → T-5.7, T-5.2.

#### Files
- `engine/src/analyze/capabilityFingerprint.ts` (treat public exports + capability
  hints + declared entrypoints as surface for non-web stacks)
- `engine/src/decompose/qualityGate.ts` (`hasSurface`/`singleFileOwnsSurface`
  consider exported public API + anchors; keep the reasons enum additive)
- `engine/test/decompose.test.ts` / a focused qualityGate test (extend)

#### Execution steps
1. Define "surface" for non-web ecosystems: a public exported entrypoint
   (Dart/Kotlin/Java public top-level decl) or a capability-hint anchor counts.
2. Relax gates only where it does not weaken the `must_not_be_modules` traps;
   re-run all fixtures including `express-saas`/`next-media`.
3. Confirm the trap files (lone types / utils) still reject.

#### MCP touchpoints
None.

#### Tests required
- [ ] `accepts a Dart capability with a public entrypoint and dep hint`
- [ ] `still rejects a lone types/utils trap (all fixtures, 0 FPs)`
- [ ] `express-saas`/`next-media` remain 1.00/1.00/1.00

#### Execution objective
`flutter-app` produces >= 2 accepted modules at file_recall >= 0.8 with zero trap
false positives.

#### Definition of done
- [ ] Non-web surface recognized; gates relaxed without new trivial FPs
- [ ] PR title: `feat(engine): generalize module surface for non-web stacks`

---

### T-5.9 — Deterministic self-containment verifier

**Status:** Not started
**Owner:** Codex

#### Goal
For each accepted module, deterministically verify it could stand alone: every
internal import target is inside the module (or a declared external dependency),
and every claimed entrypoint (`module.entrypoints[].path/symbol`) exists and is
public/exported. Surface the result in `trace.json` and the scorecard.

#### Why
This is the first signal tied to the **real** definition of a module rather than a
proxy. It is cheap and fully deterministic, so it can gate in CI.

#### Prerequisites
T-5.5 (import resolution), T-5.4/T-5.7 (symbols/exports).

#### Files
- `engine/src/decompose/selfContainment.ts` (NEW; pure function over a module's
  files + the code graph + symbols + declared external deps -> a
  `SelfContainmentResult { imports: pass/fail, entrypoint: pass/fail, danglingImports[] }`)
- `engine/src/trace/trace.ts` (record per-module verification result; additive)
- `engine/src/eval/scorecard.ts` (add self-containment pass-rate to metrics)
- `engine/test/selfContainment.test.ts` (NEW)

#### Execution steps
1. Reuse the resolver + symbol index already computed by the pipeline; for each
   owned file, every resolved internal import must land inside the module's file
   set; unresolved/external imports must be covered by the bundle's declared deps.
2. Verify each entrypoint path is in the module and its symbol is exported.
3. Emit the result into the trace (no decision change yet — observe-only here).

#### MCP touchpoints
`trace.json` gains an additive `verification` block; keep Swift decoding optional.

#### Tests required
- [ ] `selfContainment.test.ts > passes a complete, exported-entrypoint module`
- [ ] `selfContainment.test.ts > fails when an internal import dangles`
- [ ] `selfContainment.test.ts > fails when the claimed entrypoint is not exported`

#### Execution objective
Every accepted module in every fixture carries a self-containment result in its
trace, observe-only.

#### Definition of done
- [ ] Deterministic verifier + trace/scorecard surfacing; no decision change yet
- [ ] PR title: `feat(engine): deterministic self-containment verifier`

---

### T-5.10 — Build verification (eval-only / optional runtime)

**Status:** Not started
**Owner:** Codex

#### Goal
Add a best-effort build/compile check of the extracted bundle in isolation
(language-specific: `tsc --noEmit`, `dart analyze`, `kotlinc`/`javac`) as an
**eval-only and optional-runtime** signal that never fails a run.

#### Why
The strongest test of "stands alone" is "it builds." But real builds are slow,
non-deterministic, and toolchain-dependent, so this must stay out of the
deterministic CI gate and only inform evals / optional local runs.

#### Prerequisites
T-5.9.

#### Files
- `engine/src/extract/buildVerify.ts` (NEW; per-language build runner, sandboxed,
  time-boxed, swallows failures into a structured result)
- `engine/src/eval/scorecard.ts` (record golden-bundle build pass/fail as an
  eval metric)
- `engine/src/index.ts` (opt-in `--verify-build` flag; default off)
- `engine/test/buildVerify.test.ts` (NEW; gate the runner behind an env check so
  CI without toolchains skips, never fails)

#### Execution steps
1. Implement a per-language builder that runs in a temp dir over an extracted
   bundle and returns `{ built: bool, log }`; never throw into the pipeline.
2. Wire it as eval-only (golden fixtures) + an opt-in runtime flag.
3. Ensure CI without the toolchain skips cleanly.

#### MCP touchpoints
None.

#### Tests required
- [ ] `buildVerify.test.ts > reports built=true for a self-contained TS bundle`
- [ ] `buildVerify.test.ts > reports built=false (no throw) for a dangling bundle`
- [ ] `buildVerify.test.ts > skips cleanly when the toolchain is absent`

#### Execution objective
The eval report includes a build-pass column for golden modules; runtime is
unaffected unless `--verify-build` is set.

#### Definition of done
- [ ] Sandboxed, opt-in build verification; never fails a run or the deterministic gate
- [ ] PR title: `feat(engine): optional bundle build verification (eval-first)`

---

### T-5.11 — Gate feedback: wire self-containment into the quality gate

**Status:** Not started
**Owner:** Codex

#### Goal
Make moduleness a tested property: the deterministic self-containment result
**backstops** `confidence`/`cohesion` in the quality gate. A module that fails
self-containment is downgraded (`accepted -> needsApproval`, or rejected); a
strongly self-contained module with a real entrypoint can survive a weak cohesion
score.

#### Why
This closes the feedback loop the architecture lacks today — the system stops
trusting only its proxies and starts checking the thing it claims to enforce.

#### Prerequisites
T-5.9 (observe-only verifier shipped first), T-5.3 (eval gate to prove no regression).

#### Files
- `engine/src/decompose/qualityGate.ts` (consume the self-containment result;
  extend `QualityGateReason` additively, e.g. `failsSelfContainment`)
- `engine/src/decompose/pipeline.ts` (compute verification before gates and pass
  it in)
- `engine/src/models.ts` (extend the reasons enum) + Swift parity note
- `engine/test/decompose.test.ts` (extend)

#### Execution steps
1. Pass the self-containment result into `evaluate`; add `failsSelfContainment`
   as a downgrade/reject reason.
2. Allow a verified-self-contained module with a real entrypoint to pass a
   borderline `cohesion` (the backstop direction), bounded so traps still fail.
3. Re-run the full eval corpus; assert no regression on the floor.

#### MCP touchpoints
`QualityGateReason` is mirrored in the Swift app's trace decoding — extend
additively and update the Swift enum if it is exhaustively matched.

#### Tests required
- [ ] `decompose.test.ts > non-self-contained module is downgraded`
- [ ] `decompose.test.ts > self-contained low-cohesion mobile module survives`
- [ ] `express-saas`/`next-media` unchanged; 0 trap FPs across all fixtures

#### Execution objective
Verification visibly changes >= 1 decision on a fixture, with the regression floor
intact.

#### Definition of done
- [ ] Self-containment backstops the gate; reasons enum extended additively
- [ ] PR title: `feat(engine): verification-fed quality gate`

---

### T-5.12 — Proxy re-examination: tune/replace cohesion/surface/classify

**Status:** Not started
**Owner:** Codex

#### Goal
With self-containment as a near-ground-truth signal on the eval corpus, measure
which proxy (`cohesion`, `hasSurface`, `classify`) least predicts a bundle that
stands alone, then tune or replace it — holding the regression floor.

#### Why
The `0.35`/`0.7`/`0.85` constants and the import-coupling cohesion metric are
unfalsifiable in isolation. Now they can be evaluated against a real signal.

#### Prerequisites
T-5.11, T-5.3.

#### Files
- `engine/src/decompose/qualityGate.ts` (adjust thresholds / metric definitions)
- `engine/src/eval/runEval.ts` (report proxy-vs-verification agreement)
- `engine/test/decompose.test.ts` (extend) + retro notes

#### Execution steps
1. Add an eval that reports, per proxy, agreement with the self-containment /
   build signal across the corpus.
2. Tune or replace the weakest proxy (e.g. cohesion that counts symbol-reference
   edges, or a confidence floor informed by verification), keeping changes minimal.
3. Re-run the corpus; the floor must hold and trap FPs stay zero.

#### MCP touchpoints
None.

#### Tests required
- [ ] `runEval reports proxy-vs-verification agreement per fixture`
- [ ] a tuned threshold improves >= 1 fixture without regressing the floor

#### Execution objective
The eval report quantifies how well each proxy predicts "stands alone," and at
least one proxy is improved with evidence.

#### Definition of done
- [ ] Proxy agreement measured; weakest proxy tuned/replaced with evidence
- [ ] PR title: `refactor(engine): tune module-quality proxies against verification`

---

### T-5.13 — Large-repo repo-map chunking / map-reduce survey

**Status:** Not started
**Owner:** Codex

#### Goal
Stop large repos from truncating below the signal: chunk the repo map and/or
run a map-reduce survey so big projects' capabilities remain visible.

#### Why
The repo map is budget-truncated ([`repoMap.ts`](../../engine/src/ingest/repoMap.ts));
above the budget, capabilities below the cut line are invisible to survey
(hypothesis (e)).

#### Prerequisites
T-5.2 (truncation metric), T-5.1 (`large-repo` fixture).

#### Files
- `engine/src/ingest/repoMap.ts` / `engine/src/ingest/contextBuilder.ts`
  (deterministic chunking by cluster)
- `engine/src/decompose/survey.ts` (map-reduce: survey chunks, merge hypotheses)
- `engine/test/` (chunking determinism + large-repo hypothesis coverage)

#### Execution steps
1. Partition the repo map into deterministic, cluster-aligned chunks under budget.
2. Survey each chunk, then merge/dedupe hypotheses with stable ordering.
3. Prove the `large-repo` fixture surfaces capabilities that single-shot truncation
   dropped, with byte-stable output across runs.

#### MCP touchpoints
None.

#### Tests required
- [ ] `large-repo capabilities survive (no silent truncation)`
- [ ] `chunking + merge is deterministic across runs`

#### Execution objective
The `large-repo` fixture yields its expected capabilities instead of a truncated subset.

#### Definition of done
- [ ] Deterministic chunked/map-reduce survey; large-repo signal preserved
- [ ] PR title: `feat(engine): large-repo map chunking and map-reduce survey`

---

### T-5.14 — Prompt/quality improvements

**Status:** Not started
**Owner:** Codex

#### Goal
Improve the survey/refine prompts only **after** coverage and verification land,
measured by the eval suite (never as a blind tweak).

#### Why
Prompt changes are only trustworthy once parsing/surface are fixed and the evals
can prove a delta.

#### Prerequisites
T-5.8, T-5.11, T-5.3.

#### Files
- `engine/src/decompose/survey.ts`, `engine/src/decompose/refiner.ts` (prompts)
- `engine/test/` + eval report (before/after scorecards)

#### Execution steps
1. Identify a prompt weakness from the eval corpus (e.g. mobile capability naming).
2. Make a minimal prompt change; re-record replay tapes; re-run the eval.
3. Keep only changes that improve a metric without regressing the floor.

#### MCP touchpoints
None.

#### Tests required
- [ ] a prompt change improves >= 1 fixture metric in the eval report
- [ ] the floor and trap FPs are unchanged

#### Execution objective
A measured prompt improvement, justified by before/after scorecards.

#### Definition of done
- [ ] Prompt change landed with eval evidence; floor intact
- [ ] PR title: `feat(engine): measured prompt improvements`

---

### T-5.15 — Phase-5 eval gate + ARCHITECTURE update + retro + roadmap

**Status:** Not started
**Owner:** Codex

#### Goal
Prove the phase: the multi-language fixtures meet their acceptance criteria, every
accepted module passes self-containment, and the Phase 4 floor holds. Update the
architecture doc and write the retro.

#### Why
This is the phase's quality gate and the canonical record of what "multi-language,
verified" decomposition now means.

#### Prerequisites
All of T-5.1 → T-5.14.

#### Files
- `engine/docs/ARCHITECTURE.md` (new language coverage, signal metrics,
  verification stage, updated playbook + trace fields)
- `docs/retros/phase-5.md` (NEW; before/after numbers + a real Flutter capability)
- `docs/roadmap.md` (insert/renumber the phase)
- `CHANGELOG.md` (phase entry)

#### Execution steps
1. Run the full eval over all fixtures; assert acceptance criteria + the floor.
2. Update ARCHITECTURE.md (stages, metrics, verification, trace schema).
3. Write the retro with the committed scorecards and a genuine multi-file Flutter
   module example.

#### MCP touchpoints
Document the additive `trace.json` verification fields in the contract section.

#### Tests required
- [ ] `eval gate: all multi-language fixtures meet acceptance criteria`
- [ ] `eval gate: 100% of accepted modules pass self-containment`
- [ ] `eval gate: express-saas/next-media at baseline; 0 trap FPs`

#### Execution objective
The full suite is green; the architecture doc and retro reflect the new pipeline.

#### Definition of done
- [ ] Acceptance criteria met; floor intact; ARCHITECTURE + retro + roadmap updated
- [ ] PR title: `docs(engine): phase-5 eval gate, architecture, and retro`

---

## Notes on existing code
- This phase is engine-only; the Swift app, MCP store schema, and all views are
  reused unchanged. The only cross-boundary surface is `trace.json`, which is
  extended additively (Swift Runs-tab decoding must stay backward-compatible).
- New languages follow the existing pattern exactly: a wasm grammar embedded with
  `with { type: "file" }`, a `collect<Lang>` node-type collector in
  `symbolExtractor.ts`, resolver extensions, and manifest/lexicon entries.
- Verification reuses the resolver and symbol index the pipeline already computes;
  the deterministic self-containment check is the only verification signal allowed
  to gate CI. The build check is eval-only/optional and never fails a run.








