// Portability requirements for a module — the "to run this elsewhere, you
// need" readout (T-10.6). The per-module packages/env are already parsed
// upstream by `CapabilityFingerprintBuilder.aggregate` (imported dependencies
// matched against declared manifests + scanned env vars); this module adds the
// runtime derivation and the shape persisted into `gunk.yml`.

import { basename } from "node:path";

import { analysisFirstMatch } from "../analyze/analysisRegex.js";

export interface ModuleRequirements {
  /** Human runtime line, e.g. `Python ≥ 3.11`, or `null` when unknown. */
  runtime: string | null;
  /** External packages the module imports (faithful, never the whole repo). */
  packages: string[];
  /** Environment variables the module reads. */
  env: string[];
}

export const EMPTY_REQUIREMENTS: ModuleRequirements = {
  runtime: null,
  packages: [],
  env: [],
};

interface RuntimeCandidate {
  name: string;
  version: string | null;
}

/**
 * Map a stored language token (`typeScript`, `python`, …) to the name of the
 * runtime you actually install to run it. TypeScript/JavaScript run on Node, so
 * they map to `Node`; everything else keeps its own name. Returns `null` when
 * the language is unknown — we never invent one.
 */
function humanizeLanguage(language: string | null): string | null {
  if (language === null) {
    return null;
  }
  const normalized = language.trim();
  if (normalized.length === 0) {
    return null;
  }

  const known: Record<string, string> = {
    python: "Python",
    typescript: "Node",
    javascript: "Node",
    node: "Node",
    go: "Go",
    rust: "Rust",
    swift: "Swift",
    dart: "Dart",
    java: "Java",
    kotlin: "Kotlin",
    ruby: "Ruby",
    php: "PHP",
    csharp: "C#",
  };
  const mapped = known[normalized.toLowerCase()];
  if (mapped !== undefined) {
    return mapped;
  }
  return normalized[0]!.toUpperCase() + normalized.slice(1);
}

/**
 * Pull the lower-bound version out of a constraint string and render it as
 * `≥ X.Y`. Manifest constraints (`^18`, `>=3.11`, `1.21`, `>=3.0.0 <4.0.0`) are
 * minimums in practice, so we surface the first version token as the floor and
 * drop the rest rather than guess at a range.
 */
function formatVersion(raw: string | undefined): string | null {
  if (raw === undefined) {
    return null;
  }
  const match = /(\d+(?:\.\d+){0,2})/.exec(raw);
  return match ? `≥ ${match[1]}` : null;
}

function runtimeFromManifest(
  path: string,
  contents: string,
): RuntimeCandidate | null {
  const name = basename(path).toLowerCase();

  if (name === "package.json") {
    try {
      const parsed = JSON.parse(contents) as { engines?: { node?: unknown } };
      const node = parsed.engines?.node;
      return {
        name: "Node",
        version: typeof node === "string" ? formatVersion(node) : null,
      };
    } catch {
      return { name: "Node", version: null };
    }
  }
  if (name === "pyproject.toml") {
    return {
      name: "Python",
      version: formatVersion(
        analysisFirstMatch(
          contents,
          String.raw`requires-python\s*=\s*["']([^"']+)["']`,
        ),
      ),
    };
  }
  if (name === "requirements.txt") {
    return { name: "Python", version: null };
  }
  if (name === "go.mod") {
    return {
      name: "Go",
      version: formatVersion(
        analysisFirstMatch(
          contents,
          String.raw`(?m)^go\s+([0-9]+(?:\.[0-9]+){0,2})`,
        ),
      ),
    };
  }
  if (name === "cargo.toml") {
    return {
      name: "Rust",
      version: formatVersion(
        analysisFirstMatch(
          contents,
          String.raw`rust-version\s*=\s*["']([^"']+)["']`,
        ),
      ),
    };
  }
  if (name === "package.swift") {
    return {
      name: "Swift",
      version: formatVersion(
        analysisFirstMatch(
          contents,
          String.raw`swift-tools-version:\s*([0-9.]+)`,
        ),
      ),
    };
  }
  if (name === "pubspec.yaml") {
    return {
      name: "Dart",
      version: formatVersion(
        analysisFirstMatch(contents, String.raw`sdk:\s*["']?([^"'\n]+)`),
      ),
    };
  }

  return null;
}

/**
 * Derive the runtime line from the repo's dependency manifests, preferring the
 * one whose runtime matches the module's language. Falls back to the bare
 * language name (no version) when no manifest constraint is parseable, and to
 * `null` only when even the language is unknown — show what is parseable, omit
 * what is not.
 */
export function deriveRuntime(
  language: string | null,
  manifests: Record<string, string>,
): string | null {
  const candidates: RuntimeCandidate[] = [];
  for (const [path, contents] of Object.entries(manifests)) {
    const candidate = runtimeFromManifest(path, contents);
    if (candidate) {
      candidates.push(candidate);
    }
  }

  const languageName = humanizeLanguage(language);
  const preferred =
    candidates.find(
      (candidate) => languageName !== null && candidate.name === languageName,
    ) ??
    candidates[0] ??
    null;

  if (preferred) {
    return preferred.version
      ? `${preferred.name} ${preferred.version}`
      : preferred.name;
  }
  return languageName;
}
