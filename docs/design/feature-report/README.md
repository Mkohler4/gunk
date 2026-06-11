# gunk — front-end feature report (for redesign)

Audience: a design agent (Claude) tasked with redesigning the entire layout
of the gunk macOS app. The current app works but is confusing to use; this
report is the complete, code-accurate inventory of every front-end feature
as it exists today (post phase 7), so the redesign starts from ground truth
rather than guesswork.

Audit basis: direct read of `app/Sources/GunkApp/` views and controllers as
of the phase-7 completion. Where a behavior is surprising or broken, it is
called out explicitly — those are the things the redesign must either fix
or deliberately preserve.

## What gunk is (30-second version)

gunk watches you drop a folder of code onto it (window drop zone or Dock
icon), runs an LLM-powered engine that decomposes that folder into reusable
**modules**, verifies them (self-containment, build), and — once a module is
accepted or approved — **extracts** it so an AI agent can use it through an
MCP server (`gunk-mcp`). The core journey is:

```
Drop a folder → engine processes it → modules appear → low-confidence
modules wait in Approval → approved/accepted modules become "Agent-ready"
(visible to your agent via MCP)
```

The five in-window pages map onto that journey plus two utilities:

| Page | Role in the journey |
| --- | --- |
| Sources | Intake — drop folders, see what each produced |
| Modules | The core object — browse and inspect extracted modules |
| Approval | Triage — review low-confidence modules the engine wasn't sure about |
| Runs | Utility — per-run engine traces (debug-grade today) |
| Settings | Utility — LLM provider config + end-to-end pipeline health |

## Documents in this report

| File | Surface |
| --- | --- |
| [01-app-shell.md](01-app-shell.md) | Window chrome, sidebar, navigation, global status strip, landing rules |
| [02-sources.md](02-sources.md) | Sources page — drop zone + source list |
| [03-modules.md](03-modules.md) | Modules page — filter bar, browser, detail pane |
| [04-approval.md](04-approval.md) | Approval page — review queue |
| [05-runs.md](05-runs.md) | Runs page — engine trace viewer |
| [06-settings.md](06-settings.md) | Settings page — provider form + health status |
| [07-system-surfaces.md](07-system-surfaces.md) | Dock icon, menubar item, launch-failure screen |

## How to read these documents

Each page document covers, in order:

1. **Purpose** — what the page is for, in one sentence.
2. **Layout** — the structural arrangement as built today (with measurements
   where they are hard-coded).
3. **Feature inventory** — every visible element and interactive control,
   and exactly what each one does (including navigation side effects).
4. **States** — empty, loading/processing, error, and transient states.
5. **Known problems & quirks** — confusions, inconsistencies, and bugs the
   current layout carries. These are the strongest signals for the redesign.

## Cross-cutting facts the redesign must know

- **Window:** minimum 960×600; the window title is always "gunk", and the
  current section name renders as a toolbar label instead. The toolbar
  background is hidden, so the title area reads as part of the content.
- **Visual system:** a frozen brand system (CP1 tokens + CP2 components) —
  `BrandColors`, `BrandTypography`, `BrandMetrics`, glass cards
  (`GlassCard`, `.brandGlass`), `StatusBadge`, `TagChip`, `SectionHeader`,
  `EmptyStateView`, `BrandWordmark`, and brand button styles
  (primary/secondary/destructive/icon). Sources, Modules, and the shell use
  it; **Approval and Runs were never re-skinned** and still use plain
  SwiftUI styling — the app is visually inconsistent page-to-page today.
- **One data model quirk that shapes everything:** "the approval queue" is
  computed (confidence below threshold AND not approved AND not extracted).
  High-confidence modules are auto-accepted and extracted silently — they
  never pass through Approval at all.
- **The payoff state is "Agent-ready":** a module with `extractedAt` set is
  visible to the user's agent via MCP. This is surfaced as a badge on module
  rows, a status line in the module detail, and indirectly via the sidebar
  status strip ("Agent connected" / "MCP not set up").
