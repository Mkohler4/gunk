# ADR-0017: MCP `run_gunk` tool — the agent's execute door

- **Status:** Proposed
- **Date:** 2026-06-16
- **Deciders:** Mark Kohler
- **Phase:** 10 (Run & test modules) — gate **CP-K**

## Context

Phase 10 gives a module two doors to **demonstrate that it works**: the
developer's "Try it" console (T-10.7) and the AI system's MCP tool (T-10.12).
The sandbox runner that backs both landed in
[ADR-0016](0016-sandbox-execution-model.md): an app-side Swift `SmokeRunner`
that copies a bundle into a throwaway run dir, wraps the interpreter in a
deny-by-default `sandbox-exec` (Seatbelt) profile (network off, writes confined
to the run dir, no inherited env, hard timeout), classifies runnability, and
**fails closed** when the sandbox can't be applied.

Until now MCP has been **read-only**: `list_gunks`, `list_sources`,
`search_gunks`, `get_gunk` — four tools that open `~/.gunk/store.db` with
explicit column lists, query, and close (Hard data fact 8). `run_gunk` is the
first **execute** tool, the largest change to the MCP contract since Phase 2.
ADR-0001 frames MCP as the user-visible contract; ADR-0001 also already allows
a power-user **CLI** as "plumbing, not product." Agent-initiated execution of
extracted code is the highest-risk surface in the phase, so it gets its own
ADR.

The user's explicit Phase 10 ask: *"the AI needs to test these modules as
well"* — an agent should be able to verify a brick **works** before it composes
with it (the future-vision "verify before you build" / token-savings story).

## Decision

### 1. One sandbox, two callers — the runner stays app-side Swift

We do **not** fork the sandbox and do **not** reimplement it in TypeScript.
ADR-0016 deliberately put the runner in the Swift app because the isolation
primitive (`sandbox-exec`/Seatbelt) is a macOS facility the app reaches
directly, and keeping it out of the cross-platform engine (ADR-0013) avoids
duplicating spawn/resolve machinery and macOS-specific sandboxing. Moving the
*security-reviewed* sandbox core into the engine now would relitigate that
accepted decision and risk shipping a second, weaker sandbox.

Instead, the Swift app gains a thin **headless `run` verb** (`SmokeRunCLI`)
that constructs a `RunInput` and calls the **same** `SmokeRunner` the GUI
console uses, in **buffered** mode, then prints the `SmokeRunResult` as JSON
and exits — without starting the UI (the same pattern as the existing
`GUNK_RENDER_APPICON` headless export). The MCP `run_gunk` tool spawns this
verb.

```
   GUI "Try it" (T-10.7) ─┐
                          ├─►  SmokeRunner  ─►  sandbox-exec (one Seatbelt profile)
   gunk run  (headless) ──┘            ▲
        ▲                              │
   gunk-mcp run_gunk ──────────────────┘  (spawns `gunk run`, buffered, JSON)
```

There is exactly **one** executor core (`SmokeRunner`), exactly **one** sandbox
profile (`RunSandbox`), and exactly **one** fail-closed posture. The agent path
is a new *caller*, not a new *sandbox*.

**Division of labour.** `run_gunk` (TypeScript) does the store work the way
every other MCP tool does — `openDefaultStore()`, explicit column lists,
`getGunk(id)` — resolves the bundle path, language, entrypoints, and declared
packages from the store + `gunk.yml`, and passes a fully-formed request to the
verb. The Swift side re-derives runnability, re-resolves and re-validates the
entrypoint, and applies the sandbox — so safety is enforced Swift-side
regardless of what the TypeScript caller sends (a poisoned entrypoint is
re-validated and refused after staging, ADR-0016).

**Binary resolution** mirrors the existing `GUNK_*_BIN` convention: `run_gunk`
resolves the verb from `GUNK_RUN_BIN` (explicit path, dev/CI) and otherwise a
`gunk-run` on `PATH`. When it cannot be resolved, the tool returns an honest
typed receipt ("runner not configured") rather than crashing — the agent learns
it cannot run here, the same way a `cannotDetermine` is honest.

### 2. Consent posture — the sandbox *is* the consent for agent runs

The human's first-run consent (T-10.7) is informed consent about running unread
code **on their machine**. There is no human at the keyboard when an agent
calls `run_gunk`, and gating agent runs on a prior *human* per-module consent
would defeat the headline use case (an agent verifying a brick the human has
never opened). So:

- **An agent run does not require a prior human first-run consent**, **but it
  is strictly *more* constrained than a human run.** It is **always** sandboxed
  and the reduced-isolation fallback is **never** available to it
  (`allowReducedFallback = false`, always). On a machine where the sandbox
  cannot be applied, an agent run **fails closed** — it returns a not-run
  receipt, it never silently downgrades to a weaker isolation. The agent
  therefore can never exceed or bypass the sandbox.
- This satisfies "an agent must not be a way to bypass the human first-run
  consent": the consent protects the *machine*, and the sandbox bounds the
  machine's exposure identically (and, for the agent, with no fallback escape
  hatch). The agent cannot reach network, write outside the run dir, read the
  parent's env/secrets, or outlive the timeout — exactly what the consent
  promises a human.
- Agent receipts are tagged `origin = agent`. Per the CP-F coverage decision
  (#8), agent runs **never** count as human-checked evidence and never advance
  the `Ready to connect` sign-off on their own (T-10.11 owns that rule).

### 3. What the tool returns — a buffered receipt, not a live stream

`run_gunk` input: `{ gunkId: integer, input?: string[] }` (`input` is optional
extra argv composed onto the module's command — the module's own arguments,
confined by the sandbox). Output is a single structured receipt:

```jsonc
{
  "gunkId": 7,
  "passed": true,            // ran && exit 0 && !timedOut && terminal-runnable
  "runnability": "terminal-runnable",
  "isolation": "sandbox-exec",
  "exitCode": 0,
  "durationMs": 1840,
  "timedOut": false,
  "command": "python3 main.py",
  "stdout": "…",
  "stderr": "",
  "output": "…"             // combined stdout+stderr, for a one-glance read
}
```

It is **buffered, one-shot** — no incremental streaming (streaming is the GUI
console's shape, T-10.7). A non-`terminal-runnable` module returns the typed
classification (`needs-network`, `cannot-determine`, …) with `passed: false` —
an honest "can't prove it here," **not** an error and **not** a failed run.

The default timeout is **30 s** (ADR-0016). The agent cannot request an
unbounded run; `run_gunk` does not expose the timeout knob and the verb clamps
to a hard ceiling.

### 4. Persistence — return-only this phase (a documented seam)

`run_gunk` is **return-only**: it does **not** write to the store this phase.

The v6 proof tables (`smoke_runs`, `module_examples`) are **app-only** (T-10.3,
Hard data fact 3): the MCP/engine migrators pin `LATEST_VERSION = 4`,
early-return on higher stores, and read with explicit column lists, so v6 is
invisible to MCP. Keeping the MCP contract **read + execute** (not
**write-to-store**) this phase means:

- the **app stays the single owner** of the schema and its migrations — MCP
  never creates or migrates v6, avoiding a write that races or diverges from the
  app's migration;
- the first execute tool ships **minimal** and reviewable.

The future-vision note ("verified state must eventually surface over MCP") is
preserved as a **seam, not built now**: a later task can add a *guarded* write
that inserts an `origin = agent` receipt **only when the v6 tables already
exist** (never migrating), so human + agent evidence share the coverage
readout. This ADR explicitly leaves that for a follow-up.

### What this ADR does **not** decide

- No streaming over MCP (buffered only).
- No MCP store writes (return-only; the write is a documented future seam).
- No new isolation model — it reuses ADR-0016 wholesale.
- No coverage/sign-off changes (T-10.11 owns how agent receipts read).

## Consequences

### Positive

- **One sandbox, two callers.** The agent earns evidence through the exact
  Seatbelt boundary the human does — no second, weaker runner to audit.
- The agent path is **strictly more constrained** than the human path (no
  reduced-isolation fallback), so "an agent run is safe" follows directly from
  "a human run is safe."
- MCP stays **read + execute**, not write — the smallest honest expansion of
  the contract, with the store-sharing left as an explicit seam.
- `run_gunk` returns an honest pass/fail/can't-determine receipt an agent can
  act on before it composes with a brick.

### Negative

- The agent path depends on a resolvable `gunk-run` verb (the Swift app /
  `GUNK_RUN_BIN`); when it is absent the tool is honestly unavailable rather
  than functional. CP-K wires this into the real environment.
- Spawning a subprocess per `run_gunk` call is heavier than an in-process call,
  but a smoke run already spawns an interpreter — the extra hop is negligible
  next to the run itself.
- Human + agent evidence do **not** yet accumulate in one store (return-only).
  Accepted for this phase; the seam is documented.

## Alternatives considered

- **Reimplement the sandbox in the engine (`gunk-engine run`).** Rejected: it
  relitigates ADR-0016, pushes macOS Seatbelt into the cross-platform engine,
  and risks a second sandbox to keep in sync. The refining-loop's "prefer
  moving the core into the engine" is overridden by the stronger rule *do not
  fork the sandbox* — calling the existing reviewed Swift core honors that
  better than porting it.
- **Require prior human first-run consent for agent runs.** Rejected: defeats
  "verify a brick the human hasn't opened," and the sandbox already bounds the
  machine's exposure. The agent is instead made *more* constrained (no
  fallback).
- **Write agent receipts to the store now.** Deferred: would force MCP to know
  the v6 schema and risks dueling migrators. Left as a guarded future seam.
- **Stream output over MCP.** Rejected for this phase: buffered receipts match
  how an agent consumes a verification; streaming is the GUI console's job.

## Related

- ADR-0001: What is gunk? (MCP is the contract; a CLI is plumbing) *(Accepted)*
- ADR-0016: Sandbox execution model *(Accepted)* — the one sandbox this reuses
- `docs/tasks/phase-10-run-and-test-modules.md` — T-10.12, CP-K
