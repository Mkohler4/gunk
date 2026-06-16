// Minimal `gunk.yml` readers for the run tool (T-10.12). The manifest is
// written by a deterministic line writer (`engine/src/extract/manifestWriter.ts`),
// so a lightweight line parser — mirroring the app's `manifestEntrypoints` /
// `manifestRequirements` (BrowseModel.swift) — is faithful and avoids pulling a
// YAML dependency into the short-lived MCP server.

export interface ManifestEntrypoint {
  path: string;
  symbol: string | null;
}

/** Parses the `entrypoints:` block into `{ path, symbol }` records. */
export function parseEntrypoints(manifest: string): ManifestEntrypoint[] {
  const entrypoints: ManifestEntrypoint[] = [];
  let inBlock = false;
  let pendingPath: string | null = null;

  const flush = (): void => {
    if (pendingPath !== null) {
      entrypoints.push({ path: pendingPath, symbol: null });
      pendingPath = null;
    }
  };

  for (const rawLine of manifest.split("\n")) {
    if (rawLine === "entrypoints:") {
      inBlock = true;
      continue;
    }
    if (!inBlock) {
      continue;
    }
    // A non-indented line ends the block.
    if (rawLine.length > 0 && !rawLine.startsWith(" ")) {
      break;
    }

    const trimmed = rawLine.trim();
    if (trimmed.startsWith("- path:")) {
      flush();
      pendingPath = yamlValue(trimmed.slice("- path:".length));
    } else if (trimmed.startsWith("symbol:") && pendingPath !== null) {
      entrypoints.push({
        path: pendingPath,
        symbol: yamlValue(trimmed.slice("symbol:".length)),
      });
      pendingPath = null;
    }
  }
  flush();

  return entrypoints;
}

/**
 * Parses `requirements.packages` (the portability readout persisted at
 * extraction, T-10.6). Used only to *classify* runnability Swift-side — never
 * installed. Returns `[]` when the block is absent (older bundles).
 */
export function parseRequirementPackages(manifest: string): string[] {
  const packages: string[] = [];
  let inRequirements = false;
  let inPackages = false;

  for (const rawLine of manifest.split("\n")) {
    if (rawLine === "requirements:") {
      inRequirements = true;
      continue;
    }
    if (!inRequirements) {
      continue;
    }
    // A non-indented line ends the requirements block.
    if (rawLine.length > 0 && !rawLine.startsWith(" ")) {
      break;
    }

    const trimmed = rawLine.trim();
    // Two-space keys vs four-space list items: `- foo` must not be read as a key.
    const isKey = rawLine.startsWith("  ") && !rawLine.startsWith("    ");
    if (isKey) {
      inPackages =
        trimmed.startsWith("packages:") &&
        trimmed.slice("packages:".length).trim() !== "[]";
    } else if (inPackages && trimmed.startsWith("-")) {
      const value = yamlValue(trimmed.slice(1));
      if (value !== null) {
        packages.push(value);
      }
    }
  }

  return packages;
}

/** Unwraps a writer-emitted scalar: `null`/empty → null, `"x"` → x. */
function yamlValue(raw: string): string | null {
  const value = raw.trim();
  if (value === "null" || value.length === 0) {
    return null;
  }
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value
      .slice(1, -1)
      .replace(/\\"/g, '"')
      .replace(/\\n/g, "\n")
      .replace(/\\\\/g, "\\");
  }
  return value;
}
