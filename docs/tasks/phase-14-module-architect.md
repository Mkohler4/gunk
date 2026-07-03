# Phase 14 — Module Architect (engine v2)

This phase turns the [Module Architect design](../design/module-architect.md)
([ADR-0018](../adr/0018-module-architect.md)) from a vision into running code,
**one small PR at a time.** It is an **engine track** — it changes
`gunk-engine`'s decomposition pipeline, not the macOS UI — so it can proceed in
parallel with the UI redesign arc (Phases 8–13).

The whole phase exists to fix two concrete, reproducible failures (see the
design doc's intro):

1. **gunk false negative** — gunk finds **no** modules in its own (library/tool)
   repo, because the survey rubric and the "surface" proxy are biased toward
   SaaS-style app features and reject "utilities."
2. **ThemeProvider false positive** — a high-fan-in cross-cutting file is
   surfaced as a module purely because everything imports it.

The architectural principle this phase encodes (design doc §21, Appendix A.2):

> **Graphs discover dependency pressure. AI discovers product boundaries.
> Verification proves extractability.** The graph stays valuable; it stops being
> the architect.

Anchors: [design/module-architect.md](../design/module-architect.md) (the spec;
section numbers below reference it), [ADR-0018](../adr/0018-module-architect.md)
(the decision), and the current engine reference
[engine/docs/ARCHITECTURE.md](../../engine/docs/ARCHITECTURE.md). This phase
supersedes the **pipeline shape** of
[ADR-0012](../adr/0012-capability-centric-decomposition.md) incrementally, but
keeps ADR-0011's `gunk.yml`/secret/provenance/license rules unchanged.

---

## How to be hands-on with this phase (read this first)

The point of this doc is to get **Mark** back in the loop with a tight,
satisfying feedback cycle. The ritual for every task:

1. **Watch it fail.** `cd engine && bun run watch`, then process a repo in the
   app (or run the CLI). See the funnel live: stage transitions + the exact LLM
   prompts/responses.
2. **Read the post-mortem.** `bun run trace` digests the newest run into a
   one-screen funnel (`files → edges → hypotheses → modules → accepted`) and
   points at the failing stage.
3. **Make one small change** (one task = one PR).
4. **Prove it.** `bun test` (unit) and `bun run eval` (the offline gate with
   recorded LLM tapes) must stay green. Each task names the test that flips.
5. **Keep docs honest.** Tick the box here, add a `CHANGELOG.md` line, and
   update the matching design-doc section if behavior diverged.

Two gotchas you'll hit (both from `engine/docs/ARCHITECTURE.md`):

- **Prompt changes break replay tapes.** The eval gate replays
  `engine/test/fixtures/*/recorded-trace.json`. Any task that edits a survey or
  refine prompt must **re-record** the affected fixtures against a live LLM
  (`GUNK_API_KEY=… bun run src/index.ts <fixture> --provider openai --model … --trace`)
  and update the tape, or the gate throws "Replay tape stale."
- **New fixtures need a tape.** A fixture only runs in eval once it has a
  `recorded-trace.json`. Budget a one-time live run to record it.

Sequencing philosophy: **smallest, safest, highest-leverage first.** T-14.0 and
T-14.1 are pure grounding (build intuition + a red test). T-14.2 is the single
smallest change that fixes a real failure. Recall work (T-14.4–T-14.6) fixes the
gunk blind spot. Scoring/gate (T-14.7–T-14.8) make decisions principled. The
heavy creation work (T-14.9–T-14.10) is sketched, not fully specified — it will
be detailed once the foundation lands.

---

## Task ladder

### T-14.0 — Baseline: capture today's behavior on three repo kinds

**Status:** Not started
**Owner:** Mark

#### Goal
A short written baseline of how today's engine behaves on a SaaS app, a library,
and gunk itself — so every later task has a before/after to point at.

#### Why
You cannot feel progress without a measuring stick. This task is pure
intuition-building and produces the evidence that motivates the phase
(design doc intro).

#### Prerequisites
None.

#### Files
- `docs/tasks/phase-14-baseline.md` (new) — the captured funnels + notes.

#### Execution steps
1. Pick three local repos: one SaaS/app, one library/SDK, and `gunk` itself.
2. For each: `cd engine && GUNK_API_KEY=… bun run src/index.ts <path> --provider openai --model gpt-4.1-mini --db /tmp/p14.db --gunk-home /tmp/p14 --json --trace`.
3. For each: `bun run trace --gunk-home /tmp/p14` and paste the funnel + summary into the baseline doc.
4. Note, per repo: where the funnel collapses (survey? refine? gates?), and which real capabilities were missed or wrongly surfaced.

#### MCP touchpoints
None.

#### Tests required
None (documentation task). CI must still be green.

#### Execution objective
Running the three traces reproduces, in numbers, the gunk false-negative and the
app's false positives.

#### Definition of done
- [ ] `phase-14-baseline.md` exists with three funnels + a one-paragraph reading each.
  Goal: Summarize the three funnels and their readings from phase-14-baseline.md for quick reference and understanding.
  Files:
    - docs/tasks/phase-14-baseline.md
  Steps:
    - [ ] Identify the three funnels described in docs/tasks/phase-14-baseline.md. → docs/tasks/phase-14-baseline.md
    - [ ] Read the one-paragraph reading associated with each funnel in the file. → docs/tasks/phase-14-baseline.md
    - [ ] Write a concise 1-2 sentence summary for each funnel and its reading. → docs/tasks/phase-14-baseline.md
    - [ ] Add the three summaries together at the top or bottom of docs/tasks/phase-14-baseline.md, ensuring they are clearly labeled as summaries. → docs/tasks/phase-14-baseline.md
    - [ ] Save the updated docs/tasks/phase-14-baseline.md file. → docs/tasks/phase-14-baseline.md
  Done when:
    - [ ] docs/tasks/phase-14-baseline.md contains a clear summary of all three funnels and their readings at the top or bottom of the file.
    - [ ] Each funnel and its reading are represented by a concise 1-2 sentence summary.
    - [ ] No original content is lost or overwritten; summaries are additive.
    - [ ] The file is saved with the new summaries present.
- [x] CHANGELOG line under an "Unreleased / engine" heading.

---

### T-14.1 — Fixtures that define "done": library-positive + ThemeProvider-negative

**Status:** Not started
**Owner:** Mark

#### Goal
Two new eval fixtures that encode the target behavior: a small library/tooling
repo that **should** yield modules, and an app with a `ThemeProvider` that should
**not** become a standalone module.

#### Why
Turns the phase goals into red tests. This is the foundation every later task is
measured against (design doc §15, Appendix A.6/A.7).

#### Prerequisites
T-14.0.

#### Files
- `engine/test/fixtures/library-tooling/**` (new) — a tiny synthetic library: a
  scanner, a manifest parser, a redactor, sharing a small `types.ts` kernel.
- `engine/test/fixtures/app-themeprovider/**` (new) — a small app where a
  `ThemeProvider` is imported by many unrelated features.
- `engine/test/fixtures/library-tooling/expected.json`,
  `engine/test/fixtures/app-themeprovider/expected.json` (new) — golden modules.
- `engine/test/fixtures/*/recorded-trace.json` (new) — recorded LLM tapes.
- `engine/src/eval/runEval.ts`, `engine/test/evalGate.test.ts` (modify) — register
  fixtures; mark them **expected-to-improve** (quarantined floor of 0) until the
  fixing tasks land, so the gate documents the gap without failing CI.

#### Execution steps
1. Author the two fixture trees (mirror the style of existing fixtures).
2. Write `expected.json`: library fixture expects ≥3 modules (scanner, manifest
   parser, redactor); app fixture expects the ThemeProvider **absent** from
   accepted modules (a negative assertion).
3. Record tapes via a one-time live run per fixture (`--trace`), copy each
   `trace.json` to the fixture as `recorded-trace.json`.
4. Register both in the eval harness with a quarantined floor; add a comment
   pointing at the tasks that will raise the floor (T-14.2, T-14.6).

#### MCP touchpoints
None.

#### Tests required
- [ ] `evalGate.test.ts` runs both new fixtures (quarantined) without erroring.
- [ ] A focused test asserts today's pipeline **fails** the library fixture
      (documents the gap) and a separate one asserts the ThemeProvider currently
      leaks (so T-14.2 has something to flip).

#### Execution objective
`bun run eval` lists both fixtures; the library one shows 0 modules and the app
one shows a leaked ThemeProvider module — the two reds this phase will turn
green.

#### Definition of done
- [ ] Both fixtures + `expected.json` + tapes committed.
- [ ] Eval registers them quarantined; CI green.
- [ ] CHANGELOG + a note in the design doc §19/§20 linking these fixtures as the
      acceptance evidence.

---

### T-14.2 — High fan-in is suspicious, not attractive (seed suppression)

**Status:** Not started
**Owner:** Mark

#### Goal
A high-fan-in file (imported by many unrelated files) is presented to the survey
LLM as **shared infrastructure that should not be a capability seed**, instead of
as neutral/positive `bridge_files` evidence, so a cross-cutting `ThemeProvider`
stops being proposed as a standalone module.

#### Why
Smallest change that fixes a real failure (design doc §8, Appendix A.5).

#### Ground truth — how seeding actually works today (read before coding)
There is **no code gate that picks seed files** — the survey LLM picks
`seedFiles` from the repo-map *text*. So this task changes how high-fan-in files
are **presented** and the **prompt**, not a seeding `if`. The current call path:

1. `engine/src/ingest/contextBuilder.ts:131-156` — builds the repo map. Line ~133
   computes `bridgeFiles = new Set(clustering.highFanInBridgeFiles(2).map(...))`
   and line ~156 attaches the high-fan-in files to each cluster's `bridgeFiles`.
2. `engine/src/ingest/repoMap.ts:72-73` — renders them verbatim as a neutral
   `  bridge_files: <a, b, c>` line in the map the LLM reads. **Nothing tells the
   model these are *bad* seeds.**
3. `engine/src/decompose/survey.ts:84` — the rubric explicitly lists
   `"strongly connected graph cluster"` as a **valid anchor**, which a
   high-fan-in hub trivially satisfies — actively inviting the false positive.
4. `engine/src/decompose/expander.ts:28` — `sharedFanInThreshold: 3` already
   demotes a file reached by ≥3 capabilities to a `sharedDependencyFile`. This is
   the *post-seed* safety net and likely needs **no change**; the fix is upstream
   at presentation + prompt.

So the lever is steps 2–3, not the expander.

#### Prerequisites
T-14.1.

#### Files
- `engine/src/analyze/graphClustering.ts` (modify) — add
  `classifyHighFanInFile(node, graph): HighFanInRole` (`possible_entrypoint` |
  `possible_platform_service` | `shared_infrastructure` |
  `suspicious_cross_cutting_file`) per design doc §8. Keep `highFanInBridgeFiles`
  but expose the role alongside each node.
- `engine/src/ingest/repoMap.ts` (modify) — relabel the rendered line from
  `bridge_files:` to something the model reads as a warning, e.g.
  `shared_infra_do_not_seed:`, and (optional) drop entrypoint-role files from it.
- `engine/src/ingest/contextBuilder.ts` (modify) — pass the role through so only
  non-`possible_entrypoint` high-fan-in files are tagged as do-not-seed.
- `engine/src/decompose/survey.ts` (modify, lines ~79-85) — (a) remove or qualify
  `"strongly connected graph cluster"` as an anchor so a bare hub is not a valid
  anchor; (b) add a rubric line: *"Files listed under shared_infra_do_not_seed are
  cross-cutting dependencies; never propose one as a capability seed — only as a
  shared dependency."* **This edits the prompt → triggers tape re-record (below).**
- `engine/test/graphClustering.test.ts` (modify), `engine/test/repoMap.test.ts`
  (modify).
- All `engine/test/fixtures/*/recorded-trace.json` whose survey prompt/map text
  changed (re-record — **required**).

#### Execution steps
1. Add `classifyHighFanInFile` to `GraphClustering` using `inboundEdges` + the
   §8 heuristic (route/CLI entrypoint → `possible_entrypoint`; domain-API +
   tests → `possible_platform_service`; `Provider`/`Context`/`Theme`/`Config` or
   `shared`/`common` path → `shared_infrastructure`; else
   `suspicious_cross_cutting_file`).
2. Thread the role into `contextBuilder.ts` so the repo map separates
   do-not-seed files from entrypoints.
3. Rename/relabel the `bridge_files:` rendering in `repoMap.ts` accordingly.
4. Edit the survey prompt in `survey.ts` (anchor list + new rubric line).
5. Re-record every affected fixture tape:
   `GUNK_API_KEY=… bun run src/index.ts test/fixtures/<name> --provider openai --model gpt-4.1-mini --gunk-home /tmp/rec --trace`
   then copy `/tmp/rec/runs/<id>/trace.json` → `test/fixtures/<name>/recorded-trace.json`.
6. `bun test && bun run eval`.

#### MCP touchpoints
None.

#### Tests required
- [ ] Unit (`graphClustering.test.ts`): a `ThemeProvider.tsx` node with inbound
      degree ≥ 5 and no route → `classifyHighFanInFile` returns
      `shared_infrastructure`.
- [ ] Unit (`graphClustering.test.ts`): a node that is a route/CLI entrypoint with
      high inbound degree → `possible_entrypoint`.
- [ ] Unit (`repoMap.test.ts`): a high-fan-in non-entrypoint file renders under
      the `shared_infra_do_not_seed:` line, not as a neutral `bridge_files:` anchor.
- [ ] Eval (`evalGate.test.ts`): the `app-themeprovider` fixture (from T-14.1)
      produces **0** accepted/needsApproval modules whose `ownedFiles` contain the
      ThemeProvider file; flip its floor from quarantined to enforced.
- [ ] Eval: existing SaaS/multi-language fixtures hold their current module
      floors (no regression) after tape re-record.

#### Execution objective
`bun run trace` on the app fixture shows the ThemeProvider file under
shared-infrastructure, and it appears (if at all) only as a `sharedDependency` of
another module — never as an accepted module's owned file.

#### Definition of done
- [ ] All tests above pass; `app-themeprovider` floor enforced; no SaaS-fixture
      regression.
- [ ] Affected `recorded-trace.json` tapes re-recorded and committed.
- [ ] CHANGELOG entry; design doc §8/§20 annotated "implemented in T-14.2".

---

### T-14.3 — Dependency resolution classification (advisory)

**Status:** Not started
**Owner:** Mark

#### Goal
Replace the binary "self-contained or reject" verdict with a per-dependency
`DependencyResolution` classification, recorded in the trace (advisory — the gate
stays lenient this task).

#### Why
A good capability may depend on shared types/store/logging; that should inform a
boundary plan, not auto-kill it (design doc §9, Appendix A.4).

#### Prerequisites
T-14.2.

#### Files
- `engine/src/decompose/selfContainment.ts` (modify) — emit a
  `DependencyResolution[]` (own | copy_into_module | extract_shared_kernel |
  generate_local_type | replace_with_interface | adapter_port | external_package
  | reject) per dangling import, instead of only pass/fail.
- `engine/src/models.ts` (modify) — the `DependencyResolution` type.
- `engine/src/trace/trace.ts` (modify) — record resolutions under
  `verification.selfContainment[]`.
- `engine/test/selfContainment.test.ts` (modify).

#### Execution steps
1. Add the discriminated-union type and a classifier that uses graph + manifest
   evidence to label each dangling import.
2. Record resolutions in the trace; do **not** yet change accept/reject (keep the
   current gate so this PR is safe).
3. Surface the labels in `bun run trace` output.

#### MCP touchpoints
None.

#### Tests required
- [ ] Unit: `symbolExtractor`-style file importing a broad `models.ts` yields
      `generate_local_type` for the few used symbols, not `reject`.
- [ ] Unit: a store import yields `adapter_port`.

#### Execution objective
The trace now shows a resolution strategy per dangling import; behavior is
otherwise unchanged.

#### Definition of done
- [ ] Tests pass; trace shows resolutions; CHANGELOG; design doc §9 updated.

---

### T-14.4 — Repo-kind classifier

**Status:** Not started
**Owner:** Mark

#### Goal
A deterministic + LLM-assisted classifier that labels a repo
(`saas_app` | `frontend_app` | `backend_service` | `cli_tool` | `library` |
`sdk` | `compiler_or_analyzer` | `monorepo` | `infra_tooling` | `hybrid`) before
discovery.

#### Why
The rubric must change *before* discovery; this is the lever that fixes the gunk
blind spot (design doc §4, Appendix A.7).

#### Prerequisites
T-14.1.

#### Files
- `engine/src/analyze/repoKind.ts` (new) — classifier from evidence (manifests,
  entrypoints, routes, dependency mix, naming).
- `engine/src/decompose/pipeline.ts` (modify) — run it after fingerprints; pass
  the label into survey; record in trace + as a new stage count.
- `engine/test/repoKind.test.ts` (new).

#### Execution steps
1. Implement evidence-based scoring with an LLM tiebreak for ambiguous repos.
2. Thread `repoKind` into the survey context and the trace.

#### MCP touchpoints
None.

#### Tests required
- [ ] Unit: gunk-like evidence → `cli_tool`/`compiler_or_analyzer`/`library`.
- [ ] Unit: an Express+Stripe fixture → `saas_app`/`backend_service`.

#### Execution objective
Every run reports a repo kind in the trace; gunk classifies as a tool/library.

#### Definition of done
- [ ] Tests pass; trace shows repo kind; CHANGELOG; design doc §4 updated.

---

### T-14.5 — Capability ontology registry (soft priors)

**Status:** Not started
**Owner:** Mark

#### Goal
A configurable registry of `CapabilityShape`s that contributes **weighted
evidence** to candidates — never an allow-list.

#### Why
The recall fix for non-SaaS repos, with the hard guardrail from design doc §12:
matching a shape adds evidence; not matching never rejects.

#### Prerequisites
T-14.4.

#### Files
- `engine/src/analyze/capabilityOntology.ts` (new) — `CapabilityShape`,
  `CapabilityOntology`, the tooling priors, and a `scoreOntologyPrior()` /
  `matchShapes()` that returns `{ type: "ontology_match", strength, matchedShape }`
  evidence.
- `engine/src/analyze/capabilityLexicon.ts` (review) — keep dependency→label
  hints; the ontology is the higher-level layer above it.
- `engine/test/capabilityOntology.test.ts` (new).

#### Execution steps
1. Encode the shapes from design doc §12 as data (id, labels, repoKinds,
   positive/negative signals, common APIs, boundary recipe, examples).
2. Expose matching as **evidence with strength**, never a boolean gate.
3. Include the three-level `CapabilityRecognition` (known_shape / known_family /
   novel_shape) so unmatched-but-cohesive candidates survive.

#### MCP touchpoints
None.

#### Tests required
- [ ] Unit: a `extractSymbols`-named file matches `symbol_extractor` with
      positive strength.
- [ ] Unit: a capability matching **no** shape still scores > 0 from other
      evidence (proves it is not a gate).

#### Execution objective
Candidates carry ontology evidence; nothing is rejected for failing to match a
known noun.

#### Definition of done
- [ ] Tests pass (incl. the "no-match still valid" test); CHANGELOG; design doc
      §12 marked implemented.

---

### T-14.6 — Repo-kind- and ontology-aware survey/refine prompts

**Status:** Not started
**Owner:** Mark

#### Goal
Rewrite the survey and refine prompts to be repo-kind-specific, present the
ontology as **examples, not constraints**, and allow refine to *propose a
boundary transformation* rather than only accept/reject.

#### Why
The prompt is where the SaaS bias actually lives (design doc §23). This is the
task that should make the `library-tooling` fixture produce modules.

#### Prerequisites
T-14.4, T-14.5.

#### Files
- `engine/src/decompose/survey.ts` (modify) — repo-kind rubric + "examples, not
  exhaustive" wording + semantic verb/object priors (§11/§12/§23).
- `engine/src/decompose/refiner.ts` (modify) — third option: reject / accept /
  **propose boundary transformation**.
- `engine/test/fixtures/*/recorded-trace.json` (re-record — **required**, prompts
  changed).
- `engine/test/decompose.test.ts` (modify).

#### Execution steps
1. Update the two system prompts per design doc §23 (keep them deterministic,
   `temperature: 0`).
2. Re-record **all** fixture tapes (this is the "prompt changes break replay"
   gotcha) and verify the eval gate.
3. Raise the `library-tooling` fixture floor to its `expected.json` target.

#### MCP touchpoints
None.

#### Tests required
- [ ] Unit: survey prompt contains the "examples, not constraints" clause and the
      repo-kind rubric.
- [ ] Eval: `library-tooling` fixture meets its module floor (scanner / manifest
      parser / redactor accepted).
- [ ] Eval: existing SaaS fixtures (express-saas, java-service, …) hold their
      baselines — no regression.

#### Execution objective
Running gunk-like code now yields tooling-capability candidates instead of
nothing.

#### Definition of done
- [ ] All fixtures pass (new floor + no regression); tapes re-recorded; CHANGELOG;
      design doc §23 updated.

---

### T-14.7 — Dual scoring: capability value vs extractability

**Status:** Not started
**Owner:** Mark

#### Goal
Score candidates on independent axes (`capabilityValue`, `extractability`,
`cohesion`, `publicApiClarity`, `couplingRisk`, `testability`, `reusePotential`,
`falsePositiveRisk`) instead of conflating "easy to extract" with "real
capability."

#### Why
Prevents easy-but-trivial files from beating valuable-but-coupled modules
(design doc §16).

#### Prerequisites
T-14.5.

#### Files
- `engine/src/decompose/moduleScore.ts` (new) — the score vector + computation.
- `engine/src/decompose/qualityGate.ts` (modify) — consume the scores.
- `engine/test/moduleScore.test.ts` (new).

#### Tests required
- [ ] Unit: `secretRedactor`-like → high value + high extractability.
- [ ] Unit: `symbolExtractor`-like → very-high value + medium extractability.
- [ ] Unit: cross-cutting provider → low value + high falsePositiveRisk.

#### Definition of done
- [ ] Tests pass; scores recorded in trace; CHANGELOG; design doc §16 updated.

---

### T-14.8 — "Can be productized" gate

**Status:** Not started
**Owner:** Mark

#### Goal
Replace the binary reject reasons (`no surface → reject`, `dangling import →
reject`, `utility path → reject`, `high fan-in → nominate`) with an architectural
gate: clear purpose → stable contract → coherent behavior → boundary
synthesizable → (later) verification proof.

#### Why
The gate must judge productizability, not pre-existing cleanliness
(design doc §17, Appendix A.5).

#### Prerequisites
T-14.3, T-14.7.

#### Files
- `engine/src/decompose/qualityGate.ts` (modify) — new decision flow using
  scores (T-14.7) + dependency resolutions (T-14.3).
- `engine/test/decompose.test.ts` (modify).

#### Tests required
- [ ] Unit: a coupled-but-valuable capability with a synthesizable boundary →
      `accepted`/`needsApproval`, not `rejected`.
- [ ] Unit: a random folder with no clear purpose → `rejected`.
- [ ] Eval: all fixtures (SaaS + new tooling/app) hold.

#### Definition of done
- [ ] Tests pass; no fixture regression; CHANGELOG; design doc §17 updated.

---

### T-14.9 — Boundary synthesis service (semantic slicing) — *sketch, multi-PR*

**Status:** Not started (to be detailed after T-14.8)
**Owner:** Mark

#### Goal
Replace BFS-closure boundaries with a nucleus-first solver that classifies every
dependency into a resolution and emits a `BoundaryPlan` (design doc §7/§10,
Appendix A.4).

#### Notes
Larger than one PR — split into: (a) capability nucleus extraction, (b) the
weighted boundary solver, (c) shared-kernel/type extraction, (d) port/adapter
generation. Detail these into T-14.9.1…T-14.9.4 once T-14.8 merges. The advisory
classification from T-14.3 becomes load-bearing here.

---

### T-14.10 — Materialization + verification loop — *sketch, multi-PR*

**Status:** Not started (to be detailed after T-14.9)
**Owner:** Mark

#### Goal
Generate real module packages (façade, README, tests, migration patch) and prove
them with a scratch compile/test/behavioral-comparison loop, feeding failures
back into boundary synthesis (design doc §14/§15, Appendix A.1 feedback edges).

#### Notes
Build on the existing best-effort `engine/src/extract/buildVerify.ts`, but make
verification gate-enforcing for `accepted`. Split into: (a) scratch workspace +
typecheck, (b) generated tests, (c) behavioral comparison, (d) the boundary
iteration loop. Detail after T-14.9.

---

## Phase exit criteria

This phase is "done enough to demo" when:

- [ ] gunk run on its own repo produces a ranked set of **tooling/library**
      module cards (Repo Scanner, Manifest Parser, Secret Redactor, …) — the
      `library-tooling` fixture floor is enforced (T-14.6).
- [ ] A `ThemeProvider`-style cross-cutting file is never a standalone module —
      the `app-themeprovider` fixture floor is enforced (T-14.2).
- [ ] No regression on the existing SaaS/multi-language fixtures.
- [ ] The trace shows repo kind, ontology evidence, dependency resolutions, and
      the score vector — the engine "shows its work" for the new pipeline.

Materialization + verification (T-14.9–T-14.10) may land in a follow-up phase;
the exit criteria above are achievable with T-14.0 through T-14.8.
