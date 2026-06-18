# gunk-engine: how it works (and how to debug the AI)

This document is the map for understanding **exactly** what the engine does on
every run, where each decision is made, and which artifact to open when the AI
output is wrong. It is written for debugging: each stage lists its inputs,
outputs, the failure modes that make capabilities disappear or look wrong, and
the precise trace field to inspect.

If you only read one section, read [Debugging playbook](#debugging-playbook) and
[The two LLM passes](#the-two-llm-passes).

---

## Mental model

The engine is a deterministic, headless batch job:

```
folder ──► [11 stages + verification hooks] ──► SQLite rows (gunks/tags/files) + extracted bundles
                                          └──► NDJSON events (stdout)  + trace.json (~/.gunk/runs/<runId>)
```

- **Only two stages call the LLM**: `survey` (pass 1) and `refine` (pass 2).
  Everything else is deterministic static analysis. So if output is wrong, the
  cause is almost always (a) what the deterministic stages fed the LLM, (b) the
  LLM's answer, or (c) the post-processing/quality-gate filters that drop the
  LLM's answer.
- **Durable state** lives in `~/.gunk/store.db`. **Telemetry** is NDJSON on
  stdout. **The full forensic record** (every prompt, every raw response, every
  gate decision) is `~/.gunk/runs/<runId>/trace.json` — only written with
  `--trace`.
- Determinism: `temperature: 0` and stable sorting everywhere, so the same
  inputs should give the same trace. Re-runs are comparable.

---

## Data flow

```mermaid
flowchart TD
  A["scan: walk folder, apply ignore rules"] --> B["symbols: web-tree-sitter per file"]
  B --> C["graph: imports → file nodes + edges"]
  C --> D["fingerprints: routes, deps, env/config, lexicon hints"]
  D --> E["repoMap: budgeted structural summary (text)"]
  E --> F["survey (LLM pass 1): repo map → capability hypotheses"]
  F --> G["expansion: BFS each hypothesis over the graph → file closure"]
  G --> H["refine (LLM pass 2): read closure files → Module or reject"]
  H --> I["verification: deterministic self-containment per module"]
  I --> J["qualityGates: accept / needsApproval / reject"]
  J --> K["persist: write accepted + needsApproval gunks to SQLite"]
  K --> L["extract: copy bundle + manifest + embeddings (accepted only)"]
  L -. optional eval/trace .-> M["build verification: best-effort extracted-bundle build check"]
```

Progress fractions emitted per stage (useful to see where a run stalls):
`scan 0.10 · symbols 0.20 · graph 0.30 · fingerprints 0.38 · repoMap 0.48 ·
survey 0.58 · expansion 0.66 · refine 0.78 · qualityGates 0.84 · persist 0.92 ·
extract 1.00`.

Source of truth: `src/decompose/pipeline.ts`.

---

## Stage-by-stage reference

### 1. scan — `src/ingest/scanner.ts`
- **In:** source folder path.
- **Does:** recursively walks the folder, applies ignore rules (node_modules,
  `.git`, build dirs, binaries, likely-secret files, `.gunkignore`).
- **Out:** `ScannedFile[]` (`relpath`, `absPath`, `size`).
- **Goes wrong when:** real source is excluded by ignore rules → it never
  reaches the LLM. **Check:** `trace.stages[scan].counts.files` vs how many files
  you expect.

### 2. symbols — `src/analyze/symbolExtractor.ts`
- **In:** each file's contents.
- **Does:** parses with the embedded tree-sitter grammar (JS/TS/TSX, Python,
  Swift, Go, Dart, Kotlin, Java) into symbols, imports, exports. Unknown
  languages or parse failures fall back to a regex extractor.
- **Out:** `FileSymbols[]`.
- **Goes wrong when:** a language has no grammar (only the listed languages use
  embedded parsers; everything else is regex-only) → weak imports/exports → weak graph edges →
  weak closures. **Check:** is the project mostly an unsupported language?

### 3. graph — `src/analyze/codeGraph.ts` + `importResolver.ts`
- **In:** `FileSymbols[]` + file contents.
- **Does:** resolves import specifiers to in-repo files and builds a file-level
  graph: nodes (`kind: "file"`) and edges (`call`, `import`, `implements`,
  `inherit`, `reference`). External (third-party) deps are tracked separately.
- **Out:** `CodeGraph` (`nodes`, `edges`, `externalDependencies`).
- **Goes wrong when:** import resolution misses (path aliases, monorepo layouts,
  re-exports) → edges missing → expansion can't pull collaborators into a
  closure. **Check:** `trace.stages[graph].counts.edges`; low edge count on a big
  repo is a red flag. This is the single most common root cause of "the module
  is missing half its files."

### 4. fingerprints — `src/analyze/capabilityFingerprint.ts`
- **In:** `FileSymbols[]`, dependency manifests, contents.
- **Does:** per file, extracts capability signals: HTTP routes, public exports,
  imported third-party dependencies, env vars, config keys, and lexicon hints
  (known libraries → capability labels, e.g. `stripe` → payments).
- **Out:** `CapabilityFingerprint[]`.
- **Used by:** the repo map (so the LLM sees anchors) and the quality gate's
  "does this module have a real surface?" check.

### 5. repoMap — `src/ingest/contextBuilder.ts` + `repoMap.ts`
- **In:** everything above.
- **Does:** serializes a **text** structural summary into a token budget
  (`--context-budget`, default 20,000 tokens; ~chars/4). Large maps are split
  into deterministic chunks and surveyed map-reduce style so capabilities below
  the first chunk are still visible. Per file it includes:
  cluster id, up to 8 key symbols, sorted exports, resolved imports, routes,
  env/config keys, capability hints, and a few route/manifest snippets. Plus
  graph clusters with cohesion scores and bridge files.
- **Out:** one budgeted string plus full chunk strings — **this is the only
  thing pass 1 sees.** It does *not* see file bodies.
- **Goes wrong when:** the repo is large and the budget truncates the map →
  capabilities depend on chunking. **Check:**
  `trace.stages[repoMap].counts.chunks` and `chunkChars`; if chunks are > 1,
  survey should have one LLM call per chunk plus a merge call. If a capability is
  still missing, inspect `trace.llmCalls[stage=survey]` by chunk.

### 6. survey (LLM pass 1) — `src/decompose/survey.ts`
See [The two LLM passes](#the-two-llm-passes). Produces `CapabilityHypothesis[]`.

### 7. expansion — `src/decompose/expander.ts`
- **In:** hypotheses + the code graph.
- **Does:** for each hypothesis, BFS from its `seedFiles` along graph edges
  (depth ≤ 3, ≤ 25 files) to build a **closure** of related files. Files reached
  by multiple capabilities — or known shared dirs (`config`, `lib`, `shared`,
  `types`, `utils`, `types.*`, `*utils.ts`) with fan-in ≥ 3 — are split out as
  **shared dependencies** rather than owned files. Records edge evidence and
  exclusion reasons.
- **Out:** `CapabilityExpansion[]` (`closureFiles`, `ownedFiles`,
  `sharedDependencyFiles`, `excludedFiles`, `edgeEvidence`).
- **Goes wrong when:** seed files aren't in the graph (survey cited a path that
  doesn't exist or was filtered), or the graph has no edges out of the seed → the
  closure is just the seed file → pass 2 sees almost nothing. **Check:**
  `trace.expansions[i].closureFiles` and `.excludedFiles` (reasons like "seed
  file is not present in the code graph" or "closure file limit reached").

### 8. refine (LLM pass 2) — `src/decompose/refiner.ts`
See [The two LLM passes](#the-two-llm-passes). Produces `Module[]` (or rejects).

### 9. verification + qualityGates — `src/decompose/selfContainment.ts`, `qualityGate.ts`
See [Quality gates](#quality-gates). Classifies each module as
`accepted` / `needsApproval` / `rejected`.

Before the gate decides, deterministic self-containment checks that every
module-owned internal import stays inside the module and every claimed
entrypoint is an exported symbol on an owned file. Declared package dependencies
come from `package.json`, `pubspec.yaml`, Gradle, Maven `pom.xml`, and the other
supported manifests. Failures add `failsSelfContainment` and downgrade or reject
the module. Strongly self-contained modules with real entrypoints can survive
borderline/weak graph cohesion, but trivial traps still fail.

### 10. persist — `pipeline.ts`
- **Does:** writes `accepted` and `needsApproval` modules to SQLite as gunks
  (with tags and files). **Rejected modules are not persisted.**
- **Check:** `trace.summary` and the `gunks` table.

### 11. extract — `src/extract/extractor.ts` + `src/search/embeddingIndex.ts`
- **Does:** for `accepted` modules only, copies files into a bundle under
  `~/.gunk/modules/<id>`, writes `gunk.yml` + README, redacts secrets, flags
  licenses, then (if an embedding provider is configured) indexes embeddings and
  runs cross-source dedupe. `needsApproval` modules wait for manual approval in
  the app. Embedding/dedupe failures are swallowed (best-effort) and never fail
  the run.

---

## The two LLM passes

This is where AI quality lives. Both run at `temperature: 0` and use strict JSON
schema structured output.

### Pass 1 — survey (`src/decompose/survey.ts`)

**Sees:** the source name, the sorted list of known file paths, and the repo map
text. **Does not see file contents.**

**System prompt (verbatim):**

```
You are Pass 1 of gunk's capability-centric decomposition pipeline.
Propose capability hypotheses from the structural repo map only.

Real-module rubric:
- A real module is a reusable capability or feature slice that spans the files needed to stand alone.
- Prefer user-visible or integration-visible capabilities such as OAuth login, Stripe checkout, upload pipeline, API endpoint group, CLI command, SDK client, or workflow.
- Reject file-level chunks, type-only files, generic utilities, config-only groups, generated files, docs-only groups, and arbitrary folders.
- Each hypothesis needs at least one structural anchor: route, entrypoint, public export, dependency capability hint, env/config key, or strongly connected graph cluster.
- Name the capability by what it does, not by a filename.
```

**Output schema:** `{ hypotheses: [{ name, rationale, anchors[], seedFiles[],
expectedCollaborators[], granularity }] }`.

**Post-processing that silently drops hypotheses** (`parseHypotheses`): a
hypothesis is **discarded** if:
- it has zero `seedFiles`, or any seed file is not in the known-files set, or
- any `expectedCollaborator` is not in the known-files set.

It is kept but marked `priority: "low"` if it has no anchors and cites < 2 known
files. **This is a common "the model proposed it but it vanished" cause** — the
model hallucinated a path or used a slightly different relative path than what
`scan` produced. **Check:** compare `trace.llmCalls[stage=survey].responseJson`
(what the model said) against `trace.hypotheses` (what survived).

### Pass 2 — refine (`src/decompose/refiner.ts`)

Runs **once per expansion**. **Sees:** the candidate name/rationale/anchors, the
closure's owned/shared/excluded file lists, edge evidence, and the **actual file
contents** of the closure (budgeted: ≤ 32,000 chars total, ≤ 8,000 chars/file,
truncated with markers).

**System prompt (verbatim):**

```
You are Pass 2 of gunk's capability-centric decomposition pipeline.
Deep-read one expanded capability closure and return structured JSON only.

Real-module rubric:
- Keep only files needed for the reusable capability.
- Separate owned files from shared dependencies.
- Tag the module with 2-5 short labels naming what it does. Prefer the suggested tags when they fit; otherwise mint a concise lowercase kebab-case tag for the capability or domain.
- Use only files present in the closure.
- Return module null with a reject reason if this is not a real module.
```

The user prompt lists the seeded taxonomy as `Suggested tags:` (guidance, not a
hard constraint).

**Output schema:** `{ module: {name, purpose, tags[], language, ownedFiles[],
sharedDependencies[], entrypoints[{path,symbol}], anchors[], confidence} | null,
qualityGateHints{...}, reject{reason} | null }`.

**Post-processing rules** (`parseModule`):
- A malformed response (missing `module` key, `qualityGateHints` not an object,
  missing `reject`) **throws** and fails the whole run.
- `module: null` → rejected with the model's reason (surfaced into the trace).
- `ownedFiles`/`sharedDependencies` are **filtered to the closure** — paths
  outside the closure are dropped. Shared files are removed from owned. If
  nothing survives, the module becomes `null` (dropped).
- `tags` are **AI-discovered (hybrid)**: the seeded taxonomy is passed to the
  model as a *suggested* vocabulary (preferred when it fits), but the model may
  mint new domain tags. Returned tags are run through `normalizeTag`
  (`src/analyze/tagNormalizer.ts`) — lowercased, kebab-cased, deduped, and capped
  at 6 — then persisted with `upsertTag` (new names auto-create a `tags` row).
  The refiner output schema no longer constrains tags to an `enum`, so an empty
  taxonomy no longer strips tags. The 11 seed tags remain as suggestions only.
- `anchors` fall back to the hypothesis anchors if the model returns none.
- `confidence` is clamped to `[0,1]` and drives the quality-gate decision.

**Check:** `trace.refinements[i]` (`accepted`, `rejectReason`, `module`) and the
matching `trace.llmCalls[stage=refine]` entry for the full prompt + raw response.

---

## Quality gates

`src/decompose/qualityGate.ts`. Each module gets one decision. Order matters:
**any** rejection reason → `rejected`; else confidence below threshold →
`needsApproval`; else `accepted`.

| Reason (`trace.gateEvaluations[].reasons`) | Triggered when |
| --- | --- |
| `missingFiles` | module has zero files |
| `missingSurface` | no surface/anchors and no fingerprint signal (routes, exports, deps, env, config, hints) on any file |
| `singleFileWithoutOwnedSurface` | exactly 1 file and that file owns no route/public export/surface |
| `lowCohesion` | > 1 file and internal/total edge ratio < `0.35` |
| `failsSelfContainment` | deterministic import or entrypoint verification failed |
| `generatedOnly` / `typeOnly` / `utilityOnly` / `configOnly` | all files classify as that trivial kind |
| `typeOnly`+`utilityOnly`, `configOnly`+`typeOnly` | files are only those trivial kinds combined |
| `duplicateOverlap` | ≥ `0.85` file overlap with another kept module (lower-confidence/smaller/later-named one loses) |
| `belowConfidenceThreshold` | no rejection reasons, but `confidence` < `--confidence` (default `0.7`) → `needsApproval` |

- **Cohesion** = internal edges / (internal + external) edges over the module's
  files (single-file modules score 1.0). Verified self-contained modules with a
  real entrypoint can survive low cohesion; this protects sparse JVM/mobile
  feature packages without opening the door to generated/type/config traps.
- **File classification** (`classify`) keys off path components and contents:
  `generated` (markers like `@generated`, `do not edit`), `config`, `utility`,
  `typeOnly` (`types.*`, `.d.ts`, or only import/type/interface/enum lines), else
  `source`.

**Goes wrong when:** good modules get rejected because (a) the graph was too
sparse → `lowCohesion`, (b) fingerprints missed the surface → `missingSurface`,
(c) self-containment found an owned import or claimed entrypoint gap →
`failsSelfContainment`, or (d) file classification is too aggressive →
`typeOnly`/`utilityOnly`. The `trace.gateEvaluations[].fileKinds` map shows
exactly how each file was classified.

---

## Observability

### NDJSON events (stdout, with `--json`) — `src/contract/events.ts`

One JSON object per line. Used by host UIs to drive progress.

| `type` | Fields |
| --- | --- |
| `stage` | `stage`, `phase` ("started"/"finished"), `durationMs?`, `counts?` |
| `progress` | `stage`, `fraction` (0–1), `modulesFound?` |
| `result` | `runId`, `gunkIds[]`, `accepted`, `needsApproval`, `rejected`, `tracePath?` |
| `error` | `message`, `stage?` |

### Run trace (`~/.gunk/runs/<runId>/trace.json`, with `--trace`) — `src/trace/trace.ts`

This is the debugging gold mine. Top-level fields:

| Field | What's in it |
| --- | --- |
| `runId`, `sourceName`, `provider`, `model`, `status`, `error` | run identity + outcome |
| `startedAtMs` / `finishedAtMs` | wall-clock timing |
| `stages[]` | per stage: `durationMs`, `counts`, `status`, `error` |
| `llmCalls[]` | **per LLM call: full `requestMessages` (the exact prompt), full `responseJson` (the raw model output), tokens, `durationMs`, tagged by `stage`** |
| `hypotheses[]` | the survey hypotheses that **survived** filtering |
| `expansions[]` | per hypothesis: `closureFiles`, `ownedFiles`, `sharedDependencyFiles`, `excludedFiles` (+reasons), `edgeEvidence` |
| `refinements[]` | per candidate: `accepted`, `rejectReason`, resulting `module` |
| `gateEvaluations[]` | per module: `decision`, `reasons`, `cohesionScore` |
| `verification.selfContainment[]` | per refined module: `imports`, `entrypoint`, `danglingImports[]`, `missingEntrypoints[]`; this is gate-enforcing |
| `verification.build[]` | per extracted bundle: optional build command outcome; eval/trace only, never gate-enforcing |
| `summary` | `accepted`, `needsApproval`, `rejected`, `gunkIds` |

Because `llmCalls` carries the verbatim prompt **and** the raw response, you can
always answer "what did we ask, and what did it actually say?" without re-running.

The Swift app's **Runs** tab reads these files; `verification` is additive and
backward-compatible, so older traces without it still decode.

---

## Debugging playbook

Start from the symptom, jump to the stage, open the trace field.

| Symptom | Likely stage | Open in trace | Typical fix |
| --- | --- | --- | --- |
| Run fails immediately at survey | LLM/auth | `error`, last `llmCalls` | bad/missing API key, wrong model, provider down (HTTP status in message) |
| Way fewer files scanned than expected | scan | `stages[scan].counts.files` | ignore rules / `.gunkignore` too broad |
| Modules missing collaborator files | graph / expansion | `stages[graph].counts.edges`, `expansions[].closureFiles`/`excludedFiles` | import resolution gaps (aliases/monorepo); raise `maxDepth`/`maxFiles` |
| Model proposed a capability but it's gone | survey post-filter | `llmCalls[survey].responseJson` vs `hypotheses` | hallucinated/mismatched paths; tighten repo map paths |
| Capabilities never proposed at all | repoMap budget | `stages[repoMap].counts.chars` | truncation; raise `--context-budget` |
| Modules come back with no tags | refine | `refinements[].module.tags` | model returned none; tags are AI-minted + normalized, not taxonomy-gated |
| Good module rejected as low cohesion | graph / gates | `gateEvaluations[].cohesionScore`, edges | sparse graph; check importResolver |
| Module downgraded/rejected for self-containment | verification / gates | `verification.selfContainment[]`, `gateEvaluations[].reasons` | include missing internal collaborators, fix manifest dependency parsing, or remove fake entrypoints |
| Good module rejected as trivial | gates | `gateEvaluations[].fileKinds` | over-aggressive `classify`; inspect paths |
| Everything is `needsApproval` | refine confidence | `refinements[].module.confidence` | model under-confident; lower `--confidence` or improve context |
| Output not reproducible | provider | `llmCalls[].responseJson` across runs | ensure `temperature: 0` honored; some providers are non-deterministic |

### Reproduce a single run with full forensics

```bash
cd engine
GUNK_API_KEY=sk-... bun run src/index.ts /path/to/project \
  --provider openai --model gpt-4.1-mini \
  --db /tmp/debug.db --gunk-home /tmp/gunk-home \
  --json --trace
# then inspect:
cat /tmp/gunk-home/runs/*/trace.json | jq '.stages, .summary'
cat /tmp/gunk-home/runs/*/trace.json | jq '.hypotheses'
cat /tmp/gunk-home/runs/*/trace.json | jq '.llmCalls[] | select(.stage=="survey") | .responseJson'
cat /tmp/gunk-home/runs/*/trace.json | jq '.gateEvaluations[] | {name: .module.name, decision, reasons}'
cat /tmp/gunk-home/runs/*/trace.json | jq '.verification'
```

`--json` (stdout) is the live progress; `--trace` is the post-mortem. stderr
carries human-readable `[decompose]` log lines.

### Watch a run live: `gunk-engine watch`

`trace.json` is a post-mortem (written once at the end). To **watch the AI think
in real time** — every stage transition and the full prompt + raw response of
every LLM call as they happen — use the live log.

Whenever the engine runs with `--trace` (the app always does), it also streams a
tail-able `~/.gunk/runs/<runId>/live.jsonl`, one JSON event per line, flushed
immediately. `gunk-engine watch` follows it and pretty-prints each step:

```bash
cd engine
bun run watch                 # attach to the active run, or wait for the next one to start
bun run watch --full          # don't truncate prompts/responses
bun run watch <runId>         # follow a specific run
bun run watch --no-follow     # print the current log once and exit
bun run watch --gunk-home /tmp/gunk-home
```

Typical workflow: open a terminal, run `bun run watch` (it prints "waiting for a
run to start…"), then process a folder in the app — every scan/survey/refine/gate
step and each LLM prompt + response streams into the terminal live. The viewer
exits when the run finishes. Source: `src/trace/liveLog.ts` (producer),
`src/trace/watch.ts` (viewer).

### Read a trace fast: `gunk-engine trace`

`trace.json` is verbose. The `trace` subcommand digests one run into a
one-screen, symptom-oriented report: the **signal funnel** (files → edges →
hypotheses → modules → accepted), survey/refine/gate decisions,
self-containment failures, and **heuristic warnings that point at the likely
failing stage**.

```bash
cd engine
bun run trace                       # newest run under ~/.gunk/runs
bun run trace <runId>               # a specific run
bun run trace /tmp/gunk-home/runs/<runId>/trace.json  # an explicit path
bun run trace --gunk-home /tmp/gunk-home              # non-default home
bun run trace <runId> --show survey # + dump verbatim prompt/response for a stage
bun run trace <runId> --json        # structured digest (for tools / diffing)
```

The funnel makes "where did the signal die?" obvious at a glance; the warnings
encode the playbook rules below (0-edge graph, dropped survey hypotheses,
low-cohesion rejections, self-containment failures). Reach for `--show <stage>`
when you need the exact prompt and raw model output. Source:
`src/trace/digest.ts`.

---

## Tuning knobs

| Knob | Where | Default | Effect |
| --- | --- | --- | --- |
| `--context-budget` | survey input | 20,000 tokens | bigger repo map (fixes truncation) at higher cost |
| `--confidence` | quality gate | 0.7 | accept/needsApproval cutoff |
| expansion `maxDepth` | `expander.ts` | 3 | how far closures reach |
| expansion `maxFilesPerCapability` | `expander.ts` | 25 | closure size cap |
| `sharedFanInThreshold` | `expander.ts` | 3 | when a file becomes a shared dep |
| `cohesionThreshold` | `qualityGate.ts` | 0.35 | low-cohesion rejection line |
| `duplicateOverlapThreshold` | `qualityGate.ts` | 0.85 | dedupe sensitivity |
| refiner `maxContextCharacters` / `maxFileCharacters` | `refiner.ts` | 32k / 8k | how much code pass 2 reads |

The eval gate (`test/evalGate.test.ts`) runs the whole pipeline against
multi-language fixtures with recorded LLM responses. It keeps express/next at
the Phase 4 baseline, requires Flutter/Dart, Kotlin/Android, Java service,
mixed monorepo, and large-repo fixtures to meet their floors, asserts zero trap
false positives, and requires persisted modules to pass deterministic
self-containment. Run it after any change to these knobs, prompts, manifest
parsing, import resolution, or gate rules.
