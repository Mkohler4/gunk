import { closeSync, openSync, readdirSync, readSync, statSync } from "node:fs";
import path from "node:path";

import type { ScannedFile } from "../models.js";
import { IgnoreRules } from "./ignoreRules.js";

const MAX_FILE_SIZE_BYTES = 512 * 1024;
const BINARY_SNIFF_BYTES = 4096;

function standardCompare(a: string, b: string): number {
  return a.localeCompare(b, undefined, { numeric: true });
}

function relativePath(absPath: string, rootAbsPath: string): string {
  const relative = path.relative(rootAbsPath, absPath);
  return relative.split(path.sep).join("/");
}

function isBinary(absPath: string): boolean {
  const handle = openSync(absPath, "r");
  try {
    const buffer = Buffer.alloc(BINARY_SNIFF_BYTES);
    const bytesRead = readSync(handle, buffer, 0, BINARY_SNIFF_BYTES, 0);
    for (let index = 0; index < bytesRead; index += 1) {
      if (buffer[index] === 0) {
        return true;
      }
    }
    return false;
  } finally {
    closeSync(handle);
  }
}

function walk(
  rootAbsPath: string,
  currentAbsPath: string,
  ignoreRules: IgnoreRules,
  files: ScannedFile[],
): void {
  const entries = readdirSync(currentAbsPath, { withFileTypes: true })
    .map((entry) => path.join(currentAbsPath, entry.name))
    .sort(standardCompare);

  for (const childAbsPath of entries) {
    let stats;
    try {
      stats = statSync(childAbsPath);
    } catch {
      continue;
    }

    const isDirectory = stats.isDirectory();
    const relpath = relativePath(childAbsPath, rootAbsPath);

    if (ignoreRules.decision(relpath, isDirectory) !== "include") {
      continue;
    }

    if (isDirectory) {
      walk(rootAbsPath, childAbsPath, ignoreRules, files);
      continue;
    }

    if (!stats.isFile()) {
      continue;
    }

    const size = stats.size;
    if (size > MAX_FILE_SIZE_BYTES || isBinary(childAbsPath)) {
      continue;
    }

    files.push({ absPath: childAbsPath, relpath, size });
  }
}

export function scanFolder(rootAbsPath: string): ScannedFile[] {
  const root = path.resolve(rootAbsPath);
  const ignoreRules = IgnoreRules.load(root);
  const files: ScannedFile[] = [];

  walk(root, root, ignoreRules, files);

  return files.sort((lhs, rhs) => standardCompare(lhs.relpath, rhs.relpath));
}
