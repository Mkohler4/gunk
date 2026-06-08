import { Database } from "bun:sqlite";
import { copyFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";

import v0Sql from "../src/schema/v0.sql" with { type: "text" };
import v1Sql from "../src/schema/v1.sql" with { type: "text" };
import { openStore, runMigrations } from "../src/schema/index.js";

const temporaryDirectories: string[] = [];

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { force: true, recursive: true });
  }
});

describe("runMigrations", () => {
  test("creates module-level schema tables", () => {
    const db = new Database(":memory:");

    expect(runMigrations(db)).toEqual({ from: -1, to: 4 });

    const tables = db
      .query<{ name: string }, []>(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('schema_version', 'sources', 'files', 'gunks', 'tags', 'gunk_tags', 'gunk_files', 'gunk_embeddings', 'gunk_clusters', 'llm_runs') ORDER BY name",
      )
      .all()
      .map(({ name }) => name);

    expect(tables).toEqual([
      "files",
      "gunk_clusters",
      "gunk_embeddings",
      "gunk_files",
      "gunk_tags",
      "gunks",
      "llm_runs",
      "schema_version",
      "sources",
      "tags",
    ]);
    db.close();
  });

  test("is idempotent", () => {
    const db = new Database(":memory:");

    expect(runMigrations(db)).toEqual({ from: -1, to: 4 });
    expect(runMigrations(db)).toEqual({ from: 4, to: 4 });

    const versionRows = db
      .query<
        { count: number },
        []
      >("SELECT COUNT(*) AS count FROM schema_version")
      .get();

    expect(versionRows?.count).toBe(5);
    db.close();
  });

  test("records schema_version with a sane timestamp", () => {
    const db = new Database(":memory:");
    const before = Date.now();

    runMigrations(db);

    const after = Date.now();
    const version = db
      .query<
        { appliedAt: number; version: number },
        [number]
      >("SELECT version, applied_at AS appliedAt FROM schema_version WHERE version = ?")
      .get(4);

    expect(version?.version).toBe(4);
    expect(version?.appliedAt).toBeGreaterThan(0);
    expect(version?.appliedAt).toBeGreaterThanOrEqual(before);
    expect(version?.appliedAt).toBeLessThanOrEqual(after);
    db.close();
  });

  test("v0 store upgrades to module schema preserving sources rows", () => {
    const db = new Database(":memory:");

    db.exec(`
      CREATE TABLE schema_version (
        version INTEGER PRIMARY KEY,
        applied_at INTEGER NOT NULL
      );

      CREATE TABLE gunks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        path TEXT NOT NULL UNIQUE,
        dropped_at INTEGER NOT NULL,
        removed_at INTEGER
      );

      CREATE TABLE files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gunk_id INTEGER NOT NULL REFERENCES gunks(id) ON DELETE CASCADE,
        relpath TEXT NOT NULL,
        size INTEGER,
        UNIQUE(gunk_id, relpath)
      );

      INSERT INTO schema_version (version, applied_at) VALUES (0, 100);
      INSERT INTO gunks (id, name, path, dropped_at, removed_at)
      VALUES (1, 'older-source', '/code/older-source', 200, NULL);
      INSERT INTO files (id, gunk_id, relpath, size)
      VALUES (1, 1, 'README.md', 128);
    `);

    expect(runMigrations(db)).toEqual({ from: 0, to: 4 });

    const version = db
      .query<
        { version: number },
        []
      >("SELECT MAX(version) AS version FROM schema_version")
      .get();

    const source = db
      .query<
        { id: number; name: string; path: string; droppedAt: number },
        []
      >("SELECT id, name, path, dropped_at AS droppedAt FROM sources")
      .get();

    const file = db
      .query<
        { sourceId: number; relpath: string; size: number },
        []
      >("SELECT source_id AS sourceId, relpath, size FROM files")
      .get();

    expect(version?.version).toBe(4);
    expect(source).toEqual({
      id: 1,
      name: "older-source",
      path: "/code/older-source",
      droppedAt: 200,
    });
    expect(file).toEqual({
      sourceId: 1,
      relpath: "README.md",
      size: 128,
    });
    db.close();
  });

  test("real on-disk v0 fixture upgrades to module schema preserving sources", () => {
    const directory = mkdtempSync(join(tmpdir(), "gunk-schema-fixture-"));
    temporaryDirectories.push(directory);

    const fixturePath = join(directory, "store.db");
    copyFileSync(join("test", "fixtures", "store-v0.db"), fixturePath);

    const db = openStore(fixturePath);
    const source = db
      .query<
        { id: number; name: string; path: string; droppedAt: number },
        []
      >("SELECT id, name, path, dropped_at AS droppedAt FROM sources")
      .get();

    const files = db
      .query<
        { sourceId: number; relpath: string; size: number },
        []
      >("SELECT source_id AS sourceId, relpath, size FROM files ORDER BY relpath")
      .all();

    expect(source).toEqual({
      id: 1,
      name: "fixture-source",
      path: "/tmp/gunk-fixture-source",
      droppedAt: 2000,
    });
    expect(files).toEqual([
      { sourceId: 1, relpath: "README.md", size: 12 },
      { sourceId: 1, relpath: "src/index.ts", size: 34 },
    ]);
    db.close();
  });

  test("existing v1 store upgrades to module schema preserving sources", () => {
    const db = new Database(":memory:");

    db.exec(v0Sql);
    db.query(
      "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
    ).run(0, 100);
    db.query(
      "INSERT INTO gunks (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
    ).run(1, "v1-source", "/code/v1-source", 200, null);
    db.query(
      "INSERT INTO files (id, gunk_id, relpath, size) VALUES (?, ?, ?, ?)",
    ).run(1, 1, "package.json", 64);
    db.exec(v1Sql);
    db.query(
      "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
    ).run(1, 150);

    expect(runMigrations(db)).toEqual({ from: 1, to: 4 });

    const source = db
      .query<
        { name: string; path: string },
        []
      >("SELECT name, path FROM sources")
      .get();
    const file = db
      .query<
        { relpath: string; size: number },
        []
      >("SELECT relpath, size FROM files")
      .get();

    expect(source).toEqual({ name: "v1-source", path: "/code/v1-source" });
    expect(file).toEqual({ relpath: "package.json", size: 64 });
    db.close();
  });

  test("seeds the classifier tag taxonomy", () => {
    const db = new Database(":memory:");

    runMigrations(db);

    const tags = db
      .query<{ name: string }, []>("SELECT name FROM tags ORDER BY name ASC")
      .all()
      .map(({ name }) => name);

    expect(tags).toEqual([
      "api",
      "auth",
      "cli",
      "dashboard",
      "db-layer",
      "email",
      "mobile",
      "payments",
      "scraper",
      "search",
      "ui-kit",
    ]);
    db.close();
  });
});

describe("openStore", () => {
  test("enables WAL mode", () => {
    const directory = mkdtempSync(join(tmpdir(), "gunk-schema-"));
    temporaryDirectories.push(directory);

    const db = openStore(join(directory, "store.db"));
    const journalMode = db
      .query<{ journal_mode: string }, []>("PRAGMA journal_mode")
      .get();

    expect(journalMode?.journal_mode).toBe("wal");
    db.close();
  });
});
