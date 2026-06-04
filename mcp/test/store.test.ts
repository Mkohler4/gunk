import { Database } from "bun:sqlite";
import { afterEach, beforeEach, describe, expect, test } from "vitest";

import { runMigrations } from "../src/schema/index.js";
import { getGunk, getGunkFiles, listGunks } from "../src/store/index.js";

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
});
