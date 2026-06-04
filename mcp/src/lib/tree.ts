import { readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const IGNORED_ENTRIES = new Set([".git", "node_modules", ".DS_Store"]);

export interface TreeEntry {
  name: string;
  type: "file" | "dir";
  size?: number;
}

export function shallowTree(folderPath: string, maxEntries = 200): TreeEntry[] {
  if (maxEntries <= 0) {
    return [];
  }

  const entries = readdirSync(folderPath, { withFileTypes: true })
    .filter((entry) => !IGNORED_ENTRIES.has(entry.name))
    .sort((left, right) => left.name.localeCompare(right.name));
  const tree: TreeEntry[] = [];

  for (const entry of entries) {
    if (tree.length >= maxEntries) {
      break;
    }

    const stats = statSync(join(folderPath, entry.name));

    if (stats.isDirectory()) {
      tree.push({ name: entry.name, type: "dir" });
    } else if (stats.isFile()) {
      tree.push({ name: entry.name, type: "file", size: stats.size });
    }
  }

  return tree;
}
