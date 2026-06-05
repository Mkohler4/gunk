# Plan Phase 5: AI evals + AI system upgrade (gated on whole-repo, multi-language capability)

You are planning Phase 5 of `gunk`. Work in **Plan mode**: investigate, then
produce a written, phased plan with todos. **Do not modify engine/app source in
this task** — writing throwaway repro scripts/fixtures and reading traces is fine.

## Context you must load first
- Read `engine/docs/ARCHITECTURE.md` end to end. It documents the 11 pipeline
  stages, the two LLM passes (verbatim prompts + the post-processing filters that
  silently drop output), the quality-gate rejection reasons, the `trace.json`
  schema, and a symptom→fix playbook. Use its vocabulary.
- Read `docs/adr/0013-ts-decomposition-engine.md` and the engine source under
  `engine/src/` (`decompose/`, `analyze/`, `ingest/`, `llm/`, `trace/`).
- The eval harness is `engine/test/evalGate.test.ts` + `engine/src/eval/scorecard.ts`
  with fixtures in `engine/test/fixtures/`.

## The blocking problem (resolve this BEFORE planning upgrades)
A user dropped an entire **Flutter** repository and the engine produced essentially
nothing (it "only filtered out an Android manifest file"). Suspected root cause:
the system goes blind on languages it can't parse. `languageKindForPath`
(`engine/src/models.ts`) and the loaded tree-sitter grammars only cover **Go,
JS/TS/TSX, Python, Swift**. A Flutter repo is mostly **Dart** (+ Kotlin/Java/Gradle),
all of which become `"unknown"` → regex fallback → near-zero symbols → sparse
graph → empty fingerprints/routes → a signal-free repo map → survey proposes
almost nothing → quality gates reject the rest as trivial.

### Part A — Gating diagnostic (do first; required)
1. Reproduce on a real multi-language repo. Clone or assemble a representative
   Flutter/Dart project (and ideally one Kotlin and one mixed monorepo). Run:
   `cd engine && bun run src/index.ts <repo> --provider <p> --model <m> --db /tmp/p5.db --gunk-home /tmp/p5 --json --trace`
2. Open `/tmp/p5/runs/*/trace.json` and quantify where signal is lost, per the
   ARCHITECTURE playbook. Report concrete numbers:
   - `stages[scan].counts.files` vs files actually in the repo (ignore-rule loss?)
   - % of files that produced symbols/imports (symbols stage) — i.e. how many fell
     to `"unknown"` / regex fallback
   - `stages[graph].counts.edges` (edge density) and `stages[repoMap].counts.chars`
   - `hypotheses` count and `llmCalls[stage=survey].responseJson` vs surviving
     `hypotheses` (path-filter loss)
   - `gateEvaluations[].reasons` histogram (how many `missingSurface`, `lowCohesion`,
     `typeOnly`, etc.)
3. Confirm or refute each hypothesis with evidence: (a) language coverage,
   (b) ignore rules excluding real source, (c) import resolution failing for the
   ecosystem, (d) JS/Python-centric route/lexicon fingerprints producing no surface,
   (e) repo-map truncation on large repos, (f) survey path-filter dropping
   hypotheses.
4. **Decision gate:** state explicitly whether whole-repo, multi-language
   processing is fundamentally working (just needs coverage) or structurally
   broken. Everything in Part B is contingent on this finding.

## Part B — Phase 5 plan (two workstreams; sequence them by Part A findings)

### Workstream 1 — AI evals (measure before/while upgrading)
Design an eval system that would have caught this failure:
- Expand the fixture corpus to **whole-repo, multi-language** cases: Flutter/Dart,
  Kotlin/Android, Java, a mixed monorepo, and a large repo (for truncation). Keep
  the existing golden + negative-trap fixtures.
- Add **per-stage signal metrics** to the scorecard, not just the final
  precision/recall: parse-coverage % (files with real symbols), graph edge density,
  survey hypothesis count, expansion closure sizes, gate-rejection histogram. A run
  that produces near-zero signal must fail loudly.
- Add **offline/replay evals**: record real `trace.json` LLM calls and replay them
  so the eval suite runs deterministically in CI without live API keys (extend the
  canned-client pattern already in `evalGate.test.ts`).
- Decide whether to add an `eval` CLI/report and how it gates CI (extend the
  existing `engine` job). Hold the current baseline as a floor.

### Workstream 2 — AI system upgrades (driven by Part A)
Likely scope (validate against findings; don't assume):
- **Language coverage:** add Dart (and Kotlin/Java/etc.) symbol extraction.
  `tree-sitter-wasms` already ships many grammars (`out/tree-sitter-dart.wasm`,
  `-kotlin`, `-java`, …) — assess the work: extend `languageKindForPath`, the
  grammar map + `Parser.init`, and the per-language node-type collectors in
  `symbolExtractor.ts`, plus import resolution for each ecosystem.
- **Generalize fingerprints/routes/lexicon** beyond JS/Python so non-web stacks
  (mobile/CLI/SDK) yield a real "surface", or relax the `missingSurface`/triviality
  gates for ecosystems without HTTP routes.
- **Scale to large repos:** repo-map chunking / map-reduce survey so big projects
  don't truncate below the signal.
- **Prompt/quality improvements** only after coverage is fixed, measured by evals.

## Constraints & deliverables
- Keep the engine **UI-agnostic and cross-platform**; preserve the NDJSON contract
  and `trace.json` schema (extend, don't break). Maintain MCP↔Swift↔engine schema
  parity.
- Determinism (`temperature: 0`, stable sorting) and the eval gate must hold;
  no regressions on existing fixtures.
- Each phase must be **independently shippable**.
- Update `engine/docs/ARCHITECTURE.md` and add an ADR (ADR-0014) for the Phase 5
  direction.

## Output
Produce a Phase 5 plan document (same shape as prior plans: frontmatter `name`,
`overview`, ordered `todos` with ids/status, then sections) containing: the Part A
diagnostic findings with numbers, the go/no-go decision, the two workstreams broken
into phased, acceptance-gated todos, risks, and explicit acceptance criteria
(e.g., "parse-coverage ≥ X% and ≥ N accepted modules on the Flutter fixture").
Do not write implementation code in this task.