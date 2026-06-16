# Architecture Decision Records

We use lightweight ADRs to capture the *why* behind significant decisions. One short
markdown file per decision, numbered sequentially, never deleted (only superseded).

## Index

| #     | Title                                                | Status   |
|-------|------------------------------------------------------|----------|
| 0001  | What is gunk?                                        | Accepted |
| 0002  | Stack and runtime                                    | Accepted |
| 0003  | Ambient over invoked                                 | Accepted |
| 0004  | Drag-in over file-watch                              | Accepted |
| 0005  | Monorepo layout                                      | Accepted |
| 0006  | SQLite schema v0                                     | Accepted |
| 0007  | SQLite schema v1 tags                                | Accepted |
| 0008  | Gunks are modules                                    | Accepted |
| 0009  | Dock recycling-bin surface                           | Accepted |
| 0010  | SQLite schema v2 modules                             | Accepted |
| 0011  | AI decomposition pipeline and gunk.yml manifest      | Accepted |
| 0012  | Capability-centric decomposition                     | Accepted |
| 0013  | AI pipeline moves to a TS/Bun engine                 | Accepted |
| 0014  | Multi-language coverage and verification             | Accepted |
| 0015  | Full macOS app first                                 | Accepted |
| 0016  | Sandbox execution model for smoke runs               | Accepted |
| 0017  | MCP `run_gunk` tool — the agent's execute door        | Proposed |

## Format

Each ADR follows the same shape:

- **Status** — Proposed / Accepted / Superseded by ADR-XXXX
- **Context** — what's the situation that demands a decision?
- **Decision** — what did we choose?
- **Consequences** — what follows from this, both good and bad?

When an ADR is superseded, mark it as such and link forward to the new one. Don't
edit the original — the *why* of past mistakes is as valuable as the *why* of
current choices.

## When to write an ADR

Write one when a decision:

- Is hard to reverse (language, license, schema shape, public API).
- Will be questioned again in 6 months ("why did we…?").
- Closed off plausible alternatives (we chose A *over* B and C).

Don't write one for routine implementation choices.
