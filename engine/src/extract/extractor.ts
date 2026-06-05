// Module bundle extractor. Ported from
// app/Sources/GunkApp/Extract/Extractor.swift.

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";

import {
  filesForGunk,
  listGunkTags,
  markGunkExtracted,
  sourceById,
  type Gunk,
} from "../store/index.js";
import type { Database } from "bun:sqlite";
import { LicenseDetector } from "./licenseDetector.js";
import { ManifestWriter } from "./manifestWriter.js";
import { SecretRedactor, type Redaction } from "./secretRedactor.js";

export interface ExtractionResult {
  bundlePath: string;
  manifestPath: string;
  readmePath: string;
  redactions: Redaction[];
}

export class ExtractorError extends Error {
  constructor(
    message: string,
    readonly code: "sourceNotFound" | "invalidRelativePath" | "sourceFileOutsideRoot",
  ) {
    super(message);
    this.name = "ExtractorError";
  }
}

export interface ExtractorOptions {
  gunkHome?: string;
  confidenceThreshold?: number;
  redactor?: SecretRedactor;
  manifestWriter?: ManifestWriter;
  licenseDetector?: LicenseDetector;
  now?: () => number;
}

export class Extractor {
  static readonly defaultConfidenceThreshold = 0.7;

  private readonly gunkHome: string;
  private readonly confidenceThreshold: number;
  private readonly redactor: SecretRedactor;
  private readonly manifestWriter: ManifestWriter;
  private readonly licenseDetector: LicenseDetector;
  private readonly now: () => number;

  constructor(
    private readonly db: Database,
    options: ExtractorOptions = {},
  ) {
    this.gunkHome = resolve(options.gunkHome ?? join(homedir(), ".gunk"));
    this.confidenceThreshold = options.confidenceThreshold ?? Extractor.defaultConfidenceThreshold;
    this.redactor = options.redactor ?? new SecretRedactor();
    this.manifestWriter = options.manifestWriter ?? new ManifestWriter();
    this.licenseDetector = options.licenseDetector ?? new LicenseDetector();
    this.now = options.now ?? Date.now;
  }

  extract(gunk: Gunk): ExtractionResult | null {
    if ((gunk.confidence ?? 0) < this.confidenceThreshold) {
      return null;
    }
    const source = sourceById(this.db, gunk.sourceId);
    if (!source) {
      throw new ExtractorError(`Source ${gunk.sourceId} not found.`, "sourceNotFound");
    }

    const sourceRoot = resolve(source.path);
    const bundlePath = join(this.gunkHome, "modules", String(gunk.id));
    const manifestPath = join(bundlePath, "gunk.yml");
    const readmePath = join(bundlePath, "README.gunk.md");
    const gunkFiles = filesForGunk(this.db, gunk.id);
    const tags = listGunkTags(this.db, gunk.id).map((t) => t.tag);
    const redactions: Redaction[] = [];

    if (existsSync(bundlePath)) {
      rmSync(bundlePath, { recursive: true, force: true });
    }
    mkdirSync(bundlePath, { recursive: true });

    for (const file of gunkFiles) {
      this.copyFile(file.relpath, sourceRoot, bundlePath, redactions);
    }

    const extractedAt = this.now();
    const artifact = this.manifestWriter.artifact({
      gunk,
      tags,
      files: gunkFiles.map((f) => f.relpath),
      sourcePath: this.manifestWriter.homeRelativePath(source.path),
      sourceCommit: this.shortCommitHash(sourceRoot),
      license: this.licenseDetector.detect(sourceRoot),
      redactions,
      extractedAtMs: extractedAt,
    });

    writeFileSync(manifestPath, artifact.manifest, "utf-8");
    writeFileSync(readmePath, artifact.readme, "utf-8");
    markGunkExtracted(this.db, gunk.id, bundlePath, manifestPath, extractedAt);

    return { bundlePath, manifestPath, readmePath, redactions };
  }

  private copyFile(relpath: string, sourceRoot: string, bundleRoot: string, redactions: Redaction[]): void {
    this.validateRelativePath(relpath);
    const sourceURL = resolve(sourceRoot, relpath);
    const sourceRootPath = sourceRoot.endsWith("/") ? sourceRoot : `${sourceRoot}/`;
    if (!sourceURL.startsWith(sourceRootPath)) {
      throw new ExtractorError(`Source file outside root: ${relpath}`, "sourceFileOutsideRoot");
    }
    const result = this.redactor.redact(sourceURL, relpath);
    redactions.push(...result.redactions);
    if (result.kind !== "write") return;
    const destination = join(bundleRoot, relpath);
    mkdirSync(dirname(destination), { recursive: true });
    writeFileSync(destination, result.data);
  }

  private validateRelativePath(relpath: string): void {
    const normalized = relpath.replace(/\\/g, "/");
    if (normalized.startsWith("/") || normalized.length === 0 || normalized.split("/").includes("..")) {
      throw new ExtractorError(`Invalid relative path: ${relpath}`, "invalidRelativePath");
    }
  }

  private shortCommitHash(sourceRoot: string): string | null {
    try {
      const result = spawnSync("git", ["-C", sourceRoot, "rev-parse", "--short", "HEAD"], { encoding: "utf-8" });
      if (result.status !== 0) return null;
      const hash = result.stdout.trim();
      return hash.length === 0 ? null : hash;
    } catch {
      return null;
    }
  }
}
