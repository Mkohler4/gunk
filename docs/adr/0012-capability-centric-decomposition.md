# ADR-0012: Capability-centric decomposition

- **Status:** Accepted
- **Date:** 2026-06-04
- **Deciders:** Mark Kohler

## Context

ADR-0011 accepted the Phase 3 AI decomposition pipeline: scan a dropped source,
build a token-budgeted text representation, make one structured LLM call, then
persist and extract module-shaped rows. That pipeline shipped the first
end-to-end product path, but it was intentionally shallow. It deferred
tree-sitter symbol graph selection and embeddings, and it let the model infer
module boundaries from compressed source text.

That is not enough for Phase 4. The observed failure mode is file-level junk:
the model can see a useful-looking `types.ts`, but without repository structure
it may emit that file as a standalone "module." Gunk needs capabilities a
developer would reuse, not arbitrary files.

## Decision

Phase 4 replaces ADR-0011's decomposition pipeline with a
capability-centric, structure-first, multi-pass pipeline. This ADR supersedes
ADR-0011's pipeline shape only. ADR-0011's `gunk.yml` manifest spec, secret
redaction rules, home-relative provenance, and license flagging rules remain
unchanged and are retained by reference.

### Normative real-module spec

A candidate is a real module only if it meets **all** of these:

1. **External-facing capability.** It delivers something a developer would
   request by name, with an identifiable surface: an HTTP route, a CLI command,
   an exported public API, or a domain workflow. Not an internal implementation
   detail.
2. **Multi-file cohesion.** It is the *closure* of collaborating files needed to
   deliver the capability, not a single file. (A genuinely single-file capability
   is allowed only when that one file owns the entire surface — rare.)
3. **An anchor.** It is anchored by a recognizable signal: a third-party
   capability library (`passport-google-oauth20`, `stripe`, `nodemailer`,
   `@aws-sdk/client-s3`), a route group, a domain noun, or a distinct subsystem.
4. **Internal cohesion / low coupling.** Its files reference each other far more
   than they reference the rest of the repo.
5. **Right granularity.** Feature-level — between file-level (too small:
   `types.ts`, a single util) and app-level (too big: "the whole backend").

Explicit **non-modules** (must be rejected or absorbed as shared deps): a lone
type/interface file, a single utility function, a bare config file, generated
code, an arbitrary directory, or "everything else."

Shared/utility files that many capabilities touch are **referenced as
dependencies** (and optionally collected into a single `shared` bucket), never
emitted as standalone modules.

### Structure-first principle

The LLM must never propose module boundaries from raw text alone. The app first
builds deterministic structure:

- tree-sitter symbols per supported language
- a code graph with import, call, reference, and inheritance edges
- capability fingerprints from third-party dependencies, routes, entrypoints,
  environment variables, config keys, naming, and directories
- a compressed structural repo map

The LLM reasons over that structure, then reads concrete file contents only
inside candidate closures. This un-defers ADR-0011's tree-sitter work. Local
embeddings are also in scope for semantic search and cross-source dedup,
un-deferring ADR-0011's embeddings work.

### Multi-pass contract

The pipeline is:

1. Pass 1 survey: hypothesize capabilities from the structural repo map.
2. Graph-closure expansion: deterministically pull collaborators for each
   hypothesized capability.
3. Pass 2 refine: deep-read each candidate closure and finalize module files,
   shared dependencies, tags, and confidence.
4. Deterministic quality gates: accept, reject, merge, or move files into shared
   dependencies.

#### Pass 1 survey input

```json
{
  "source": {
    "id": 0,
    "name": "string",
    "languageHints": ["TypeScript"]
  },
  "repoMap": {
    "files": [
      {
        "path": "relative/path.ts",
        "symbols": ["GET", "AuthService"],
        "imports": ["next-auth"],
        "exports": ["GET"],
        "routes": ["/api/auth"],
        "entrypoints": ["GET"],
        "envKeys": ["GOOGLE_CLIENT_ID"],
        "configKeys": ["auth.providers.google"],
        "fingerprints": ["google-oauth", "auth"]
      }
    ],
    "graphSummary": {
      "clusters": [
        {
          "id": "cluster-auth",
          "files": ["relative/path.ts"],
          "internalEdges": 8,
          "externalEdges": 2,
          "anchors": ["next-auth", "/api/auth"]
        }
      ]
    }
  },
  "rubric": "ADR-0012 normative real-module spec"
}
```

#### Pass 1 survey output

```json
{
  "capabilities": [
    {
      "id": "candidate-google-oauth",
      "name": "Google OAuth login",
      "purpose": "Authenticates users with Google OAuth and creates a session.",
      "anchors": ["next-auth", "/api/auth", "GOOGLE_CLIENT_ID"],
      "seedFiles": ["app/api/auth/[...nextauth]/route.ts"],
      "expectedCollaborators": ["service", "provider-client", "config", "types", "tests"],
      "tags": ["auth", "api"],
      "rationale": "string",
      "confidence": 0.82
    }
  ],
  "rejections": [
    {
      "path": "src/types.ts",
      "reason": "lone type/interface file"
    }
  ]
}
```

#### Graph-closure expansion input

```json
{
  "candidate": {
    "id": "candidate-google-oauth",
    "seedFiles": ["app/api/auth/[...nextauth]/route.ts"],
    "anchors": ["next-auth", "/api/auth", "GOOGLE_CLIENT_ID"]
  },
  "codeGraph": {
    "nodes": ["relative/path.ts"],
    "edges": [
      {
        "from": "app/api/auth/[...nextauth]/route.ts",
        "to": "src/auth/service.ts",
        "kind": "import"
      }
    ]
  },
  "fingerprints": ["google-oauth", "auth"]
}
```

#### Graph-closure expansion output

```json
{
  "candidateId": "candidate-google-oauth",
  "closureFiles": ["app/api/auth/[...nextauth]/route.ts", "src/auth/service.ts"],
  "sharedDependencyFiles": ["src/lib/db.ts"],
  "excludedFiles": [
    {
      "path": "src/generated/client.ts",
      "reason": "generated code"
    }
  ],
  "edgeEvidence": [
    {
      "from": "app/api/auth/[...nextauth]/route.ts",
      "to": "src/auth/service.ts",
      "kind": "import"
    }
  ]
}
```

#### Pass 2 refine input

```json
{
  "candidate": {
    "id": "candidate-google-oauth",
    "name": "Google OAuth login",
    "anchors": ["next-auth", "/api/auth", "GOOGLE_CLIENT_ID"]
  },
  "closure": {
    "ownedFiles": [
      {
        "path": "app/api/auth/[...nextauth]/route.ts",
        "contents": "string"
      }
    ],
    "sharedDependencyFiles": [
      {
        "path": "src/lib/db.ts",
        "summary": "Shared database client used by multiple capabilities."
      }
    ]
  },
  "structuralEvidence": {
    "routes": ["/api/auth"],
    "entrypoints": ["GET", "POST"],
    "externalDeps": ["next-auth"],
    "envKeys": ["GOOGLE_CLIENT_ID"]
  },
  "rubric": "ADR-0012 normative real-module spec"
}
```

#### Pass 2 refine output

```json
{
  "module": {
    "name": "Google OAuth login",
    "purpose": "Authenticates users with Google OAuth and creates a session.",
    "tags": ["auth", "api"],
    "language": "TypeScript",
    "ownedFiles": ["app/api/auth/[...nextauth]/route.ts", "src/auth/service.ts"],
    "sharedDependencies": ["src/lib/db.ts"],
    "entrypoints": [
      {
        "path": "app/api/auth/[...nextauth]/route.ts",
        "symbol": "GET"
      }
    ],
    "anchors": ["next-auth", "/api/auth", "GOOGLE_CLIENT_ID"],
    "confidence": 0.91
  },
  "qualityGateHints": {
    "externalFacingCapability": true,
    "multiFileCohesion": true,
    "anchorPresent": true,
    "rightGranularity": true
  },
  "reject": null
}
```

If Pass 2 decides a candidate is not a real module, it must return
`"module": null` and a `reject` object with a rubric-grounded reason. The
Swift quality gates still make the final decision.

### Deterministic quality gates

Quality gates run in Swift after LLM output. The model may provide evidence,
but it is not trusted as the enforcement layer.

The validator rejects candidates that:

- lack an external-facing surface
- are lone type/interface files, single utilities, bare configs, generated
  code, arbitrary directories, or "everything else"
- have no anchor from dependencies, routes, entrypoints, domain nouns, config,
  environment variables, or subsystem naming
- are app-level blobs or file-level fragments instead of feature-level modules
- have weak internal cohesion or excessive coupling to unrelated repo files
- cite files outside the scanned source or secret-redacted safe set

Accepted modules are persisted as `gunks`, with file membership in
`gunk_files`, tags in `gunk_tags`, and every LLM call recorded in `llm_runs`.

### Granularity and shared files

The target granularity is a reusable feature-level capability: "Google OAuth
login," "Stripe subscription billing," "S3 image upload." A single file may be
accepted only when it owns the whole external surface. Shared files, broad
utilities, common types, generated clients, database clients, and app config are
not emitted as standalone modules. They are either referenced as dependencies
from accepted modules or collected into one `shared` bucket for extraction and
manifest purposes.

### Cost stance

Correctness wins over speed. A drop may run static analysis, a whole-repo survey
LLM call, many per-candidate refine calls, local embedding generation, and dedup
checks. That is acceptable for Phase 4. All LLM calls must write `llm_runs`
rows. Token accounting remains useful; `cost_usd` stays inert and does not
revive a cost-meter UI.

### Scope note

Phase 4 makes no UI changes. The pipeline reuses the existing drop path, Dock
processing state, browse list, approval queue, and settings surfaces. The
standalone app window, marketplace, and any SwiftUI redesigns are deferred to a
later phase.

## Consequences

### Positive

- Gunk's module definition is now explicit, testable, and enforced outside the
  model.
- The LLM receives repository structure and capability fingerprints before it
  reads file contents, so it can reason about collaborating files instead of
  guessing from text boundaries.
- Tree-sitter and embeddings are no longer optional refinements; they are part
  of the Phase 4 architecture.
- Evaluation can target concrete failures, especially the `types.ts`-only false
  positive from Phase 3.

### Negative

- Ingestion gets slower and more complex. The project accepts this because
  module quality is the product.
- Static analysis and graph construction become core app code and need strong
  fixtures across languages.
- The pipeline now has more intermediate artifacts, which makes schema parity
  and test fixture maintenance more important.

### Constraints this locks in

- AI processing still runs in `gunk.app`; `gunk-mcp` remains a reader of the
  shared SQLite store.
- The app must keep the SQLite schema byte-for-byte in parity with MCP
  migrations.
- LLM clients must support structured output for survey and refine calls.
- Deterministic Swift validators decide whether candidates become modules.
- Every LLM call is recorded in `llm_runs`.
- `gunk.yml`, secret redaction, provenance privacy, and license flagging remain
  exactly as specified by ADR-0011.
- No SwiftUI view changes are in scope for Phase 4.

## Supersedes / amends

- Supersedes ADR-0011's single-pass, token-budgeted text decomposition
  pipeline.
- Retains ADR-0011's `gunk.yml` manifest, secret safety, provenance privacy, and
  license stance unchanged by reference.
- Un-defers ADR-0011's deferred tree-sitter symbol graph and embeddings work.
- Implements ADR-0008's "gunks are modules" decision with a capability-level
  rubric.

## Related

- ADR-0001: What is gunk? *(Accepted)*
- ADR-0002: Stack and runtime *(Accepted)*
- ADR-0008: Gunks are modules *(Accepted)*
- ADR-0010: SQLite schema v2 modules *(Accepted)*
- ADR-0011: AI decomposition pipeline and gunk.yml manifest *(Accepted; pipeline superseded here)*
- `docs/tasks/phase-4-standalone-app-and-ai.md`
