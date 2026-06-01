# Codex prompt template

Paste this into Codex (or any structured coding agent) to execute a single
task from a task spec. Replace `<TASK_ID>` (e.g. `T-2.5`) and the phase
file path with the right values.

---

## The prompt

```
You are working on the gunk project at https://github.com/Mkohler4/gunk.

PROJECT CONTEXT (read these files first, in order):
1. README.md
2. docs/roadmap.md
3. docs/adr/0001-what-is-gunk.md
4. docs/adr/0002-stack-and-runtime.md
5. docs/adr/0003-ambient-over-invoked.md
6. docs/adr/0004-drag-in-over-file-watch.md
7. docs/adr/0005-monorepo-layout.md
8. docs/tasks/README.md
9. docs/tasks/phase-2-walking-skeleton.md

YOUR TASK: implement task <TASK_ID> from
docs/tasks/phase-2-walking-skeleton.md.

PROCESS:
1. Re-read the task spec carefully. Note its prerequisites, files,
   execution steps, MCP touchpoints, tests required, and definition
   of done.
2. Confirm all prerequisite task IDs are merged into main before
   starting. If any are not, stop and report.
3. Create a feature branch: `task/<TASK_ID>-<short-slug>`.
4. Implement the execution steps in order. Make the smallest, most
   focused change for each step.
5. Write all listed tests. They must pass before the task is done.
6. Update the listed documentation files. Tick the boxes in
   "Definition of done" only when each is genuinely true.
7. Run the full test suite for both packages:
   - `cd mcp && bun test`
   - `cd app && swift test`
8. Run lint and typecheck:
   - `cd mcp && bun run lint && bun run typecheck`
9. Commit using Conventional Commits format with package scope (e.g.
   `feat(mcp): ...`, `feat(app): ...`, `chore: ...`). One logical
   change per commit; if the task naturally splits, multiple commits
   are fine.
10. Push the branch and open a draft PR. PR body must:
    - Link to <TASK_ID>.
    - Copy and tick the "Definition of done" checklist.
    - Note any deviations from the spec and why.
11. Report: test output, files changed, PR URL.

CONSTRAINTS:
- Do NOT exceed the scope of <TASK_ID>. If you find work that belongs
  to a later task, stop and note it in the PR body under "Out of scope
  but observed."
- Do NOT skip tests. If a test is impossible or disproportionate,
  stop and propose an alternative; do not mark the task done.
- Do NOT modify accepted ADRs. They are append-only. If architecture
  must change, propose a new ADR superseding the old one.
- Do NOT modify the task spec file itself. Progress is logged in
  CHANGELOG.md and ticked in docs/roadmap.md.
- Stay aligned with all accepted ADRs (0001 through 0005, plus any
  added since this prompt was written).
- Never grant the macOS app Full Disk Access. Per ADR-0004, gunk only
  knows about folders the user explicitly drops on it.

OUTPUT:
A summary of what you did, the test output (last 20 lines), the
commit subjects, and the PR URL.
```

---

## How this prompt is intentionally constrained

- **It refuses to skip tests.** Codex tends to "ship" by reducing the
  test bar when it gets stuck. The constraint forces it to surface
  the problem instead.
- **It refuses to mutate the task spec.** Otherwise Codex tends to
  rewrite the spec to match what it built, defeating the purpose.
- **It enforces small scope.** "Do NOT exceed the scope" prevents the
  classic agent failure mode of finishing T-2.5 *and* starting T-2.6
  in the same PR.
- **It enforces conventional commits.** Otherwise we lose the
  release-please / changelog automation downstream.
- **It enforces ADR discipline.** Codex is allowed to *propose* a new
  ADR but not edit an existing one.

## Variants

### "Just diagnose, don't implement"
Replace `YOUR TASK: implement <TASK_ID>...` with:

```
YOUR TASK: read <TASK_ID> in
docs/tasks/phase-2-walking-skeleton.md and produce a 1-page
implementation plan. Do not write any code. List the files you
would create, the order of execution steps, and any open
questions about the spec.
```

Use this when you want a sanity check before letting Codex burn
through a task autonomously.

### "Resume a partial task"
If a task has commits but isn't merged, prepend:

```
The task <TASK_ID> was partially started on branch <BRANCH_NAME>.
Read its commits with `git log <BRANCH_NAME>` and continue from
where it left off. Do not redo completed steps.
```
