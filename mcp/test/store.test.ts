import { Database } from "bun:sqlite";
import { afterEach, beforeEach, describe, expect, test } from "vitest";

import { runMigrations } from "../src/schema/index.js";
import {
  getGunk,
  getGunkFiles,
  listGunks,
  listGunkTags,
  listSources,
  listTags,
} from "../src/store/index.js";

describe("store reader", () => {
  let db: Database;

  beforeEach(() => {
    db = new Database(":memory:");
    runMigrations(db);

    db.query(
      "INSERT INTO sources (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
    ).run(1, "source", "/code/source", 100, null);
    db.query(
      "INSERT INTO sources (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
    ).run(2, "removed-source", "/code/removed-source", 200, 300);

    db.query(
      "INSERT INTO files (id, source_id, relpath, size) VALUES (?, ?, ?, ?)",
    ).run(1, 1, "README.md", 128);

    db.query(
      "INSERT INTO gunks (id, source_id, name, purpose, language, confidence, bundle_path, manifest_path, extracted_at, approved_at, removed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    ).run(
      1,
      1,
      "auth-module",
      "Google OAuth flow",
      "TypeScript",
      0.9,
      "/tmp/modules/1",
      "/tmp/modules/1/gunk.yml",
      400,
      null,
      null,
    );
    db.query(
      "INSERT INTO gunks (id, source_id, name, purpose, language, confidence, bundle_path, manifest_path, extracted_at, approved_at, removed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    ).run(
      2,
      1,
      "payments-module",
      null,
      null,
      0.7,
      null,
      null,
      null,
      null,
      null,
    );
    db.query(
      "INSERT INTO gunks (id, source_id, name, purpose, language, confidence, bundle_path, manifest_path, extracted_at, approved_at, removed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    ).run(
      3,
      1,
      "removed-module",
      null,
      null,
      null,
      null,
      null,
      null,
      null,
      500,
    );

    db.query(
      "INSERT INTO gunk_files (id, gunk_id, relpath, size) VALUES (?, ?, ?, ?)",
    ).run(1, 1, "auth.ts", 256);
    db.query(
      "INSERT INTO gunk_files (id, gunk_id, relpath, size) VALUES (?, ?, ?, ?)",
    ).run(2, 1, "oauth.ts", null);

    const authTag = db
      .query<{ id: number }, []>("SELECT id FROM tags WHERE name = 'auth'")
      .get();
    const apiTag = db
      .query<{ id: number }, []>("SELECT id FROM tags WHERE name = 'api'")
      .get();

    expect(authTag).toBeDefined();
    expect(apiTag).toBeDefined();

    db.query(
      "INSERT INTO gunk_tags (gunk_id, tag_id, confidence) VALUES (?, ?, ?)",
    ).run(1, authTag!.id, 0.9);
    db.query(
      "INSERT INTO gunk_tags (gunk_id, tag_id, confidence) VALUES (?, ?, ?)",
    ).run(1, apiTag!.id, 0.7);
  });

  afterEach(() => {
    db.close();
  });

  test("listSources returns active rows in dropped_at desc order", () => {
    expect(listSources(db)).toEqual([
      {
        id: 1,
        name: "source",
        path: "/code/source",
        droppedAt: 100,
        removedAt: null,
      },
    ]);
  });

  test("listGunks returns active modules in id desc order", () => {
    expect(listGunks(db).map(({ id }) => id)).toEqual([2, 1]);
  });

  test("listGunks excludes rows with removed_at set", () => {
    expect(listGunks(db).map(({ name }) => name)).not.toContain(
      "removed-module",
    );
  });

  test("getGunk returns null for unknown id", () => {
    expect(getGunk(db, 999)).toBeNull();
  });

  test("getGunk returns full module record for known id", () => {
    expect(getGunk(db, 1)).toEqual({
      id: 1,
      sourceId: 1,
      name: "auth-module",
      purpose: "Google OAuth flow",
      language: "TypeScript",
      confidence: 0.9,
      bundlePath: "/tmp/modules/1",
      manifestPath: "/tmp/modules/1/gunk.yml",
      extractedAt: 400,
      approvedAt: null,
      removedAt: null,
    });
  });

  test("getGunkFiles returns module file rows for that gunk only", () => {
    expect(getGunkFiles(db, 1)).toEqual([
      {
        id: 1,
        gunkId: 1,
        relpath: "auth.ts",
        size: 256,
      },
      {
        id: 2,
        gunkId: 1,
        relpath: "oauth.ts",
        size: null,
      },
    ]);
  });

  test("listTags returns the seeded taxonomy", () => {
    expect(listTags(db).map(({ name }) => name)).toEqual([
      "api",
      "auth",
      "cli",
      "dashboard",
      "db-layer",
      "email",
      "payments",
      "scraper",
      "search",
      "ui-kit",
    ]);
  });

  test("listGunkTags returns tags for that gunk ordered by confidence", () => {
    const tags = listGunkTags(db, 1);

    expect(tags.map(({ tag, confidence }) => ({ tag, confidence }))).toEqual([
      { tag: "auth", confidence: 0.9 },
      { tag: "api", confidence: 0.7 },
    ]);
    expect(tags.map(({ gunkId }) => gunkId)).toEqual([1, 1]);
  });
});
