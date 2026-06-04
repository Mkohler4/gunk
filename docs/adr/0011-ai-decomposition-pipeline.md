# ADR-0011: AI decomposition pipeline and gunk.yml manifest

- **Status:** Accepted
- **Date:** 2026-06-04
- **Deciders:** Mark Kohler

## Context

ADR-0008 defines a gunk as an extracted reusable module, not a dropped
folder. ADR-0010 defines the schema that stores sources, module-level gunks,
tags, file membership, bundle paths, manifest paths, and LLM run accounting.
The remaining Phase 3 work needs a shared contract for how the Swift app turns
a dropped source into those rows and into a physical bundle.

SQLite remains the shared app/MCP contract (ADR-0002), and the app remains the
only writer. That means the AI pipeline must run inside `gunk.app` at
drop-time, write deterministic store rows, and produce a manifest shape that
`gunk-mcp` can later return without making its own product decisions.

The original Phase 3 task document called this ADR-0010, but ADR-0010 is
already accepted on `main` for schema v2. This ADR records the same AI
pipeline decision as ADR-0011 to preserve append-only ADR numbering.

## Decision

The AI decomposition pipeline runs in-process in the Swift app at drop-time.
The app scans the source, builds a token-budgeted source representation, calls
an injected LLM client for structured output, validates the response, persists
module rows, and extracts approved modules into portable bundles.

### LLM client abstraction

`gunk.app` exposes a provider-agnostic LLM client protocol. The first provider
implementations are:

- OpenAI
- Anthropic
- Ollama for local models

Every provider implementation must support structured JSON output. Hosted
provider API keys are stored in Keychain, never in SQLite or plaintext files.
Tests inject fake clients and fake secret stores so CI never touches live
network APIs or the real user Keychain.

### Decomposition contract

The decomposition input is a token-budgeted source representation assembled by
the app. It contains:

- a source summary with project markers and detected language hints
- a file tree of scanned, non-ignored files
- selected file contents and signatures prioritized within the token budget
- the allowed tag taxonomy from the store

The LLM output is structured JSON with this shape:

```json
{
  "modules": [
    {
      "name": "string",
      "purpose": "string",
      "tags": ["auth"],
      "files": ["relative/path.ts"],
      "language": "TypeScript",
      "confidence": 0.86
    }
  ]
}
```

Rules:

- `tags` must come from the seeded taxonomy: `auth`, `payments`, `ui-kit`,
  `scraper`, `dashboard`, `cli`, `api`, `db-layer`, `email`, `search`.
- `files` must be relative paths that came from the scanner. Modules that cite
  nonexistent files are rejected.
- `confidence` is clamped to `0...1`.
- Token usage and estimated USD cost are recorded in `llm_runs`.

### Confidence threshold and approval

The default auto-extraction threshold is **0.7**.

Modules with confidence greater than or equal to the threshold are extracted
automatically. Modules below the threshold are persisted for review but remain
in the approval queue until the user approves or rejects them. Approval sets
`approved_at` and then runs extraction.

### gunk.yml manifest spec v0

Each extracted bundle contains a `gunk.yml` manifest at its root. Manifest v0
has this shape:

```yaml
schema_version: 0
id: 0
name: string
tags:
  - auth
language: string
purpose: string
deps:
  package_managers:
    - npm
  packages:
    - name: string
      version: string
entrypoints:
  - path: relative/path.ts
    symbol: optionalSymbolName
provenance:
  source_path: ~/Documents/source-project
  source_commit: abc1234
license:
  detected: MIT
  warning: null
confidence: 0.86
extracted_at: "2026-06-04T18:00:00Z"
redactions:
  - path: relative/path.ts
    reason: high_entropy_secret
```

Required fields:

- `schema_version`
- `id`
- `name`
- `tags`
- `language`
- `purpose`
- `deps`
- `entrypoints`
- `provenance`
- `license`
- `confidence`
- `extracted_at`

Optional but allowed fields:

- `redactions`

`deps.package_managers`, `deps.packages`, and `entrypoints` may be empty lists
when the pipeline cannot infer them confidently. `provenance.source_commit`
may be `null` when the source is not a git repository or the commit cannot be
read locally.

Worked example:

```yaml
schema_version: 0
id: 42
name: google-oauth-flow
tags:
  - auth
  - api
language: TypeScript
purpose: Implements Google OAuth callback handling and session exchange.
deps:
  package_managers:
    - npm
  packages:
    - name: next-auth
      version: "^5.0.0"
entrypoints:
  - path: app/api/auth/[...nextauth]/route.ts
    symbol: GET
provenance:
  source_path: ~/Documents/old-saas
  source_commit: 8f3a91c
license:
  detected: MIT
  warning: null
confidence: 0.91
extracted_at: "2026-06-04T18:00:00Z"
redactions: []
```

### Secret safety

Extraction must never copy likely-secret files into a bundle. The scanner and
extractor both enforce this rule as defense in depth.

Likely-secret file names and patterns include:

- `.env*`
- `*.pem`
- `*.key`
- `id_rsa`
- `id_rsa*`
- `credentials*`
- `*.p12`
- `*.pfx`
- token files and provider credential exports

The extractor must also scan copied file contents for known key prefixes and
high-entropy secrets, including examples such as `AKIA`, `sk-`, and PEM private
key blocks. If a match is found, the extractor skips the file or redacts the
matched line before it reaches the bundle, and records the action in
`redactions`.

### Provenance privacy

Manifest provenance stores source paths relative to the user home, for example
`~/Documents/old-saas`. It must never store a raw absolute path with the
username. It also omits git remote URLs. If the source is a git repository,
the manifest may store only the short commit hash.

### License stance

Licenses are flagged, not blocked. The extractor records the detected source
license. If a restrictive license such as GPL is detected, the manifest sets
`license.warning` and the UI surfaces the warning. Gunk does not silently
relicense copied code.

### Deferred

Tree-sitter symbol-graph file selection is deferred. Embeddings-based search is
also deferred. Phase 3 ships deterministic scan/context building and tag/text
search before those refinements.

## Consequences

### Positive

- The app, extractor, Browse UI, and MCP tools share one module contract.
- Hosted and local LLM providers are implementation details behind one Swift
  protocol.
- The confidence threshold gives gunk a safe default while preserving a path
  for lower-confidence modules via review.
- Bundles are portable and inspectable because each one carries a manifest,
  provenance, license, and redaction record.
- Secret and provenance rules are explicit before any file-copying code lands.

### Negative

- The pipeline is now central product code and will need careful fixtures,
  mocks, and manual smoke tests.
- Structured-output support differs across providers, so provider adapters must
  normalize request and response behavior.
- Secret detection can produce false positives and skip useful files. The
  product accepts that trade-off because leaking secrets is worse than missing
  a file.
- License detection is advisory; users still need judgment when reusing code
  from restrictive sources.

### Constraints this locks in

- AI processing runs in `gunk.app`, not in `gunk-mcp`.
- LLM clients must be injectable and structured-output capable.
- The default auto-extraction threshold is `0.7`.
- Extracted bundles live under `~/.gunk/modules/<gunk_id>/` by default, with
  an injectable root for tests.
- `gunk.yml` manifest v0 is the bundle contract consumed by later MCP tools.
- Secret-named files and detected secret contents must not reach bundles.
- Manifest provenance uses home-relative paths and omits git remotes.

## Supersedes / amends

- Implements ADR-0008's module-level product noun.
- Builds on ADR-0010's schema v2 fields for `gunks`, `gunk_files`, and
  `llm_runs`.
- Amends ADR-0002 by specifying that AI processing is app-side writer logic,
  while MCP remains read-only.

## Related

- ADR-0002: Stack and runtime *(Accepted)*
- ADR-0008: Gunks are modules *(Accepted)*
- ADR-0009: Dock recycling-bin surface *(Accepted)*
- ADR-0010: SQLite schema v2 modules *(Accepted)*
- `docs/tasks/phase-3-ai-decomposition.md`
