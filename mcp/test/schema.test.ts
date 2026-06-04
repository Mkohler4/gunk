import { Database } from "bun:sqlite";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";

import { openStore, runMigrations } from "../src/schema/index.js";

const temporaryDirectories: string[] = [];

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { force: true, recursive: true });
  }
});

describe("runMigrations", () => {
  test("creates v1 tables", () => {
    const db = new Database(":memory:");

    expect(runMigrations(db)).toEqual({ from: -1, to: 1 });

    const tables = db
      .query<{ name: string }, []>(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('schema_version', 'gunks', 'files', 'tags', 'gunk_tags') ORDER BY name",
      )
      .all()
      .map(({ name }) => name);

    expect(tables).toEqual([
      "files",
      "gunk_tags",
      "gunks",
      "schema_version",
      "tags",
    ]);
    db.close();
  });

  test("is idempotent", () => {
    const db = new Database(":memory:");

    expect(runMigrations(db)).toEqual({ from: -1, to: 1 });
    expect(runMigrations(db)).toEqual({ from: 1, to: 1 });

    const versionRows = db
      .query<
        { count: number },
        []
      >("SELECT COUNT(*) AS count FROM schema_version")
      .get();

    expect(versionRows?.count).toBe(2);
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
      .get(1);

    expect(version?.version).toBe(1);
    expect(version?.appliedAt).toBeGreaterThan(0);
    expect(version?.appliedAt).toBeGreaterThanOrEqual(before);
    expect(version?.appliedAt).toBeLessThanOrEqual(after);
    db.close();
  });

  test("migrates an existing v0 database to v1", () => {
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
    `);

    expect(runMigrations(db)).toEqual({ from: 0, to: 1 });

    const version = db
      .query<
        { version: number },
        []
      >("SELECT MAX(version) AS version FROM schema_version")
      .get();

    const tagCount = db
      .query<{ count: number }, []>("SELECT COUNT(*) AS count FROM tags")
      .get();

    expect(version?.version).toBe(1);
    expect(tagCount?.count).toBe(10);
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
