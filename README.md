# gunk

[![CI](https://github.com/Mkohler4/gunk/actions/workflows/ci.yml/badge.svg)](https://github.com/Mkohler4/gunk/actions/workflows/ci.yml)

> **Reframe, don't recode. Less tokens, more shipping.**

Gunk is your shit code, modularized — and silently fed back into your AI.

You ship throwaway projects every week. Half of them die. The other half quietly contain the same auth flow, the same Stripe wrapper, the same dashboard scaffold — re-implemented for the 51st time. That waste is **gunk**. Repurposed correctly, it's the most useful thing in your dev folder.

You drag the folders you want to remember onto **gunk.app**. It modularizes them and exposes them to **Cursor, Claude Code, Codex, and OpenCode** via MCP. So when your AI is about to recode auth from scratch, it finds yours and references it instead.

You don't type any commands. You don't grant Full Disk Access. You curate; gunk does the rest.

---

## The problem

- **Sprawl.** Even on GitHub, you can't find your own work after six months.
- **Reinvention.** Auth, payments, dashboards, scrapers — implemented dozens of times across throwaway repos. None of it reused.
- **Tool fragmentation.** ~7 AI tools per developer (Cursor, Claude Code, Codex, OpenCode, ChatGPT, Cline, Aider…). None know what the others have already built for you.
- **Token waste.** Every "build me a login page" prompt regenerates code you already wrote last week. You pay for it. You wait for it. You merge it. Again.

A 50-follower Twitter post asking "what's everyone building?" returned 55 replies referencing 50 distinct abandoned products in under a day. The signal is loud. The waste is real.

## How it works

Two processes. One local store. No daemon. No file-system scanning.

```
┌──────────────────────────────────────────────────────────────┐
│  You keep coding in Cursor / Claude Code / Codex / OpenCode  │
│  exactly like you do today. Your AI gets smarter.            │
└────────────────────────┬─────────────────────────────────────┘
                         │ AI tool spawns gunk-mcp on startup
                         ▼
        ┌────────────────────────────────────────┐
        │  gunk-mcp  (TypeScript, short-lived)   │
        │  - reads ~/.gunk/store.db              │
        │  - exposes MCP tools to the AI tool    │
        │  - exits when AI tool exits            │
        └────────────────────┬───────────────────┘
                             │ reads
                             ▼
                   ┌──────────────────────┐
                   │   ~/.gunk/store.db   │
                   │   + module files     │
                   └──────────▲───────────┘
                              │ writes (only on user drop)
                              │
        ┌─────────────────────┴────────────────────┐
        │  gunk.app  (macOS menubar)               │
        │  - drop zone for folders                 │
        │  - in-process classifier + extractor     │
        │  - browse / approve UI                   │
        │  - one-click MCP setup for all 4 tools   │
        └──────────────────────────────────────────┘
```

### What you actually do

1. **Install gunk.app** (drag-and-drop into Applications).
2. **Drop the folders you want gunk to know about** onto the app's window. Old side projects, abandoned experiments, that one repo with the auth flow you keep stealing from. Each drop becomes a gunk.
3. The app detects which AI tools you have installed → *"Wire them all up to gunk?"* → one click. It writes the right MCP config to Cursor, Claude Code, Codex, and OpenCode for you.
4. **You open Cursor and code like you always do.** The next time you ask for an auth flow, your AI finds the one in your dropped folder and references it instead of regenerating it.

You can drop more folders in any time. You can remove folders any time. There is no `~/code` config, no filesystem watcher, no permission prompt for files outside what you dropped.

### The wow moment

> *"Build me Google OAuth."*

**Without gunk:** 4,000 tokens, 30 seconds, brand-new code that's subtly different from the four other auth flows you've already written.

**With gunk:** *"I see you have an auth module in `proj-47/lib/auth/`. Should I use that pattern?"* — 200 tokens, 3 seconds, your real code.

## Status

Very early. Building in public. Code lands daily-ish; product decisions land in [`docs/adr/`](docs/adr/); the plan lives in [`docs/roadmap.md`](docs/roadmap.md).

What exists today: this README, four ADRs, a roadmap, and a clear thesis. That's the honest state.

## Roadmap (high-level)

| Phase | Outcome |
|---|---|
| 1. Foundation | Repo, license, ADRs, CI, public roadmap. |
| 2. Walking skeleton | Drop a folder → it appears in the store → MCP server exposes it → Cursor can reference it. End-to-end, no classification. |
| 3. Classifier | Drops get tagged: auth, payments, ui-kit, scraper, dashboard… |
| 4. Extractor | Tagged modules become portable bundles with manifests. |
| 5. AI-tool wiring | One-click MCP setup for Cursor, Claude Code, Codex, OpenCode. |
| 6. Polish | Approval UI, usage counter, browse view, settings. |
| 7. Friend alpha | Five real users from the Twitter circle. |
| 8. Public alpha | `gunk.app` download, demo video, Show HN. |

See [`docs/roadmap.md`](docs/roadmap.md) for the week-by-week version.

**Explicitly out of scope for v0:** any cloud component, any public/shared registry, any team features, any monetization, any filesystem watching. Everything is local; everything is user-curated. We re-evaluate after the local product is real.

## Principles

- **Drop-only ingestion.** Gunk only knows about folders you explicitly drop on it. No filesystem watching, no Full Disk Access, no path config. ([ADR-0004](docs/adr/0004-drag-in-over-file-watch.md))
- **Ambient, not invoked.** Once configured, the user types zero gunk commands. The AI tool does the work. ([ADR-0003](docs/adr/0003-ambient-over-invoked.md))
- **Local-first.** Your gunk stays on your machine. There is no cloud component in v0.
- **Two processes, no daemon.** A short-lived MCP server (spawned by AI tools) and a macOS menubar app. They share a SQLite store. ([ADR-0002](docs/adr/0002-stack-and-runtime.md))
- **AI-native.** Every feature is designed around "how does an AI consume this?" first.
- **Boring stack, durable choices.** TypeScript MCP server, Swift macOS app, SQLite store. We optimize for shipping.
- **Build in public.** Weekly visible progress, not promises.

## Stack ([ADR-0002](docs/adr/0002-stack-and-runtime.md))

- **`gunk.app`:** Swift / SwiftUI / AppKit. macOS 14+. Native menubar app.
- **`gunk-mcp`:** TypeScript on Bun. Single-binary. Spawned by AI tools using the standard MCP stdio pattern.
- **Local store:** SQLite + a modules directory under `~/.gunk/`.
- **AI tool integration:** MCP. Works for Cursor, Claude Code, Codex, OpenCode, Claude Desktop, Cline, and any future MCP-compatible client.

## Contributing

We're not ready for big PRs yet — the architecture is still moving. But:

- File issues for use cases, naming, problems we should solve.
- Watch the repo to follow along.
- See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the (small) process so far.

## License

MIT. See [`LICENSE`](LICENSE).
