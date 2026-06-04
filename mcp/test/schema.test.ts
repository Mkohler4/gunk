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
  test("creates v0 tables", () => {
    const db = new Database(":memory:");

    expect(runMigrations(db)).toEqual({ from: -1, to: 0 });

    const tables = db
      .query<{ name: string }, []>(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('schema_version', 'gunks', 'files') ORDER BY name",
      )
      .all()
      .map(({ name }) => name);

    expect(tables).toEqual(["files", "gunks", "schema_version"]);
    db.close();
  });

  test("is idempotent", () => {
    const db = new Database(":memory:");

    expect(runMigrations(db)).toEqual({ from: -1, to: 0 });
    expect(runMigrations(db)).toEqual({ from: 0, to: 0 });

    const versionRows = db
      .query<
        { count: number },
        []
      >("SELECT COUNT(*) AS count FROM schema_version")
      .get();

    expect(versionRows?.count).toBe(1);
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
        []
      >("SELECT version, applied_at AS appliedAt FROM schema_version")
      .get();

    expect(version?.version).toBe(0);
    expect(version?.appliedAt).toBeGreaterThan(0);
    expect(version?.appliedAt).toBeGreaterThanOrEqual(before);
    expect(version?.appliedAt).toBeLessThanOrEqual(after);
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
