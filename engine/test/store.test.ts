import { Database } from "bun:sqlite";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  addGunkFile,
  addGunkTag,
  addSourceFile,
  cosineSimilarity,
  decodeVector,
  encodeVector,
  filesForSource,
  gunkEmbedding,
  insertGunk,
  insertSource,
  listGunkTags,
  listTags,
  recordLLMRun,
  runMigrations,
  upsertGunkEmbedding,
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
