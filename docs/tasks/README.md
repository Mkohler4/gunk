# Task specs

This directory holds **structured task lists** designed to be executed by
coding agents (especially [OpenAI Codex](https://openai.com/codex)) one task
at a time, slowly and deliberately, with strong testing and documentation
discipline.

## Why this format exists

We don't ask Codex (or any agent) to "build Phase 2." We ask it to "build
**T-2.5**." Every task is small enough to be one PR, has explicit
prerequisites, lists the exact files it touches, and defines a hard
acceptance bar before it can be marked done.

This format is opinionated:

- **One task = one PR.** Small, focused, reviewable.
- **Tasks are ordered.** Prerequisites are explicit. Don't start T-2.6
  before T-2.5 is merged.
- **Every task ships tests.** "Tests required" is non-negotiable. If a
  test would be hard to write, we revise the task, not the bar.
- **Every task ships docs.** CHANGELOG entry, roadmap checkbox, and
  package-level README updates as appropriate.
- **MCP touchpoints are explicit.** Per ADR-0001, MCP is the user-visible
  contract. Every task notes whether it changes the MCP surface.
- **The spec is a stable reference.** Codex does not modify task specs
  while executing them — it logs progress in `CHANGELOG.md` and ticks
  boxes in `docs/roadmap.md`. The spec stays canonical.

## File layout

| File                          | Purpose                                             |
|-------------------------------|-----------------------------------------------------|
| `README.md`                   | This file. Format and conventions.                  |
| `codex-prompt.md`             | The exact prompt to paste into Codex per task.      |
| `phase-N-<slug>.md`           | Task list for one phase of the roadmap.             |

We add a new `phase-N-<slug>.md` file when the previous phase is merged.
We don't write task specs for phases we haven't reached yet — they will
inevitably be wrong by the time we get to them.

## Task structure

Every task in a phase file follows the same shape:

```markdown
### T-N.M — <short title>

**Status:** Not started | In progress | Done | Cancelled
**Owner:** Codex | Mark | <other>

#### Goal
One sentence describing the user-visible (or developer-visible) outcome.

#### Why
1–2 sentences linking the task to an ADR or roadmap principle.

#### Prerequisites
List of T-x.y task IDs that must be merged before this can start.

#### Files
Bullet list of paths to create or modify. Be explicit.

#### Execution steps
Numbered, atomic, ordered. Each step should be a small, verifiable action.

#### MCP touchpoints
What this task does or doesn't change about the MCP surface.

#### Tests required
A checklist of named test cases that must exist and pass.

#### Execution objective
What concretely happens when the code runs at the end of this task.

#### Definition of done
A checklist combining tests, docs, CI green, and PR conventions.
```

## Conventions

### Conventional Commits + package scope

- `feat(mcp): add list_gunks tool`
- `feat(app): add drop zone view`
- `fix(mcp): handle missing store.db gracefully`
- `chore: update CHANGELOG`
- `docs: capture decision in ADR-0006`

### Branch naming

- One branch per task: `task/T-2.5-sqlite-schema-v0`
- Branch off `main`, target `main` in the PR.

### PR titles

Match the conventional commit subject. PR body must link back to the task
ID and include the "Definition of done" checklist copied from the spec,
ticked.

### When to write a new ADR

A task may require a sub-decision that is hard to reverse (e.g., "what
fields are in the schema?"). When that happens, the task lists a new ADR
file in its `Files` section and references it in `Definition of done`.
Existing ADRs are append-only — never edit an Accepted ADR; supersede it.

### When tests are genuinely hard

If a test that the spec asks for turns out to be impossible or wildly
disproportionate to the work (e.g., requires a specific OS UI state),
the agent stops, documents what it tried, and proposes either a lower-bar
test or a follow-up integration test. **The agent does not skip the test
and mark the task done.**

## Running a task in Codex

See [`codex-prompt.md`](codex-prompt.md) for the exact prompt to use.

The short version: paste the prompt into Codex with the task ID filled in.
Codex reads the spec, the ADRs, and the relevant existing code, then
implements the task, writes the tests, opens a PR, and reports.
