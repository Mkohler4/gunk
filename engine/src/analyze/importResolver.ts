export interface ImportResolverConfig {
  sourceFiles: Set<string>;
  tsconfigPaths?: Record<string, string[]>;
}

function normalizePathComponents(path: string): string {
  return path.split("/").filter((component) => component.length > 0).join("/");
}

export class ImportResolver {
  private readonly sourceFiles: Set<string>;
  private readonly tsconfigPaths: Record<string, string[]>;
  private readonly extensions = ["", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".py", ".swift", ".go"];

  constructor(config: ImportResolverConfig) {
    this.sourceFiles = new Set(
      [...config.sourceFiles].map((path) => normalizePathComponents(path)),
    );
    this.tsconfigPaths = config.tsconfigPaths ?? {};
  }

  resolve(specifier: string, sourcePath: string): string | null {
    if (specifier.startsWith(".")) {
      return this.resolveRelative(specifier, sourcePath);
    }

    const aliased = this.resolveAlias(specifier);
    if (aliased !== null) {
      return aliased;
    }

    return this.resolveCandidate(specifier);
  }

  private resolveRelative(specifier: string, sourcePath: string): string | null {
    const sourceDirectory = deletingLastPathComponent(sourcePath);
    return this.resolveCandidate(this.normalize(`${sourceDirectory}/${specifier}`));
  }

  private resolveAlias(specifier: string): string | null {
    for (const [pattern, targets] of Object.entries(this.tsconfigPaths)) {
      const captured = this.captureAliasWildcard(specifier, pattern);
      if (captured === null) {
        continue;
      }

      for (const target of targets) {
        const candidate = target.replace(/\*/g, captured);
        const resolved = this.resolveCandidate(candidate);
        if (resolved !== null) {
          return resolved;
        }
      }
    }

    return null;
  }

  private resolveCandidate(candidate: string): string | null {
    const normalizedCandidate = this.normalize(candidate);

    for (const suffix of this.extensions) {
      const path = normalizedCandidate + suffix;
      if (this.sourceFiles.has(path)) {
        return path;
      }
    }

    for (const suffix of this.extensions.slice(1)) {
      const indexPath = `${normalizedCandidate}/index${suffix}`;
      if (this.sourceFiles.has(indexPath)) {
        return indexPath;
      }
    }

    return null;
  }

  private captureAliasWildcard(specifier: string, pattern: string): string | null {
    const wildcardIndex = pattern.indexOf("*");
    if (wildcardIndex === -1) {
      return specifier === pattern ? "" : null;
    }

    const prefix = pattern.slice(0, wildcardIndex);
    const suffix = pattern.slice(wildcardIndex + 1);

    if (!specifier.startsWith(prefix) || !specifier.endsWith(suffix)) {
      return null;
    }

    return specifier.slice(prefix.length, specifier.length - suffix.length);
  }

  private normalize(path: string): string {
    const components: string[] = [];

    for (const component of path.split("/").filter((value) => value.length > 0)) {
      switch (component) {
        case ".":
          continue;
        case "..":
          components.pop();
          break;
        default:
          components.push(component);
      }
    }

    return components.join("/");
  }
}

/** Mirrors `NSString.deletingLastPathComponent` for the relative paths used here. */
function deletingLastPathComponent(path: string): string {
  const index = path.lastIndexOf("/");
  return index >= 0 ? path.slice(0, index) : "";
}
