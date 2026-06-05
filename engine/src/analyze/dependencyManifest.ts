import { analysisFirstMatch, analysisMatches } from "./analysisRegex.js";

export type DependencyManifestKind =
  | "cargoToml"
  | "gradle"
  | "goMod"
  | "packageJson"
  | "packageSwift"
  | "pubspecYaml"
  | "pyprojectToml"
  | "requirementsTxt";

export interface DependencyManifest {
  path: string;
  kind: DependencyManifestKind;
  dependencies: string[];
}

function dedupe(values: string[]): string[] {
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

function splitLines(contents: string): string[] {
  return contents.split(/\r\n|\r|\n/);
}

export class DependencyManifestParser {
  parseOne(path: string, contents: string): DependencyManifest | null {
    const lowercasedPath = path.toLowerCase();

    if (lowercasedPath.endsWith("package.json")) {
      return { path, kind: "packageJson", dependencies: this.parsePackageJSON(contents) };
    } else if (lowercasedPath.endsWith("pubspec.yaml")) {
      return { path, kind: "pubspecYaml", dependencies: this.parsePubspecYaml(contents) };
    } else if (
      lowercasedPath.endsWith("build.gradle") ||
      lowercasedPath.endsWith("build.gradle.kts")
    ) {
      return { path, kind: "gradle", dependencies: this.parseGradle(contents) };
    } else if (lowercasedPath.endsWith("package.swift")) {
      return { path, kind: "packageSwift", dependencies: this.parsePackageSwift(contents) };
    } else if (lowercasedPath.endsWith("pyproject.toml")) {
      return { path, kind: "pyprojectToml", dependencies: this.parsePyproject(contents) };
    } else if (lowercasedPath.endsWith("requirements.txt")) {
      return { path, kind: "requirementsTxt", dependencies: this.parseRequirements(contents) };
    } else if (lowercasedPath.endsWith("go.mod")) {
      return { path, kind: "goMod", dependencies: this.parseGoMod(contents) };
    } else if (lowercasedPath.endsWith("cargo.toml")) {
      return { path, kind: "cargoToml", dependencies: this.parseCargoToml(contents) };
    }

    return null;
  }

  parse(manifests: Record<string, string>): DependencyManifest[] {
    const out: DependencyManifest[] = [];
    for (const [path, contents] of Object.entries(manifests)) {
      const manifest = this.parseOne(path, contents);
      if (manifest) {
        out.push(manifest);
      }
    }

    return out.sort((lhs, rhs) => (lhs.path < rhs.path ? -1 : lhs.path > rhs.path ? 1 : 0));
  }

  private parsePackageJSON(contents: string): string[] {
    let object: Record<string, unknown>;
    try {
      const parsed = JSON.parse(contents) as unknown;
      if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
        return [];
      }
      object = parsed as Record<string, unknown>;
    } catch {
      return [];
    }

    const sections = ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"];
    const names: string[] = [];
    for (const section of sections) {
      const dependencies = object[section];
      if (typeof dependencies === "object" && dependencies !== null && !Array.isArray(dependencies)) {
        names.push(...Object.keys(dependencies as Record<string, unknown>));
      }
    }

    return dedupe(names);
  }

  private parsePubspecYaml(contents: string): string[] {
    const dependencies: string[] = [];
    let inDependencySection = false;

    for (const line of splitLines(contents)) {
      const trimmed = line.trim();
      if (trimmed.length === 0 || trimmed.startsWith("#")) {
        continue;
      }

      if (!line.startsWith(" ") && !line.startsWith("\t")) {
        inDependencySection =
          trimmed === "dependencies:" || trimmed === "dev_dependencies:";
        continue;
      }

      if (!inDependencySection) {
        continue;
      }

      const dependency = analysisFirstMatch(
        line,
        String.raw`^ {2}([A-Za-z0-9_\-\.]+)\s*:`,
      );
      if (dependency !== undefined) {
        dependencies.push(dependency);
      }
    }

    return dedupe(dependencies);
  }

  private parseGradle(contents: string): string[] {
    const dependencies: string[] = [];

    for (const match of analysisMatches(
      contents,
      String.raw`\b(?:api|compileOnly|debugImplementation|implementation|kapt|ksp|runtimeOnly|testImplementation)\s*(?:\(\s*)?["']([^"']+)["']`,
    )) {
      const coordinate = match[0];
      if (coordinate === undefined) {
        continue;
      }

      const parts = coordinate.split(":");
      dependencies.push(parts.length >= 2 ? `${parts[0]}:${parts[1]}` : coordinate);
      if (parts.length >= 2) {
        dependencies.push(parts[1]);
      }
    }

    return dedupe(dependencies);
  }

  private parsePackageSwift(contents: string): string[] {
    const packages: string[] = [];
    for (const match of analysisMatches(contents, String.raw`\.package\s*\(\s*url:\s*"([^"]+)"`)) {
      const url = match[0];
      if (url === undefined) {
        continue;
      }
      const segments = url.split("/");
      const last = segments[segments.length - 1];
      if (last === undefined || last.length === 0) {
        continue;
      }
      packages.push(last.replace(/\.git/g, ""));
    }
    return dedupe(packages);
  }

  private parsePyproject(contents: string): string[] {
    const dependencies: string[] = [];

    for (const match of analysisMatches(
      contents,
      String.raw`"([A-Za-z0-9_\-\.]+)(?:[<>=~! ][^"]*)?"`,
    )) {
      if (match[0] !== undefined) {
        dependencies.push(match[0]);
      }
    }

    for (const match of analysisMatches(
      contents,
      String.raw`(?m)^\s*([A-Za-z0-9_\-\.]+)\s*=\s*"[^\n"]+"`,
    )) {
      if (match[0] !== undefined) {
        dependencies.push(match[0]);
      }
    }

    return dedupe(dependencies);
  }

  private parseRequirements(contents: string): string[] {
    const dependencies: string[] = [];
    for (const line of splitLines(contents)) {
      const trimmed = line.trim();
      if (trimmed.length === 0 || trimmed.startsWith("#")) {
        continue;
      }
      const dependency = analysisFirstMatch(trimmed, String.raw`^([A-Za-z0-9_\-\.]+)`);
      if (dependency !== undefined) {
        dependencies.push(dependency);
      }
    }
    return dedupe(dependencies);
  }

  private parseGoMod(contents: string): string[] {
    return dedupe(
      analysisMatches(
        contents,
        String.raw`(?m)^\s*(?:require\s+)?([A-Za-z0-9_\-\.]+/[A-Za-z0-9_\-\./]+)\s+v[0-9]`,
      )
        .map((groups) => groups[0])
        .filter((value): value is string => value !== undefined),
    );
  }

  private parseCargoToml(contents: string): string[] {
    const dependencies: string[] = [];
    let inDependenciesSection = false;

    for (const line of splitLines(contents)) {
      const trimmed = line.trim();

      if (trimmed.startsWith("[")) {
        inDependenciesSection = trimmed === "[dependencies]" || trimmed === "[dev-dependencies]";
        continue;
      }

      if (!inDependenciesSection) {
        continue;
      }

      const dependency = analysisFirstMatch(trimmed, String.raw`^([A-Za-z0-9_\-]+)\s*=`);
      if (dependency !== undefined) {
        dependencies.push(dependency);
      }
    }

    return dedupe(dependencies);
  }
}
