import { Database } from "bun:sqlite";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  addGunkFile,
  addGunkTag,
  addSourceFile,
  clearGunksForSource,
  cosineSimilarity,
  decodeVector,
  encodeVector,
  filesForGunk,
  filesForSource,
  gunkEmbedding,
  gunksForSource,
  insertGunk,
  insertSource,
  listGunkTags,
  listTags,
  markGunkExtracted,
  recordLLMRun,
  runMigrations,
  upsertGunkEmbedding,
  upsertTag,
} from "../src/store/index.js";

describe("engine store", () => {
  let db: Database;

  beforeEach(() => {
    db = new Database(":memory:");
    db.exec("PRAGMA foreign_keys = ON;");
    runMigrations(db);
  });

  afterEach(() => {
    db.close();
  });

  it("migrates to v4 and seeds tags", () => {
    expect(listTags(db).map((t) => t.name)).toContain("auth");
    expect(listTags(db).map((t) => t.name)).toContain("mobile");
  });

  it("inserts sources, files, gunks, tags and reads them back", () => {
    const source = insertSource(db, "demo", "/tmp/demo", 1000);
    addSourceFile(db, source.id, "src/a.ts", 10);
    expect(filesForSource(db, source.id).map((f) => f.relpath)).toEqual(["src/a.ts"]);

    const gunk = insertGunk(db, {
      sourceId: source.id,
      name: "auth-login",
      purpose: "Login flow",
      language: "typeScript",
      confidence: 0.9,
    });
    const authTag = listTags(db).find((t) => t.name === "auth")!;
    addGunkTag(db, gunk.id, authTag.id, 0.9);
    addGunkFile(db, gunk.id, "src/a.ts", 10);

    expect(listGunkTags(db, gunk.id).map((t) => t.tag)).toEqual(["auth"]);
    recordLLMRun(db, {
      sourceId: source.id,
      provider: "OpenAI",
      model: "gpt-4.1-mini",
      inputTokens: 100,
      outputTokens: 50,
      startedAt: 1,
      finishedAt: 2,
    });
  });

  it("upsertTag creates a new tag and is idempotent", () => {
    const before = listTags(db).length;
    const created = upsertTag(db, "orders");
    expect(created.name).toBe("orders");
    expect(listTags(db).map((t) => t.name)).toContain("orders");
    expect(listTags(db).length).toBe(before + 1);

    const again = upsertTag(db, "orders");
    expect(again.id).toBe(created.id);
    expect(listTags(db).length).toBe(before + 1);
  });

  it("links a novel AI-created tag to a gunk", () => {
    const source = insertSource(db, "demo", "/tmp/demo-novel", 1000);
    const gunk = insertGunk(db, {
      sourceId: source.id,
      name: "report-export",
      purpose: "CSV report export",
      language: "java",
      confidence: 0.8,
    });
    const tag = upsertTag(db, "reports");
    addGunkTag(db, gunk.id, tag.id, 0.8);
    expect(listGunkTags(db, gunk.id).map((t) => t.tag)).toEqual(["reports"]);
  });

  it("clearGunksForSource replaces a source's modules and reports bundle paths", () => {
    const source = insertSource(db, "demo", "/tmp/demo-replace", 1000);
    const first = insertGunk(db, {
      sourceId: source.id,
      name: "stale-module",
      purpose: "from an earlier run",
      language: "typeScript",
      confidence: 0.9,
    });
    const authTag = listTags(db).find((t) => t.name === "auth")!;
    addGunkTag(db, first.id, authTag.id, 0.9);
    addGunkFile(db, first.id, "src/a.ts", 10);
    upsertGunkEmbedding(db, first.id, [0.1, 0.2], "text-embedding-3-small");
    markGunkExtracted(db, first.id, "/home/.gunk/modules/1", "/home/.gunk/modules/1/gunk.yml");

    const cleared = clearGunksForSource(db, source.id);
    expect(cleared.removed).toBe(1);
    expect(cleared.bundlePaths).toEqual(["/home/.gunk/modules/1"]);

    // Gunk + all dependent rows are gone (cascade), source itself survives.
    expect(gunksForSource(db, source.id)).toEqual([]);
    expect(listGunkTags(db, first.id)).toEqual([]);
    expect(gunkEmbedding(db, first.id)).toBeNull();
    expect(filesForGunk(db, first.id)).toEqual([]);

    // A fresh run can now persist without accumulating the stale module.
    const second = insertGunk(db, {
      sourceId: source.id,
      name: "fresh-module",
      purpose: "from the re-run",
      language: "typeScript",
      confidence: 0.9,
    });
    expect(gunksForSource(db, source.id).map((g) => g.name)).toEqual(["fresh-module"]);
    expect(second.id).not.toBe(first.id);
  });

  it("round-trips embedding vectors as little-endian float32", () => {
    const source = insertSource(db, "demo", "/tmp/demo2", 1000);
    const gunk = insertGunk(db, {
      sourceId: source.id,
      name: "g",
      purpose: null,
      language: null,
      confidence: 0.5,
    });
    const vector = [0.1, 0.2, 0.3, -0.4];
    upsertGunkEmbedding(db, gunk.id, vector, "text-embedding-3-small");
    const stored = gunkEmbedding(db, gunk.id)!;
    expect(stored.dim).toBe(4);
    stored.vector.forEach((v, i) => expect(v).toBeCloseTo(vector[i], 5));
    expect(cosineSimilarity(stored.vector, vector)).toBeCloseTo(1, 5);
  });

  it("encode/decode are inverse", () => {
    const v = [1, 2, 3];
    expect(decodeVector(encodeVector(v), 3)).toEqual(v);
  });
});
