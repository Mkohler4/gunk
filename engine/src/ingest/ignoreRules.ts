import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

export type IgnoreDecision = "include" | "skip";

/**
 * Replicates POSIX `fnmatch(pattern, string, FNM_CASEFOLD)`:
 * `*` matches any sequence (including `/`), `?` matches any single character,
 * and matching is case-insensitive. Brackets are not supported (parity with the
 * Swift default-pattern set, which never uses them).
 */
function fnmatch(pattern: string, candidate: string): boolean {
  let source = "^";
  for (const ch of pattern) {
    if (ch === "*") {
      source += "[\\s\\S]*";
    } else if (ch === "?") {
      source += "[\\s\\S]";
    } else {
      source += ch.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
  }
  source += "$";

  try {
    return new RegExp(source, "i").test(candidate);
  } catch {
    return false;
  }
}

function splitLines(contents: string): string[] {
  return contents.split(/\r\n|\r|\n/);
}

function basenameOf(normalized: string): string {
  const components = normalized.split("/");
  return components.length > 0 ? components[components.length - 1] : "";
}

class Pattern {
  private readonly value: string;
  private readonly directoryOnly: boolean;
  private readonly anchored: boolean;

  private constructor(value: string, directoryOnly: boolean, anchored: boolean) {
    this.value = value;
    this.directoryOnly = directoryOnly;
    this.anchored = anchored;
  }

  static create(rawValue: string): Pattern | null {
    const trimmed = rawValue.trim();

    if (trimmed.length === 0 || trimmed.startsWith("#")) {
      return null;
    }

    const directoryOnly = trimmed.endsWith("/");
    const anchored = trimmed.includes("/");
    const value = trimmed.replace(/^\/+/, "").replace(/\/+$/, "");

    return new Pattern(value, directoryOnly, anchored);
  }

  matches(relpath: string, basename: string, isDirectory: boolean): boolean {
    if (this.directoryOnly && !isDirectory) {
      return false;
    }

    if (this.anchored) {
      return fnmatch(this.value, relpath) || relpath.startsWith(`${this.value}/`);
    }

    return fnmatch(this.value, basename) || (isDirectory && basename === this.value);
  }
}

export class IgnoreRules {
  // Directories that are essentially never first-party source: VCS, build
  // output, dependency/vendor trees, language virtualenvs, and tool caches.
  // The scanner prunes the whole subtree when a directory is skipped, so adding
  // a basename here keeps huge installed-dependency trees (e.g. a committed
  // Python `.venv` with tens of thousands of files) out of the pipeline.
  private static readonly DEFAULT_IGNORED_DIRECTORIES = new Set<string>([
    // VCS + generic build output
    ".git",
    "node_modules",
    "build",
    "dist",
    ".build",
    // Python virtualenvs, packaging, and caches
    ".venv",
    "venv",
    "site-packages",
    "__pycache__",
    ".tox",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".eggs",
    // JS/web build + tool caches
    ".next",
    ".nuxt",
    ".svelte-kit",
    ".turbo",
    ".parcel-cache",
    "bower_components",
    "coverage",
    // Other ecosystems
    ".gradle",
    ".dart_tool",
    "Pods",
    ".terraform",
    // Editor/tooling caches
    ".idea",
    ".vscode",
    ".cache",
  ]);

  private readonly patterns: Pattern[];

  constructor(patterns: string[] = []) {
    this.patterns = patterns
      .map((raw) => Pattern.create(raw))
      .filter((pattern): pattern is Pattern => pattern !== null);
  }

  static load(sourceRoot: string): IgnoreRules {
    const ignorePath = path.join(sourceRoot, ".gunkignore");

    if (!existsSync(ignorePath)) {
      return new IgnoreRules();
    }

    const contents = readFileSync(ignorePath, "utf8");
    return new IgnoreRules(splitLines(contents));
  }

  decision(relpath: string, isDirectory: boolean): IgnoreDecision {
    const normalized = IgnoreRules.normalize(relpath);
    const basename = basenameOf(normalized);

    if (this.isDefaultIgnored(basename, isDirectory)) {
      return "skip";
    }

    if (IgnoreRules.isLikelySecret(normalized, basename)) {
      return "skip";
    }

    if (this.patterns.some((pattern) => pattern.matches(normalized, basename, isDirectory))) {
      return "skip";
    }

    return "include";
  }

  private isDefaultIgnored(basename: string, isDirectory: boolean): boolean {
    if (basename === ".DS_Store" || basename === ".gunkignore") {
      return true;
    }

    if (!isDirectory) {
      return false;
    }

    return IgnoreRules.DEFAULT_IGNORED_DIRECTORIES.has(basename);
  }

  private static isLikelySecret(relpath: string, basename: string): boolean {
    const candidates = [basename, relpath];
    const secretPatterns = [
      ".env*",
      "*.pem",
      "*.key",
      "id_rsa*",
      "credentials*",
      "*.p12",
      "*.pfx",
    ];

    return secretPatterns.some((pattern) =>
      candidates.some((candidate) => fnmatch(pattern, candidate)),
    );
  }

  private static normalize(p: string): string {
    return p.replace(/\\/g, "/").replace(/^\/+/, "").replace(/\/+$/, "");
  }
}
