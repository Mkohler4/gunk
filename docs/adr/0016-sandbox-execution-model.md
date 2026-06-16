# ADR-0016: Sandbox execution model for smoke runs

- **Status:** Accepted
- **Date:** 2026-06-15
- **Deciders:** Mark Kohler
- **Phase:** 10 (Run & test modules) — gate **CP-G**

## Context

Phase 10 lets a module **demonstrate that it works** to two audiences — the
developer (T-10.7 "Try it") and the AI system (T-10.12 MCP `run_gunk`). Both
doors call one engine: a runner that executes a module's entrypoint against
its extracted bundle and captures a structured result.

Nothing executes a module today (Hard data fact 1). The only existing code
execution is the optional build-verify compile check
(`engine/src/extract/buildVerify.ts`), which copies a bundle into a throwaway
`mkdtempSync` directory and `spawnSync`s a compiler with a timeout. That is
the nearest pattern, but build-verify only *compiles*; smoke runs *execute
arbitrary extracted code*, so the isolation bar is far higher.

This is the riskiest, highest-leverage piece of the phase. Executing
extracted code on the user's machine — code the user did not write and may
not have read — demands a hard, stated boundary, not a best-effort one. The
model is security-sensitive and hard to reverse (it shapes the consent copy,
the MCP contract, and what "we ran it safely" means), so it gets its own ADR.

### Constraints that shaped the decision

- The app is a native macOS app (ADR-0015) that already spawns subprocesses
  via `Process()` (`EngineLauncher`, Hard data fact 9). The runner follows
  that spawn/resolve pattern but adds the isolation those launchers lack.
- The design (CP-F, [module-run-v2.md](../design/explorations/module-run-v2.md))
  scopes this phase to **terminal/CLI/library one-shot** modules only.
  Everything else must be **classified** as not-runnable-here and **not
  executed** — the page renders that as a neutral state, never a failure.
- The promise must be stateable in one sentence at first-run consent:
  *throwaway copy, no network, time-boxed, writes stay inside the run
  directory, secrets never echoed.*

## Decision

### Home: app-side Swift

The runner lives in the Swift app
(`app/Sources/GunkApp/Run/`), not as an engine subcommand. The isolation
primitive is a **macOS sandbox profile** applied per child process, which the
Swift app reaches most directly (it already owns process spawning and the
`~/.gunk` paths). The engine stays analysis/decomposition only (ADR-0013);
adding code-execution-with-isolation there would duplicate the spawn/resolve
machinery and push macOS-specific sandboxing into a cross-platform engine.

### Isolation primitive: `sandbox-exec` (Seatbelt), with a documented fallback

Each run is wrapped in `/usr/bin/sandbox-exec -p <profile> -- <command>`. The
generated Seatbelt profile is **deny-by-default**:

- `(deny default)` — nothing is allowed unless explicitly granted.
- `(allow process-fork) (allow process-exec*)` — the interpreter must spawn.
- `(allow file-read*)` — read access (interpreters need to read their own
  runtime, libraries, and the bundle). Reads are not the threat; writes and
  network are.
- `(allow file-write* (subpath "<runDir>"))` plus the OS temp dir and
  `/dev/null` + tty — **writes are confined to the run directory**. No write
  anywhere else on the filesystem, including the user's source.
- `(deny network*)` — **network is off.** No outbound or inbound sockets.
- `(deny mach-lookup)` is *not* added wholesale (it breaks interpreter
  startup on some systems); the network + write denials are the load-bearing
  guarantees.

`sandbox-exec` is deprecated by Apple but present and functional on current
macOS, and it is the only userspace-applyable Seatbelt entry point. **It does
not nest** — applying a profile inside an already-sandboxed process fails
with `sandbox_apply: Operation not permitted` (observed when the build agent
itself runs sandboxed). The runner detects this and surfaces it rather than
silently running unsandboxed.

**Fallback (documented, not preferred):** if `sandbox-exec` is unavailable or
the App-Sandbox/notarization path forbids it, the runner falls back to a
**constrained `Process`** — no network entitlement, working directory pinned
to the run dir, the same hard timeout — and **labels the run as reduced
isolation**. An *unbounded* `Process` (network on, unscoped writes, no
timeout) is **never acceptable**: the runner refuses to run rather than run
unbounded.

### The run directory

Each run copies the bundle into a throwaway directory under
`~/.gunk/runs/smoke/<gunkId>/<timestamp>/` and executes there. The copy is
the only writable location. On completion the captured output is kept and the
temp copy is dropped (unless an output artifact must persist). This mirrors
build-verify's `mkdtempSync` copy but pins the location under `~/.gunk` for
inspectability.

**Future-vision seam (do not build now):** the copy/resolve step is shaped so
it can later become "copy the bundle **+ its resolved gunk-deps**" for
parent-gunk composition. The runner takes a *bundle to stage* and a *resolved
entrypoint*, neither of which hard-codes the single-bundle assumption. This
phase copies one self-contained bundle.

### Runnability classification (gates execution)

Before any execution the runner classifies the module into exactly one of:

- `terminalRunnable` — a one-shot CLI/library entrypoint. **The only class
  this phase executes.**
- `needsNetwork` — manifest/framework signals an outbound API/network job.
- `needsSecrets` — requires credentials/env not present in the sandbox.
- `interactiveStdin` — a CLI that prompts and reads stdin.
- `longRunning` — a server/watcher/TUI that does not terminate.
- `uiModule` — output *is* a UI surface (deferred, T-10.13).
- `cannotDetermine` — gunk cannot confidently derive how to run it.

Classification keys off **language**, **entrypoint shape** (path + optional
symbol, Hard data fact 4), the **parsed dependency manifest** (Hard data
fact 5), and framework hints. **When unsure, it prefers a not-runnable-here
reason over a wrong guess.** A non-`terminalRunnable` class is returned on the
result and **never auto-run**. Supported interpreters this phase: **Python**
(`python3 <entry>`) and **Node** (`node <entry>`); other languages without a
confident one-shot command return `cannotDetermine`.

### The result type

```
SmokeRunResult {
  runnability: Runnability        // the classification above
  command: String?                // the resolved command (nil if not run)
  exitCode: Int32?                // nil if not run
  stdout: String
  stderr: String
  durationMs: Int
  timedOut: Bool
  outputArtifacts: [URL]          // new files left inside the run dir
  startedAt: Date
  isolation: Isolation            // .sandboxExec | .reducedFallback | .notRun
}
```

Two consumption shapes share **one executor core**:

- **Streaming** — incremental stdout/stderr for the live console (T-10.7),
  emitted as an `AsyncThrowingStream` of events.
- **Buffered** — a single awaited `SmokeRunResult` for the MCP tool (T-10.12).

The default timeout is **30 seconds**. `timedOut` is reported as a fact, not
an error (a long-running module is a *classification*, not a failed run).

### What this ADR does **not** decide

- No store writes (T-10.3 / CP-H).
- No UI (T-10.4+).
- No MCP wiring (T-10.12 / its own ADR).
- No golden-diff semantics (T-10.9, recorded in the CP-F design doc).

## Consequences

### Positive

- Executing extracted code carries a hard, stated boundary: throwaway copy,
  no network, time-boxed, writes confined, secrets not echoed. The consent
  copy can promise exactly what the runner enforces.
- One executor core backs both the human console and the agent's MCP tool, so
  both audiences earn evidence the same way.
- The classifier makes "we won't pretend to run this" a first-class, honest
  result rather than a crash or a wrong guess.
- The copy/resolve and entrypoint-resolution seams stay open for future
  parent-gunk composition without committing to it now.

### Negative

- `sandbox-exec` is deprecated; a future macOS could remove it, forcing the
  documented fallback (or a new primitive). The fallback is weaker isolation
  and is labeled as such.
- Seatbelt profiles are finicky — too tight breaks interpreter startup, too
  loose weakens the promise. The profile is unit-tested and the live-sandbox
  path is integration-tested where the environment permits applying it.
- The runner cannot nest under an already-sandboxed parent; CI/agents that
  run sandboxed must skip the live-sandbox integration tests (the pure logic
  — classification, command resolution, profile generation — is always
  tested).
- Network egress cannot be exhaustively proven in a network-restricted CI;
  the profile's `(deny network*)` is asserted structurally and the
  *enforcement* of the profile is proven by the filesystem-scope test (a
  write outside the run dir is denied), which exercises the same Seatbelt
  application path.

## Alternatives considered

- **Engine subcommand (`gunk-engine run`).** Rejected as the home: it would
  push macOS sandbox primitives into the cross-platform engine and duplicate
  the app's spawn/resolve. The engine stays analysis-only (ADR-0013).
- **No isolation, constrained `Process` only.** Rejected as the *primary*
  path: executing unread extracted code with network on and unscoped writes
  is not an acceptable default. Kept only as a labeled fallback.
- **Containers / VMs (Docker, `container`, a Linux VM).** Rejected for this
  phase: a heavy dependency and a poor fit for "click Try it and see it run
  in 30s" on a developer's Mac. Revisit if Seatbelt is removed.
