// Manifest + README writer. Ported from
// app/Sources/GunkApp/Extract/ManifestWriter.swift.

import { homedir } from "node:os";
import { basename } from "node:path";

import type { Gunk } from "../store/index.js";
import type { DetectedLicense } from "./licenseDetector.js";
import { EMPTY_REQUIREMENTS, type ModuleRequirements } from "./requirements.js";
import type { Redaction } from "./secretRedactor.js";

export interface ManifestInput {
  gunk: Gunk;
  tags: string[];
  files: string[];
  sourcePath: string;
  sourceCommit: string | null;
  license: DetectedLicense;
  redactions: Redaction[];
  extractedAtMs: number;
  /** Portability readout persisted into `gunk.yml` (T-10.6). */
  requirements?: ModuleRequirements;
}

export interface ManifestArtifact {
  manifest: string;
  readme: string;
}

function isoNoFraction(ms: number): string {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
}

export class ManifestWriter {
  constructor(private readonly homeDirectory: string = homedir()) {}

  artifact(input: ManifestInput): ManifestArtifact {
    const entrypoints = this.entrypoints(input.files);
    return {
      manifest: this.manifestYAML(input, entrypoints),
      readme: this.readmeMarkdown(input, entrypoints),
    };
  }

  homeRelativePath(path: string): string {
    const home = this.homeDirectory.endsWith("/") ? this.homeDirectory : `${this.homeDirectory}/`;
    if (path === this.homeDirectory) return "~";
    if (path.startsWith(home)) return `~/${path.slice(home.length)}`;
    return `~/${basename(path)}`;
  }

  private manifestYAML(input: ManifestInput, entrypoints: string[]): string {
    const lines: string[] = ["schema_version: 0", `id: ${input.gunk.id}`, `name: ${this.yaml(input.gunk.name)}`];
    this.appendList(input.tags, "tags", lines);
    lines.push(`language: ${this.yamlOptional(input.gunk.language)}`);
    lines.push(`purpose: ${this.yamlOptional(input.gunk.purpose)}`);
    lines.push("deps:");
    lines.push("  package_managers: []");
    lines.push("  packages: []");
    const requirements = input.requirements ?? EMPTY_REQUIREMENTS;
    lines.push("requirements:");
    lines.push(`  runtime: ${this.yamlOptional(requirements.runtime)}`);
    this.appendIndentedList(requirements.packages, "packages", "  ", lines);
    this.appendIndentedList(requirements.env, "env", "  ", lines);
    if (entrypoints.length === 0) {
      lines.push("entrypoints: []");
    } else {
      lines.push("entrypoints:");
      for (const entrypoint of entrypoints) {
        lines.push(`  - path: ${this.yaml(entrypoint)}`);
        lines.push("    symbol: null");
      }
    }
    lines.push("provenance:");
    lines.push(`  source_path: ${this.yaml(input.sourcePath)}`);
    lines.push(`  source_commit: ${this.yamlOptional(input.sourceCommit)}`);
    lines.push("license:");
    lines.push(`  detected: ${this.yaml(input.license.detected)}`);
    lines.push(`  warning: ${this.yamlOptional(input.license.warning)}`);
    lines.push(`confidence: ${input.gunk.confidence ?? 0}`);
    lines.push(`extracted_at: ${this.yaml(isoNoFraction(input.extractedAtMs))}`);

    if (input.redactions.length > 0) {
      lines.push("redactions:");
      for (const redaction of input.redactions) {
        lines.push(`  - path: ${this.yaml(redaction.path)}`);
        lines.push(`    reason: ${this.yaml(redaction.reason)}`);
      }
    }

    return `${lines.join("\n")}\n`;
  }

  private readmeMarkdown(input: ManifestInput, entrypoints: string[]): string {
    const lines: string[] = [`# ${input.gunk.name}`, "", input.gunk.purpose ?? "Extracted reusable gunk module.", ""];
    if (input.tags.length > 0) {
      lines.push(`Tags: ${input.tags.join(", ")}`);
      lines.push("");
    }
    lines.push("## Entrypoints");
    if (entrypoints.length === 0) {
      lines.push("- No confident entrypoints were inferred.");
    } else {
      lines.push(...entrypoints.map((e) => `- \`${e}\``));
    }
    lines.push("");
    lines.push(`Confidence: ${input.gunk.confidence ?? 0}`);
    return `${lines.join("\n")}\n`;
  }

  private entrypoints(files: string[]): string[] {
    const prioritized = files.filter((relpath) => {
      const name = basename(relpath).toLowerCase();
      return (
        name.startsWith("main.") ||
        name.startsWith("index.") ||
        name === "package.swift" ||
        name === "package.json" ||
        name === "pyproject.toml" ||
        name === "cargo.toml" ||
        name === "go.mod" ||
        relpath.toLowerCase().includes("/route.")
      );
    });
    const candidates = prioritized.length === 0 ? files : prioritized;
    return candidates.slice(0, 5);
  }

  private appendList(values: string[], key: string, lines: string[]): void {
    if (values.length === 0) {
      lines.push(`${key}: []`);
      return;
    }
    lines.push(`${key}:`);
    lines.push(...values.map((v) => `  - ${this.yaml(v)}`));
  }

  private appendIndentedList(values: string[], key: string, indent: string, lines: string[]): void {
    if (values.length === 0) {
      lines.push(`${indent}${key}: []`);
      return;
    }
    lines.push(`${indent}${key}:`);
    lines.push(...values.map((v) => `${indent}  - ${this.yaml(v)}`));
  }

  private yamlOptional(value: string | null): string {
    return value === null ? "null" : this.yaml(value);
  }

  private yaml(value: string): string {
    const escaped = value.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n");
    return `"${escaped}"`;
  }
}
