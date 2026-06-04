import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const README_NAMES = ["README.md", "README", "Readme.md", "readme.md"];
const MAX_README_BYTES = 64 * 1024;
const TRUNCATION_MARKER = "\n\n[...truncated]";

export function readReadme(folderPath: string): string | null {
  const files = readdirSync(folderPath, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .sort();
  let readmeName: string | undefined;

  for (const candidate of README_NAMES) {
    readmeName =
      files.find((file) => file === candidate) ??
      files.find((file) => file.toLowerCase() === candidate.toLowerCase());

    if (readmeName) {
      break;
    }
  }

  if (!readmeName) {
    return null;
  }

  const contents = readFileSync(join(folderPath, readmeName));

  if (contents.byteLength <= MAX_README_BYTES) {
    return contents.toString("utf8");
  }

  return (
    contents.subarray(0, MAX_README_BYTES).toString("utf8") + TRUNCATION_MARKER
  );
}
