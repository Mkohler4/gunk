import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, expect, test } from "vitest";

import { readReadme } from "../../src/lib/readme.js";

let folderPath: string;

beforeEach(() => {
  folderPath = mkdtempSync(join(tmpdir(), "gunk-readme-"));
});

afterEach(() => {
  rmSync(folderPath, { recursive: true, force: true });
});

test("finds README.md", () => {
  writeFileSync(join(folderPath, "README.md"), "# Fixture\n");

  expect(readReadme(folderPath)).toBe("# Fixture\n");
});

test("finds README.md case-insensitively", () => {
  writeFileSync(join(folderPath, "rEaDmE.Md"), "# Mixed case\n");

  expect(readReadme(folderPath)).toBe("# Mixed case\n");
});

test("prefers README.md over readme.md", () => {
  writeFileSync(join(folderPath, "readme.md"), "lower priority");
  writeFileSync(join(folderPath, "README.md"), "higher priority");

  expect(readReadme(folderPath)).toBe("higher priority");
});

test("prefers mini readme over source readme", () => {
  writeFileSync(join(folderPath, "README.md"), "source readme");
  writeFileSync(join(folderPath, "README.gunk.md"), "mini readme");

  expect(readReadme(folderPath)).toBe("mini readme");
});

test("returns null when none present", () => {
  mkdirSync(join(folderPath, "src"));
  writeFileSync(join(folderPath, "package.json"), "{}");

  expect(readReadme(folderPath)).toBeNull();
});

test("truncates files over 64 KiB with marker", () => {
  writeFileSync(join(folderPath, "README.md"), "a".repeat(64 * 1024 + 1));

  expect(readReadme(folderPath)).toBe(
    "a".repeat(64 * 1024) + "\n\n[...truncated]",
  );
});
