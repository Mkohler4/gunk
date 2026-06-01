# Architecture Decision Records

We use lightweight ADRs to capture the *why* behind significant decisions. One short
markdown file per decision, numbered sequentially, never deleted (only superseded).

## Index

| #     | Title                          | Status   |
|-------|--------------------------------|----------|
| 0001  | What is gunk?                  | Accepted |
| 0002  | Stack and runtime              | Accepted |
| 0003  | Ambient over invoked           | Accepted |
| 0004  | Drag-in over file-watch        | Accepted |
| 0005  | Monorepo layout                | Accepted |

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
