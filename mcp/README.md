# gunk-mcp

`gunk-mcp` is the short-lived TypeScript MCP server for gunk. AI tools spawn
it over stdio, it reads the local gunk store, returns context, and then exits
with the parent tool.

This package is intentionally small for T-2.2: it proves the Bun + TypeScript
toolchain works before T-2.7 adds the real MCP server surface.

## Install

```bash
cd mcp
bun install
```

## Scripts

| Script              | What it does                                |
| ------------------- | ------------------------------------------- |
| `bun run start`     | Print `gunk-mcp 0.0.1` to stderr and exit.  |
| `bun test`          | Run Vitest tests.                           |
| `bun run lint`      | Run ESLint.                                 |
| `bun run typecheck` | Run TypeScript without emitting files.      |
| `bun run format`    | Check formatting with Prettier.             |
| `bun run build`     | Bundle `src/index.ts` into `dist/` for Bun. |

## Context

- Root README: [../README.md](../README.md)
- Runtime decision: [../docs/adr/0002-stack-and-runtime.md](../docs/adr/0002-stack-and-runtime.md)
