import { Database } from "bun:sqlite";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  addGunkFile,
  addGunkTag,
  gunkById,
  insertGunk,
  insertSource,
  listTags,
  runMigrations,
} from "../src/store/index.js";
import { Extractor } from "../src/extract/extractor.js";
import { SecretRedactor } from "../src/extract/secretRedactor.js";
import { LicenseDetector } from "../src/extract/licenseDetector.js";
import { ManifestWriter } from "../src/extract/manifestWriter.js";
import { EmbeddingIndex } from "../src/search/embeddingIndex.js";
import type { EmbeddingProvider } from "../src/llm/embeddings.js";

describe("SecretRedactor", () => {
  let dir: string;
  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), "gunk-redact-"));
  });
  afterEach(() => rmSync(dir, { recursive: true, force: true }));

  it("skips secret-named files", () => {
    const file = join(dir, ".env");
    writeFileSync(file, "API_KEY=abc");
    const result = new SecretRedactor().redact(file, ".env");
    expect(result.kind).toBe("skip");
    expect(result.redactions[0].reason).toBe("secret_filename");
  });

  it("redacts secret-like content lines", () => {
    const file = join(dir, "config.ts");
    writeFileSync(file, "const x = 1\nconst apiKey = 'sk-abcdefghijklmnop12345'\n");
    const result = new SecretRedactor().redact(file, "config.ts");
    expect(result.kind).toBe("write");
    if (result.kind === "write") {
      expect(result.data.toString("utf-8")).toContain("[gunk redacted: secret-like content]");
      expect(result.redactions[0].reason).toBe("secret_like_content");
    }
  });

  it("passes clean files through unchanged", () => {
    const file = join(dir, "clean.ts");
    writeFileSync(file, "export const greet = () => 'hi'\n");
    const result = new SecretRedactor().redact(file, "clean.ts");
    expect(result.kind).toBe("write");
    expect(result.redactions).toHaveLength(0);
  });
});

describe("LicenseDetector", () => {
  let dir: string;
  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), "gunk-lic-"));
  });
  afterEach(() => rmSync(dir, { recursive: true, force: true }));

  it("detects MIT", () => {
    writeFileSync(join(dir, "LICENSE"), "MIT License\n\nPermission is hereby granted...");
    expect(new LicenseDetector().detect(dir).detected).toBe("MIT");
  });

  it("flags GPL as restrictive", () => {
    writeFileSync(join(dir, "LICENSE.txt"), "GNU GENERAL PUBLIC LICENSE Version 3");
    const result = new LicenseDetector().detect(dir);
    expect(result.detected).toBe("GPL-3.0-or-later");
    expect(result.warning).toContain("Restrictive");
  });

  it("returns unknown when absent", () => {
    expect(new LicenseDetector().detect(dir).detected).toBe("unknown");
  });
});

describe("ManifestWriter", () => {
  it("renders gunk.yml and README", () => {
    const writer = new ManifestWriter("/home/me");
    const artifact = writer.artifact({
      gunk: {
        id: 7,
        sourceId: 1,
        name: "Auth",
        purpose: "Login",
        language: "typeScript",
        confidence: 0.9,
        bundlePath: null,
        manifestPath: null,
        extractedAt: null,
        approvedAt: null,
        removedAt: null,
      },
      tags: ["auth"],
      files: ["src/index.ts", "src/login.ts"],
      sourcePath: "~/proj",
      sourceCommit: "abc1234",
      license: { detected: "MIT", warning: null },
      redactions: [{ path: "src/login.ts", reason: "secret_like_content" }],
      extractedAtMs: 0,
    });
    expect(artifact.manifest).toContain("schema_version: 0");
    expect(artifact.manifest).toContain('name: "Auth"');
    expect(artifact.manifest).toContain("extracted_at: \"1970-01-01T00:00:00Z\"");
    expect(artifact.manifest).toContain("entrypoints:");
    expect(artifact.manifest).toContain("reason: \"secret_like_content\"");
    expect(artifact.readme).toContain("# Auth");
  });

  it("maps home-relative paths", () => {
    const writer = new ManifestWriter("/home/me");
    expect(writer.homeRelativePath("/home/me/proj")).toBe("~/proj");
    expect(writer.homeRelativePath("/home/me")).toBe("~");
    expect(writer.homeRelativePath("/var/x")).toBe("~/x");
  });
});

describe("Extractor", () => {
  let db: Database;
  let sourceDir: string;
  let gunkHome: string;

  beforeEach(() => {
    db = new Database(":memory:");
    db.exec("PRAGMA foreign_keys = ON;");
    runMigrations(db);
    sourceDir = mkdtempSync(join(tmpdir(), "gunk-src-"));
    gunkHome = mkdtempSync(join(tmpdir(), "gunk-home-"));
    mkdirSync(join(sourceDir, "src"), { recursive: true });
    writeFileSync(join(sourceDir, "src", "login.ts"), "export function login() { return 1 }\n");
    writeFileSync(join(sourceDir, "LICENSE"), "MIT License\nPermission is hereby granted");
  });

  afterEach(() => {
    db.close();
    rmSync(sourceDir, { recursive: true, force: true });
    rmSync(gunkHome, { recursive: true, force: true });
  });

  it("copies files, writes a manifest, and records extraction", () => {
    const source = insertSource(db, "demo", sourceDir, 100);
    const gunk = insertGunk(db, {
      sourceId: source.id,
      name: "Login",
      purpose: "Handles login",
      language: "typeScript",
      confidence: 0.9,
    });
    addGunkTag(db, gunk.id, listTags(db).find((t) => t.name === "auth")!.id, 0.9);
    addGunkFile(db, gunk.id, "src/login.ts", 40);

    const result = new Extractor(db, { gunkHome, now: () => 0 }).extract(gunk)!;
    expect(result).not.toBeNull();
    expect(existsSync(join(result.bundlePath, "src/login.ts"))).toBe(true);
    const manifest = readFileSync(result.manifestPath, "utf-8");
    expect(manifest).toContain('name: "Login"');
    expect(manifest).toContain('detected: "MIT"');
    expect(gunkById(db, gunk.id)!.bundlePath).toBe(result.bundlePath);
  });

  it("skips low-confidence gunks", () => {
    const source = insertSource(db, "demo2", sourceDir, 100);
    const gunk = insertGunk(db, {
      sourceId: source.id,
      name: "Weak",
      purpose: null,
      language: "typeScript",
      confidence: 0.5,
    });
    addGunkFile(db, gunk.id, "src/login.ts", 40);
    expect(new Extractor(db, { gunkHome }).extract(gunk)).toBeNull();
  });
});

describe("EmbeddingIndex", () => {
  let db: Database;
  beforeEach(() => {
    db = new Database(":memory:");
    db.exec("PRAGMA foreign_keys = ON;");
    runMigrations(db);
  });
  afterEach(() => db.close());

  it("indexes a gunk into the store", async () => {
    const source = insertSource(db, "demo", "/tmp/x", 100);
    const gunk = insertGunk(db, {
      sourceId: source.id,
      name: "Auth",
      purpose: "Login",
      language: "typeScript",
      confidence: 0.9,
    });
    addGunkFile(db, gunk.id, "src/login.ts", 10);
    const fake: EmbeddingProvider = {
      model: "fake-embed",
      embed: async () => [0.1, 0.2, 0.3],
    };
    const embedding = await new EmbeddingIndex(db, fake).index(gunk);
    expect(embedding.dim).toBe(3);
    expect(embedding.model).toBe("fake-embed");
  });
});
