// Installs gunk-mcp to a user-local bin path, ALWAYS rebuilding from the
// current source first. This is the guard against a stale installed binary
// lagging behind the source (which manifests as MCP "Not connected" errors).
//
// Destination defaults to ~/.local/bin/gunk-mcp and can be overridden with the
// GUNK_MCP_INSTALL_PATH env var (e.g. /usr/local/bin/gunk-mcp).

import { chmodSync, copyFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";

const packageDir = resolve(import.meta.dir, "..");
const builtBinary = join(packageDir, "dist", "gunk-mcp");

// Always rebuild so the installed binary can never be older than the source.
const build = Bun.spawnSync(["bun", "run", "build"], {
  cwd: packageDir,
  stdout: "inherit",
  stderr: "inherit",
});

if (build.exitCode !== 0) {
  console.error("gunk-mcp build failed; nothing was installed.");
  process.exit(build.exitCode ?? 1);
}

const destination =
  process.env.GUNK_MCP_INSTALL_PATH ??
  join(homedir(), ".local", "bin", "gunk-mcp");

mkdirSync(dirname(destination), { recursive: true });
copyFileSync(builtBinary, destination);
chmodSync(destination, 0o755);

console.log(`Installed gunk-mcp -> ${destination}`);
