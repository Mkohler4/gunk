# Phase 14 — Baseline: today's engine behavior on three repo kinds (T-14.0)

> **Status:** in progress — capturing funnels.
> **Owner:** Mark
> **Task:** [phase-14-module-architect.md → T-14.0](./phase-14-module-architect.md)

## Why this doc exists

This is the **"before" snapshot** for the Module Architect phase. Every later
task (T-14.2 … T-14.8) claims to fix one of two reproducible failures:

1. **gunk false negative** — gunk finds **no** modules in its own library/tool
   repo, because the survey rubric and the "surface" proxy are biased toward
   SaaS-style app features and reject "utilities."
2. **`ThemeProvider` false positive** — a high-fan-in cross-cutting file is
   surfaced as a module purely because everything imports it.

We capture today's funnel on three repo kinds so the improvement is measurable,
not vibes. Read the funnel as: `files → edges → hypotheses → modules → accepted`.
Where it collapses to `0` is where the engine gives up.

## How these numbers were produced (reproduce)

```bash
cd gunk/engine

# Run with a full trace into a throwaway home:
GUNK_API_KEY=sk-... bun run src/index.ts <REPO_PATH> \
  --provider openai --model gpt-4.1-mini \
  --db /tmp/p14.db --gunk-home /tmp/p14 --json --trace

# Digest the newest run into the one-screen funnel:
bun run trace --gunk-home /tmp/p14
```

- `provider/model`: `openai` / `gpt-4.1-mini`
- `gunk-home`: `/tmp/p14` (traces land in `/tmp/p14/runs/<runId>/trace.json`)
- Date captured: <!-- YYYY-MM-DD -->

---

## 1. SaaS / app — `<repo name>`

**Path:** `<REPO_PATH>`
**Why this repo:** <!-- one line: what kind of app, language, rough size -->

```text
<!-- paste the full `bun run trace` funnel + SURVEY / REFINE / QUALITY GATES / RESULT / WARNINGS here -->
```

**Reading (one paragraph):**
<!--
Where does the funnel collapse (survey? refine? gates?) and why?
Which real capabilities were MISSED (false negatives)?
Which non-capabilities were WRONGLY SURFACED (false positives, e.g. a
cross-cutting provider/context/theme/config file proposed as a module)?
This is the repo where we expect to see the ThemeProvider-style false positive.
-->

---

## 2. Library / SDK — `<repo name>`

**Path:** `<REPO_PATH>`
**Why this repo:** <!-- one line -->

```text
<!-- paste funnel here -->
```

**Reading (one paragraph):**
<!--
Same questions. We expect recall to be poor here — tooling/library capabilities
(scanners, parsers, redactors, extractors) tend to get rejected as "utilities"
or "no surface."
-->

---

## 3. gunk itself — `gunk/engine` (TS library/tool)

**Path:** `/Users/markkohler/Documents/new-idea/gunk/engine`
**Why this repo:** the canonical "library/tool" case the phase is built to fix —
the engine is a reusable analysis tool, not a SaaS app.

```text
<!-- paste funnel here -->
```

**Reading (one paragraph):**
<!--
This is the headline false negative. Expect hypotheses to survive survey but die
at the quality gate (self-containment / lowCohesion / missingSurface), yielding
0 accepted. Name the real capabilities the engine SHOULD have found in itself
(e.g. Repo Scanner, Symbol Extractor, Import Resolver, Capability Fingerprinter,
Trace Digest, Secret Redactor) and which gate reason killed each.
-->

> **Note:** an earlier run against gunk's **Swift app** produced
> `accepted 0 · needsApproval 0 · rejected 16` — 16 hypotheses survived survey
> but every one failed self-containment / lowCohesion at the gate. That run is
> the same false negative on the app side and can be cited here too.

---

## Cross-repo reading (the measuring stick)

| Repo kind     | files | edges | hypotheses | modules | accepted | collapses at |
| ------------- | ----- | ----- | ---------- | ------- | -------- | ------------ |
| SaaS / app    |       |       |            |         |          |              |
| Library / SDK |       |       |            |         |          |              |
| gunk/engine   |       |       |            |         |          |              |

**One-paragraph summary of the gap this phase closes:**
<!--
Tie it together: the SaaS app surfaces a cross-cutting file it shouldn't (false
positive), while the library and gunk itself surface nothing they should (false
negatives). Both stem from a SaaS-feature-shaped rubric + a "surface" proxy that
rejects utilities. This is the before; T-14.2 (seed suppression) and T-14.4–T-14.6
(repo-kind + ontology-aware prompts) are the after.
-->
