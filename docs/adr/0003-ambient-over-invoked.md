# ADR-0003: Ambient over invoked

- **Status:** Accepted
- **Date:** 2026-06-01
- **Deciders:** Mark Kohler

## Context

An earlier draft of gunk's product framing leaned heavily on a CLI: `gunk scan`,
`gunk list`, `gunk extract`, `gunk inject`, and so on. After review, this was
rejected as a primary surface. This ADR captures *why*, so future contributors
(and future-Mark) don't drift back to it.

The core observation: **the value of gunk is realized inside the user's AI
tool, not inside a terminal.** A CLI-first product would mean the user has to:

1. Notice they're about to ask their AI for something they've already built.
2. Switch out of their flow to type a `gunk` command.
3. Manually inject the result into their AI's context.

Steps 1 and 2 are friction; step 3 is impossible across most AI tools today.
A product that requires a user to *remember to use it* before each AI request
will not be used.

## Decision

**Gunk is ambient. The happy-path user types zero gunk commands, ever.**

Concretely:

- Indexing happens automatically when files change in watched directories.
- Classification happens automatically when new projects appear.
- Extraction happens automatically when modules are tagged with confidence.
- Modules are exposed automatically to AI tools via MCP.
- Configuration of AI tools happens once, via a button click in the macOS app.

A CLI exists, but only for:

- **Power users and scripting** (`gunkd status`, `gunkd reindex`, `gunk debug
  module <id>`).
- **Headless / Linux / Windows users** who don't have the macOS app yet.
- **Diagnostics and support** ("send me the output of `gunkd diagnose`").

The CLI is **plumbing**, not product. It is documented under "Advanced" and
never appears in onboarding, marketing, or the launch demo.

## Consequences

### Positive

- **Zero learning curve.** No commands to memorize. No mental model.
- **Compounds with AI tool habits.** Whatever AI tool the user adopts next
  inherits gunk for free, as long as it speaks MCP.
- **Demoable to non-developers.** "Watch this — I ask Cursor for OAuth, and it
  uses my old code instead of writing new code." That demo doesn't require
  explaining a CLI.

### Negative / things we forbid as a result

- **No `gunk init` ceremony.** The macOS app onboarding replaces this. Adding
  it later for "advanced setup" is a smell — onboarding should be the same
  for everyone.
- **No "you forgot to run `gunk update`" UX bugs.** The daemon updates the
  index continuously; staleness must be a daemon bug, not a user bug.
- **No marketing copy that leads with commands.** READMEs, blog posts, and
  launch threads describe gunk in terms of *outcomes* ("your AI uses your old
  code"), not commands.
- **No screenshots of terminals in the launch video.** The visible demo is a
  Cursor session, not a shell.

### What this constrains in design

- The macOS app **must** be able to do everything the user needs (configure
  watched dirs, wire up AI tools, browse modules, approve classifications).
  Anything the app can't do is something the user has to escape to a CLI for,
  which violates this ADR.
- The MCP server **must** require zero ongoing user interaction. Auto-reload
  on store changes; never make the user "restart gunk" to see new modules.

## Revisit triggers

This ADR should be reopened only if user research shows that the ambient model
is *worse* than an explicit-invocation model — for example, if classification
errors cause AI tools to confidently use the wrong module and users want a
"manual mode" to review every reference. In that case the right answer is
probably better confidence thresholds and approval UX in the app, not a CLI
escape hatch — but we'd discuss it.

## Related

- ADR-0001: What is gunk? *(Accepted)*
- ADR-0002: Stack and runtime *(Accepted)*
