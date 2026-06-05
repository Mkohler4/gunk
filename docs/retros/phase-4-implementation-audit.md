# Phase 4 implementation audit

Date: 2026-06-05

This audit compares the current Phase 4 branch stack against
`docs/tasks/phase-4-standalone-app-and-ai.md`.

## Current state

- The Phase 4 task spec file is present locally again, but is currently
  untracked. It should be committed so the task list remains the source of truth.
- `origin/main` is current through T-4.4.
- T-4.5 through T-4.12 are implemented in the stacked Phase 4 PR chain.
- T-4.13 is implemented in PR #93 on top of T-4.12.
- T-4.14 is not started.

## Task status

| Task | Spec item | Current status |
| --- | --- | --- |
| T-4.0 | ADR-0012 capability-centric decomposition | Done, merged to `main` via PR #74. |
| T-4.1 | Eval harness + fixtures + baseline | Done, merged to `main` via PR #76. |
| T-4.2 | Tree-sitter symbol extraction | Done, merged to `main` via PR #78. |
| T-4.3 | Code graph builder | Done, merged to `main` via PR #79. |
| T-4.4 | Capability fingerprinting | Done, merged to `main` via PR #83. |
| T-4.5 | Structural repo-map context builder | Done in stacked PR #84; not yet on `main` until the stack lands. |
| T-4.6 | Capability survey pass | Done in stacked PR #85; not yet on `main`. |
| T-4.7 | Capability expansion | Done in stacked PR #87; not yet on `main`. |
| T-4.8 | Capability refinement pass | Done in stacked PR #88; not yet on `main`. |
| T-4.9 | Real-module quality gates | Done in stacked PR #89; not yet on `main`. |
| T-4.10 | Orchestrator pipeline | Done in stacked PR #90; not yet on `main`. |
| T-4.11 | Eval gate beats baseline | Done in stacked PR #91; not yet on `main`. |
| T-4.12 | Local semantic index + MCP semantic search | Done in stacked PR #92; not yet on `main`. |
| T-4.13 | Cross-source dedup / canonical modules | Done in open PR #93; not yet merged. |
| T-4.14 | Demo + retro + roadmap renumber | Not started. |

## Phase checklist status

- All tasks merged to `main`: no. T-4.5 through T-4.13 are still stacked/off-main.
- No UI changes: yes for the current T-4.5 through T-4.13 stack; no SwiftUI view
  files are changed by the stack.
- ADR-0012 accepted and indexed: yes.
- Structure-grounded pipeline: yes in the stack.
- Quality gates reject non-modules: yes in the stack, covered by tests.
- Eval scorecard beats Phase 3 baseline: yes in the stack, covered by tests.
- Real-project demo: not done.
- Semantic `search_gunks`: yes in the stack.
- Cross-source duplicate recorded and exposed via MCP: yes in PR #93, covered by tests.
- Demo recorded / Friday thread: not done.

## Implemented outside the exact task text

- T-4.13 exposes `canonicalGunkId` and `variantCount` through `search_gunks`
  summaries as well as `list_gunks` and `get_gunk`. The task only explicitly
  named list/get, but the shared MCP summary made search exposure automatic and
  consistent.
- T-4.12/T-4.13 embedding and dedup after extraction are best-effort in the
  processing pipeline. If Ollama embedding or dedup fails, extraction still
  succeeds. The task spec does not define this failure policy.
- T-4.13 stores cluster membership in `gunk_clusters` and derives "built N
  times" with a count query, rather than denormalizing a variant-count column.
  This matches the allowed link-table shape, but the count is computed from
  stored rows.

## Gaps or mismatches to resolve

- The restored task spec itself was not tracked in Git before this audit. Commit
  it before continuing so future agents can verify against the same source.
- `gunk_clusters` is folded into schema v3 as requested by T-4.13. This is safe
  while the v3 stack is unreleased/off-main. If any user has already run a v3 DB
  containing only `gunk_embeddings`, a v4 migration would be needed instead of
  editing v3 in place.

## Next task

The next task according to the restored spec is T-4.14: demo, retro, and roadmap
renumber. Before starting it, commit the restored task spec and this audit note,
then decide whether to fix the documented gaps or explicitly defer them.
