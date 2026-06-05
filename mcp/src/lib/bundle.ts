import { readFileSync } from "node:fs";
import { join, normalize, sep } from "node:path";

import type { GunkFile } from "../store/index.js";

const MAX_TOTAL_FILE_BYTES = 64 * 1024;
const TRUNCATION_MARKER = "\n\n[...truncated]";

export interface BundleFileContent {
  relpath: string;
  content: string;
}

export function readManifest(bundlePath: string): string | null {
  try {
    return readFileSync(join(bundlePath, "gunk.yml"), "utf8");
  } catch {
    return null;
  }
}

export function readBundleFiles(
  bundlePath: string,
  files: GunkFile[],
  maxTotalBytes = MAX_TOTAL_FILE_BYTES,
): BundleFileContent[] {
  let remainingBytes = maxTotalBytes;
  const contents: BundleFileContent[] = [];

  for (const file of files) {
    if (!isSafeRelativePath(file.relpath)) {
      continue;
    }

    const filePath = join(bundlePath, file.relpath);
    let data: Buffer;

    try {
      data = readFileSync(filePath);
    } catch {
      continue;
    }

    let content: string;

    if (remainingBytes <= 0) {
      content = TRUNCATION_MARKER;
    } else if (data.byteLength > remainingBytes) {
      content =
        data.subarray(0, remainingBytes).toString("utf8") + TRUNCATION_MARKER;
      remainingBytes = 0;
    } else {
      content = data.toString("utf8");
      remainingBytes -= data.byteLength;
    }

    contents.push({
      relpath: file.relpath,
      content,
    });
  }

  return contents;
}

function isSafeRelativePath(relpath: string): boolean {
  const normalized = normalize(relpath);

  return (
    normalized.length > 0 &&
    !normalized.startsWith("..") &&
    !normalized.startsWith(sep) &&
    !normalized.includes(`${sep}..${sep}`)
  );
}
