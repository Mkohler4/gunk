import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, expect, test } from "vitest";

import { shallowTree } from "../../src/lib/tree.js";

let folderPath: string;

beforeEach(() => {
  folderPath = mkdtempSync(join(tmpdir(), "gunk-tree-"));
});

afterEach(() => {
  rmSync(folderPath, { recursive: true, force: true });
});

test("returns one level only", () => {
  mkdirSync(join(folderPath, "src"));
  writeFileSync(join(folderPath, "src", "nested.ts"), "nested");
  writeFileSync(join(folderPath, "root.ts"), "root");

  expect(shallowTree(folderPath)).toEqual([
    { name: "root.ts", type: "file", size: 4 },
    { name: "src", type: "dir" },
  ]);
});

test("skips .git and node_modules", () => {
  mkdirSync(join(folderPath, ".git"));
  mkdirSync(join(folderPath, "node_modules"));
  writeFileSync(join(folderPath, ".DS_Store"), "metadata");
  writeFileSync(join(folderPath, "index.ts"), "code");

  expect(shallowTree(folderPath)).toEqual([
    { name: "index.ts", type: "file", size: 4 },
  ]);
});

test("caps at maxEntries", () => {
  writeFileSync(join(folderPath, "c.ts"), "c");
  writeFileSync(join(folderPath, "a.ts"), "a");
  writeFileSync(join(folderPath, "b.ts"), "b");

  expect(shallowTree(folderPath, 2)).toEqual([
    { name: "a.ts", type: "file", size: 1 },
    { name: "b.ts", type: "file", size: 1 },
  ]);
});
