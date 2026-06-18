# ADR-0018: Module Architect — AI-led module creation over graph clustering

- **Status:** Proposed
- **Date:** 2026-06-18
- **Deciders:** Mark Kohler

## Context

[ADR-0012](0012-capability-centric-decomposition.md) accepted a
structure-first, capability-centric pipeline: deterministic static analysis
builds a repo map and code graph, an LLM survey hypothesizes capabilities from
that map, a graph BFS expands each hypothesis into a file closure, an LLM refine
pass deep-reads the closure, and deterministic quality gates accept/reject. The
implementation lives in `engine/src/decompose/` and is documented in
`engine/docs/ARCHITECTURE.md`.

Two failure modes show the limits of that design:

1. **Library/tool false negatives.** Running gunk on its **own** repo produced
   **no modules**, despite obviously reusable capabilities (repo scanner,
   dependency-manifest parser, secret redactor, license detector, symbol
   extractor, LLM provider client, …). The survey rubric prefers app/integration
   capabilities and rejects "generic utilities / arbitrary folders"; the
   `hasSurface` gate keys on routes ∨ public exports ∨ dependency-lexicon hints;
   and `classify()` buckets `utils/`-style paths as trivial. Library code reads
   as "utilities" and never clears the bar.
2. **Cross-cutting false positives.** A high-fan-in `ThemeProvider` was surfaced
   as a module purely because everything imports it.
   `GraphClustering.highFanInBridgeFiles` treats high inbound degree as a
   *positive* anchor, and "strongly-connected cluster" is an accepted survey
   anchor, so a shared utility gets promoted to a capability.

Both stem from one root cause: **the import graph is the architect.** The
pipeline asks "can I find a connected cluster that looks like an app feature?"
and the LLM is boxed inside that frame — Pass 1 never sees code, and module
boundaries are drawn by BFS, not by semantic reasoning.

## Decision

Adopt the **Module Architect** architecture as gunk's north-star decomposition
design. The full specification — including the Mermaid architecture diagrams in
its Appendix A — is
[`docs/design/module-architect.md`](../design/module-architect.md). When
implemented, it supersedes ADR-0012's pipeline *shape* (not its safety,
manifest, provenance, or license rules, which are retained by reference from
ADR-0011).

Core commitments:

1. **A module is a product, not a cluster.** It has a kind, a public contract,
   owned files, classified dependencies, an extraction plan, and a verification
   proof. A module is *allowed to require boundary work* (extract / wrap / adapt
   / generate) rather than having to be already self-contained.
2. **Graph is evidence, not judge.** The graph answers "what depends on what?";
   the LLM answers "what capability exists and what is its boundary?"; the
   compiler/tests answer "does the created module actually work?"
3. **Repo-kind-aware rubrics, as soft priors not hard gates.** Classify the repo
   (`saas_app`, `library`, `cli_tool`, `compiler_or_analyzer`, …) before
   discovery, and use kind-specific module shapes. Library/tool capabilities
   (scanner, parser, resolver, extractor, indexer, provider client, pipeline
   stage, …) are first-class, not "utilities." **Critically, the capability
   ontology is a scoring prior and a recall aid — never an allow-list.** Matching
   a known shape adds weighted evidence; not matching one never rejects a
   candidate. There is an explicit unknown-/novel-shape discovery path, and the
   ontology evolves. A hardcoded noun list (SaaS *or* tooling) would only
   relocate the blind spot. See `docs/design/module-architect.md` §12.
4. **Ensemble candidate discovery + specialist deep-read agents.** Many
   generators emit `ModuleThesis` candidates; specialist LLM agents (Library
   Architect, Skeptic, Boundary Refiner, Test Architect, Packaging) deep-read
   real code, not just the repo map.
5. **Semantic boundary synthesis replaces BFS.** A weighted solver classifies
   each dependency as owned / copied / shared-kernel / generated-type /
   interface / adapter-port / external / rejected.
6. **High fan-in is suspicious, not attractive.** High-inbound-degree files are
   suppressed as module *seeds* and allowed only as shared dependencies (fixes
   ThemeProvider).
7. **Materialize + verify.** Produce real packages, façades, adapters, tests,
   and a migration patch, then prove them via typecheck/test/behavioral-compare
   loops. Accept modules that required generated boundaries.

The cost stance from ADR-0012 holds and intensifies: correctness over speed.
Many LLM calls and scratch compile/test loops per run are acceptable.

## Consequences

### Positive

- Fixes the gunk self-blindness and the ThemeProvider false positive directly.
- Detects library/tool/analysis capabilities, not only SaaS features.
- Output becomes actionable refactoring artifacts (packages + patches + proof),
  not just labels.
- Verification proves extractability instead of approximating it.

### Negative

- Substantially more expensive and complex: multi-agent LLM passes, boundary
  synthesis, code generation, and scratch compile/test workspaces.
- Introduces new failure surfaces (generated adapters that don't compile, flaky
  scratch builds) that need their own handling and eval coverage.
- Larger architecture (five cooperating services) to build and maintain versus
  today's single in-process pipeline.

### Constraints this locks in (when adopted)

- The graph remains advisory; it must not be the sole arbiter of boundaries or
  capability anchors.
- The capability ontology must stay a soft prior: matches add weighted evidence;
  non-matches never gate. The only hard constraints are architectural (clear
  purpose, coherent owned behavior, stable public contract, synthesizable
  boundary, verifiable extraction).
- Survey/refine prompts must be repo-kind- and role-specific and must permit
  boundary transformations (not just accept/reject).
- Verification (typecheck/tests/behavioral comparison) is part of the accept
  decision, not an optional post-step.
- ADR-0011's `gunk.yml`, secret redaction, provenance privacy, and license
  rules remain unchanged by reference.

## Supersedes / amends

- Supersedes ADR-0012's pipeline *shape* (survey → BFS expansion → refine →
  binary gates) when implemented. Retains ADR-0012's "modules are reusable
  capabilities" intent and ADR-0011's manifest/safety rules by reference.

## Related

- [`docs/design/module-architect.md`](../design/module-architect.md) — full spec
- ADR-0008: Gunks are modules *(Accepted)*
- ADR-0011: AI decomposition pipeline and gunk.yml manifest *(Accepted; safety rules retained)*
- ADR-0012: Capability-centric decomposition *(Accepted; pipeline shape superseded here)*
- ADR-0014: Multi-language coverage and verification *(Accepted)*
- `engine/docs/ARCHITECTURE.md` — current engine reference
