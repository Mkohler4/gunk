import type { ExportRef, FileSymbols } from "../models.js";
import { analysisMatches } from "./analysisRegex.js";
import {
  type CapabilityHint,
  capabilityHintKey,
  CapabilityLexicon,
} from "./capabilityLexicon.js";
import { type DependencyManifest } from "./dependencyManifest.js";
import { RouteDetector, type RouteSurface } from "./routeDetector.js";

export interface CapabilityFingerprint {
  filePath: string;
  importedDependencies: string[];
  routes: RouteSurface[];
  publicExports: ExportRef[];
  envVars: string[];
  configKeys: string[];
  namingTokens: string[];
  capabilityHints: CapabilityHint[];
}

export interface ClusterCapabilityFingerprint {
  filePaths: string[];
  importedDependencies: string[];
  routes: RouteSurface[];
  publicExports: ExportRef[];
  envVars: string[];
  configKeys: string[];
  namingTokens: string[];
  capabilityHints: CapabilityHint[];
  hasPublicSurface: boolean;
}

function dedupeStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const value of values) {
    if (!seen.has(value)) {
      seen.add(value);
      out.push(value);
    }
  }
  return out;
}

function dedupeHints(hints: CapabilityHint[]): CapabilityHint[] {
  const seen = new Set<string>();
  const out: CapabilityHint[] = [];
  for (const hint of hints) {
    const key = capabilityHintKey(hint);
    if (!seen.has(key)) {
      seen.add(key);
      out.push(hint);
    }
  }
  return out;
}

function isUppercase(char: string): boolean {
  return char !== char.toLowerCase() && char === char.toUpperCase();
}

function splitBeforeUppercase(value: string): string[] {
  const words: string[] = [];
  let current = "";

  for (const char of value) {
    if (isUppercase(char) && current.length > 0) {
      words.push(current);
      current = "";
    }
    current += char;
  }

  if (current.length > 0) {
    words.push(current);
  }

  return words;
}

function splitIdentifier(value: string): string[] {
  return value
    .replace(/-/g, "_")
    .split("_")
    .filter((part) => part.length > 0)
    .flatMap((part) => splitBeforeUppercase(part));
}

export class CapabilityFingerprintBuilder {
  private readonly lexicon: CapabilityLexicon;
  private readonly routeDetector: RouteDetector;

  constructor(lexicon: CapabilityLexicon = CapabilityLexicon.default, routeDetector = new RouteDetector()) {
    this.lexicon = lexicon;
    this.routeDetector = routeDetector;
  }

  fingerprints(
    files: FileSymbols[],
    manifests: DependencyManifest[],
    contentsByPath: Record<string, string>,
  ): CapabilityFingerprint[] {
    const declaredDependencies = dedupeStrings(
      manifests.flatMap((manifest) => manifest.dependencies),
    ).sort();

    return files
      .map((file) => {
        const contents = contentsByPath[file.path] ?? "";
        const importedDependencies = this.dependenciesImported(file, declaredDependencies);
        const hints = dedupeHints(
          importedDependencies
            .map((dependency) => this.lexicon.hint(dependency))
            .filter((hint): hint is CapabilityHint => hint !== null),
        );

        return {
          filePath: file.path,
          importedDependencies,
          routes: this.routeDetector.detect(file.path, contents),
          publicExports: file.exports,
          envVars: this.envVars(contents),
          configKeys: this.configKeys(contents),
          namingTokens: this.namingTokens(file),
          capabilityHints: hints,
        };
      })
      .sort((lhs, rhs) => (lhs.filePath < rhs.filePath ? -1 : lhs.filePath > rhs.filePath ? 1 : 0));
  }

  aggregate(
    fingerprints: CapabilityFingerprint[],
    filePaths: Set<string>,
  ): ClusterCapabilityFingerprint {
    const included = fingerprints.filter((fingerprint) => filePaths.has(fingerprint.filePath));

    const routes = included.flatMap((fingerprint) => fingerprint.routes);
    const publicExports = included.flatMap((fingerprint) => fingerprint.publicExports);

    return {
      filePaths: [...filePaths],
      importedDependencies: dedupeStrings(
        included.flatMap((fingerprint) => fingerprint.importedDependencies),
      ),
      routes,
      publicExports,
      envVars: dedupeStrings(included.flatMap((fingerprint) => fingerprint.envVars)),
      configKeys: dedupeStrings(included.flatMap((fingerprint) => fingerprint.configKeys)),
      namingTokens: dedupeStrings(included.flatMap((fingerprint) => fingerprint.namingTokens)),
      capabilityHints: dedupeHints(included.flatMap((fingerprint) => fingerprint.capabilityHints)),
      hasPublicSurface:
        routes.length > 0 ||
        publicExports.length > 0 ||
        included.some((fingerprint) => fingerprint.capabilityHints.length > 0),
    };
  }

  private dependenciesImported(
    file: FileSymbols,
    declaredDependencies: string[],
  ): string[] {
    const matched: string[] = [];
    for (const importRef of file.imports) {
      const dependency = declaredDependencies.find((candidate) =>
        this.importMatchesDependency(importRef.moduleSpecifier, candidate),
      );
      if (dependency !== undefined) {
        matched.push(dependency);
      }
    }
    return dedupeStrings(matched);
  }

  private importMatchesDependency(specifier: string, dependency: string): boolean {
    const normalizedSpecifier = this.normalizePackageName(this.packageRoot(specifier));
    const normalizedDependency = this.normalizePackageName(dependency);
    const normalizedGroup = this.normalizePackageName(dependency.split(":")[0] ?? "");

    return (
      normalizedSpecifier === normalizedDependency ||
      normalizedSpecifier.startsWith(`${normalizedDependency}/`) ||
      normalizedDependency.startsWith(`${normalizedSpecifier}/`) ||
      (normalizedGroup.length > 0 &&
        (normalizedSpecifier === normalizedGroup ||
          normalizedSpecifier.startsWith(`${normalizedGroup}.`)))
    );
  }

  private packageRoot(specifier: string): string {
    if (specifier.startsWith("package:")) {
      const body = specifier.slice("package:".length);
      const first = body.split("/")[0];
      return first.length > 0 ? first : specifier;
    }

    if (!specifier.startsWith("@")) {
      const first = specifier.split("/")[0];
      return first.length > 0 ? first : specifier;
    }

    const parts = specifier.split("/");
    if (parts.length < 2) {
      return specifier;
    }

    return `${parts[0]}/${parts[1]}`;
  }

  private normalizePackageName(name: string): string {
    return name.toLowerCase().replace(/_/g, "-").trim();
  }

  private envVars(contents: string): string[] {
    const patterns = [
      String.raw`process\.env\.([A-Za-z_][A-Za-z0-9_]*)`,
      String.raw`process\.env\[['"]([A-Za-z_][A-Za-z0-9_]*)['"]\]`,
      String.raw`os\.environ\[['"]([A-Za-z_][A-Za-z0-9_]*)['"]\]`,
      String.raw`getenv\(['"]([A-Za-z_][A-Za-z0-9_]*)['"]\)`,
      String.raw`Environment\.GetEnvironmentVariable\(['"]([A-Za-z_][A-Za-z0-9_]*)['"]\)`,
    ];

    return dedupeStrings(
      patterns.flatMap((pattern) =>
        analysisMatches(contents, pattern)
          .map((groups) => groups[0])
          .filter((value): value is string => value !== undefined),
      ),
    );
  }

  private configKeys(contents: string): string[] {
    const patterns = [
      String.raw`config\.get\(['"]([A-Za-z0-9_\-\.]+)['"]\)`,
      String.raw`getConfig\(['"]([A-Za-z0-9_\-\.]+)['"]\)`,
      String.raw`settings\.([A-Za-z_][A-Za-z0-9_]*)`,
    ];

    return dedupeStrings(
      patterns.flatMap((pattern) =>
        analysisMatches(contents, pattern)
          .map((groups) => groups[0])
          .filter((value): value is string => value !== undefined),
      ),
    );
  }

  private namingTokens(file: FileSymbols): string[] {
    const pathTokens = file.path
      .replace(/\./g, "/")
      .split("/")
      .filter((component) => component.length > 0);
    const symbolTokens = file.symbols.flatMap((symbol) => splitIdentifier(symbol.name));
    const exportTokens = file.exports.flatMap((ref) => splitIdentifier(ref.name));

    return dedupeStrings(
      [...pathTokens, ...symbolTokens, ...exportTokens]
        .flatMap((token) => splitIdentifier(token))
        .map((token) => token.toLowerCase())
        .filter((token) => token.length > 2),
    );
  }
}
