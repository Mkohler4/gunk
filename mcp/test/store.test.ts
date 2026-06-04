import { Database } from "bun:sqlite";
import { afterEach, beforeEach, describe, expect, test } from "vitest";

import { runMigrations } from "../src/schema/index.js";
import {
  getGunk,
  getGunkFiles,
  listGunks,
  listGunkTags,
  listTags,
} from "../src/store/index.js";

describe("store reader", () => {
  let db: Database;

  beforeEach(() => {
    db = new Database(":memory:");
    runMigrations(db);

    db.query(
      "INSERT INTO gunks (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
    ).run(1, "older", "/code/older", 100, null);
    db.query(
      "INSERT INTO gunks (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
    ).run(2, "newer", "/code/newer", 300, null);
    db.query(
      "INSERT INTO gunks (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
    ).run(3, "removed", "/code/removed", 400, 500);

    db.query(
      "INSERT INTO files (id, gunk_id, relpath, size) VALUES (?, ?, ?, ?)",
    ).run(1, 1, "README.md", 128);
    db.query(
      "INSERT INTO files (id, gunk_id, relpath, size) VALUES (?, ?, ?, ?)",
    ).run(2, 1, "src/index.ts", null);
    db.query(
      "INSERT INTO files (id, gunk_id, relpath, size) VALUES (?, ?, ?, ?)",
    ).run(3, 2, "package.json", 256);

    db.query(
      "INSERT INTO gunk_tags (gunk_id, tag, confidence, source, tagged_at) VALUES (?, ?, ?, ?, ?)",
    ).run(1, "auth", 0.9, "manual", 600);
    db.query(
      "INSERT INTO gunk_tags (gunk_id, tag, confidence, source, tagged_at) VALUES (?, ?, ?, ?, ?)",
    ).run(1, "api", 0.7, "heuristic", 500);
    db.query(
      "INSERT INTO gunk_tags (gunk_id, tag, confidence, source, tagged_at) VALUES (?, ?, ?, ?, ?)",
    ).run(2, "payments", 0.8, "llm", 700);
  });

  afterEach(() => {
    db.close();
  });

  test("listGunks returns rows in dropped_at desc order", () => {
    expect(listGunks(db).map(({ id }) => id)).toEqual([2, 1]);
  });

  test("listGunks excludes rows with removed_at set", () => {
    expect(listGunks(db).map(({ name }) => name)).not.toContain("removed");
  });

  test("getGunk returns null for unknown id", () => {
    expect(getGunk(db, 999)).toBeNull();
  });

  test("getGunk returns full record for known id", () => {
    expect(getGunk(db, 1)).toEqual({
      id: 1,
      name: "older",
      path: "/code/older",
      droppedAt: 100,
      removedAt: null,
    });
  });

  test("getGunkFiles returns rows for that gunk only", () => {
    expect(getGunkFiles(db, 1)).toEqual([
      {
        id: 1,
        gunkId: 1,
        relpath: "README.md",
        size: 128,
      },
      {
        id: 2,
        gunkId: 1,
        relpath: "src/index.ts",
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
    expect(listGunkTags(db, 1)).toEqual([
      {
        gunkId: 1,
        tag: "auth",
        confidence: 0.9,
        source: "manual",
        taggedAt: 600,
      },
      {
        gunkId: 1,
        tag: "api",
        confidence: 0.7,
        source: "heuristic",
        taggedAt: 500,
      },
    ]);
  });
});
