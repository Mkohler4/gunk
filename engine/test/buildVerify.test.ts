import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import { BuildVerifier } from "../src/extract/buildVerify.js";

const tempDirs: string[] = [];

function makeBundle(files: Record<string, string>): string {
  const root = mkdtempSync(join(tmpdir(), "gunk-build-verify-test-"));
  tempDirs.push(root);
  for (const [path, contents] of Object.entries(files)) {
    const fullPath = join(root, path);
    mkdirSync(dirname(fullPath), { recursive: true });
    writeFileSync(fullPath, contents);
  }
  return root;
}

function hasTypeScriptTool(): boolean {
  if (existsSync(resolve("node_modules", ".bin", "tsc"))) return true;
  if (existsSync(resolve("engine", "node_modules", ".bin", "tsc"))) return true;
  const result = spawnSync("tsc", ["--version"], { encoding: "utf8" });
  return !result.error && result.status === 0;
}

describe("BuildVerifier", () => {
  afterEach(() => {
    for (const dir of tempDirs.splice(0)) {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  const maybeIt = hasTypeScriptTool() ? it : it.skip;

  maybeIt("reports built=true for a self-contained TS bundle", () => {
    const bundle = makeBundle({
      "src/index.ts": `export function add(lhs: number, rhs: number): number {
  return lhs + rhs;
}
`,
    });

    const result = new BuildVerifier({ timeoutMs: 10_000 }).verify(bundle);

    expect(result.skipped).toBe(false);
    expect(result.built).toBe(true);
    expect(result.command).toContain("tsc --noEmit");
  });

  maybeIt("reports built=false (no throw) for a dangling bundle", () => {
    const bundle = makeBundle({
      "src/index.ts": `import { missing } from "./missing";

export const value = missing;
`,
    });

    const result = new BuildVerifier({ timeoutMs: 10_000 }).verify(bundle);

    expect(result.skipped).toBe(false);
    expect(result.built).toBe(false);
    expect(result.log).toContain("missing");
  });

  it("skips cleanly when the toolchain is absent", () => {
    const bundle = makeBundle({
      "src/index.ts": "export const value = 1;\n",
    });
    const cwd = mkdtempSync(join(tmpdir(), "gunk-build-verify-empty-cwd-"));
    tempDirs.push(cwd);

    const result = new BuildVerifier({
      cwd,
      env: { ...process.env, PATH: "" },
    }).verify(bundle);

    expect(result.skipped).toBe(true);
    expect(result.built).toBe(false);
    expect(result.command).toBeNull();
  });
});
