# Phase 11 retro: Settings v2 (the spend & trust panel)

Phase 11 turned Settings from a compact debug form into the place that answers
three trust questions: which provider/key/model will gunk use, what has
decomposition spend *estimated* to, and where does the Approval threshold
actually bite? The important line held: cost is derived from token counts at
presentation time, never stored as truth.

Task breakdown:
[docs/tasks/phase-11-settings-v2.md](../tasks/phase-11-settings-v2.md)
(T-11.1-T-11.10, checkpoints CP-L-CP-P). Design source of truth:
[settings-v2](../design/explorations/settings-v2.md). The price-table
representation is recorded in T-11.2 and in the `PRICES` note beside
`PriceTable.current`; CP-M did not require promoting it to a full ADR.

## What Shipped

- **Settings v2 IA**: the page now has a left rail for Provider & keys, Local
  model, Spend, Processing, and Pipeline health, with MCP deep links landing on
  Pipeline health instead of a generic settings form.
- **Estimated spend**: the app restored `listLLMRuns()` /
  `llmRunsForSource(_:)` and added provider/model aggregation for
  `llm_runs`. Spend rows show real input/output tokens, `EST` dollar values
  only when a price is known, a price-table version/as-of stamp, and `—` for
  unknown hosted prices. Ollama/local rows are known free rows, not unknowns.
- **Price table and estimator**: Phase 11 added a versioned in-repo static
  table for the live provider set, plus pure estimation tests. The table is not
  SQLite, and `cost_usd` remains presentation-inert.
- **Provider keys**: OpenAI and Anthropic can be managed side by side with
  add/edit/remove/test actions. Keys remain in Keychain, and each provider
  remembers its model so switching the active provider does not clobber custom
  model text.
- **Ollama settings**: Local model configuration now has host/base URL, model,
  reachability states, and a no-key local treatment. In-app checks honor the
  configured host.
- **Processing trust controls**: the confidence threshold is labelled as the
  Approval to Auto-accept gate, and the Library approval queue/sidebar badge now
  follow the user's `llm.confidenceThreshold` instead of a hard-coded `0.7`.
  The cost cap stretch shipped as warn-only and estimate-based.

## What Slipped

- **Actual billed cost reconciliation** stayed out, by design. The spend panel
  is a receipt from stored decomposition token counts, not a provider billing
  dashboard.
- **Ollama custom host parity with engine decomposition** is not complete.
  App-side checks and module analysis use the configured base URL; new
  decompositions still rely on the engine's built-in Ollama host
  `localhost:11434` until engine support is deliberately unlocked in a later
  phase.
- **CP-P remains Mark's real-store walkthrough**. The debug fixtures cover the
  UI states, but the final trust check is still opening Mark's real store and
  confirming the spend rows match his data.

## What We Learned

- The `cost_usd` column needed louder framing, not more plumbing. Keeping it
  NULL while deriving estimates from token counts made the UI more honest than
  reviving the old meter.
- Price staleness is a product state. A version/as-of stamp is enough for this
  phase; blocking on stale prices would make the app feel more precise than the
  data actually is.
- Settings is a better home for trust details than the app shell. Provider
  keys, MCP setup, price provenance, threshold behavior, and local-model health
  all need a little room to be understood.
- Debug staging hooks paid for themselves. Spend unknown/empty/local states,
  Ollama reachability, cost-cap states, provider-key editing, and MCP deep-link
  arrival can be captured without mutating a real Keychain or real store.

## What Remains

- Mark's CP-P walkthrough on real data: verify token totals, unknown-price
  treatment, Keychain behavior, Ollama reachability, threshold behavior, and
  the MCP deep-link row.
- A future engine task can thread the configured Ollama base URL into
  decomposition. Phase 11 intentionally did not reopen `engine/`.
- A future provider/catalog phase can add Google/Gemini when there is a real
  client; Phase 11 intentionally omitted disabled or pretend provider rows.
- If price sourcing becomes contentious, promote the T-11.2 write-up to an ADR.
  For now the task doc plus in-code `PRICES` note are enough.

## Close-Out Notes

`rg` found no Phase 11 orphan matching the old "kept for reuse" pattern. The
only cleanup was documentation/comment drift: README and CHANGELOG now reflect
that the LLM run read APIs exist again, the roadmap marks Phase 11 complete,
and the hosted-model switcher comment no longer points to pre-Settings-v2
Ollama UX. The Phase 11 re-freeze held for this cleanup: no schema migration,
no `engine/` change, and no `mcp/` change.
