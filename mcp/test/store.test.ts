import { Database } from "bun:sqlite";
import { afterEach, beforeEach, describe, expect, test } from "vitest";

import { runMigrations } from "../src/schema/index.js";
import {
  getGunk,
  listGunks,
  listSources,
  searchGunks,
} from "../src/store/index.js";

describe("store reader", () => {
  let db: Database;

  beforeEach(() => {
    db = new Database(":memory:");
    runMigrations(db);
    seedStore(db);
  });

  afterEach(() => {
    db.close();
  });

  test("listGunks returns modules with tags", () => {
    expect(listGunks(db)).toEqual([
      {
        id: 2,
        sourceId: 1,
        name: "cli-tools",
        purpose: "Command line maintenance helpers",
        language: "TypeScript",
        confidence: 0.82,
        tags: ["cli"],
        bundlePath: "/tmp/modules/2",
        manifestPath: "/tmp/modules/2/gunk.yml",
        extractedAt: 450,
        approvedAt: null,
        removedAt: null,
      },
      {
        id: 1,
        sourceId: 1,
        name: "auth-module",
        purpose: "Google OAuth flow",
        language: "TypeScript",
        confidence: 0.9,
        tags: ["auth", "api"],
        bundlePath: "/tmp/modules/1",
        manifestPath: "/tmp/modules/1/gunk.yml",
        extractedAt: 400,
        approvedAt: null,
        removedAt: null,
      },
    ]);
  });

  test("searchGunks matches by tag and name", () => {
    expect(searchGunks(db, "auth").map(({ id }) => id)).toEqual([1]);
    expect(searchGunks(db, "CLI").map(({ id }) => id)).toEqual([2]);
    expect(searchGunks(db, "oauth").map(({ id }) => id)).toEqual([1]);
  });

  test("getGunk returns module with files", () => {
    expect(getGunk(db, 1)).toEqual({
      id: 1,
      sourceId: 1,
      name: "auth-module",
      purpose: "Google OAuth flow",
      language: "TypeScript",
      confidence: 0.9,
      tags: ["auth", "api"],
      bundlePath: "/tmp/modules/1",
      manifestPath: "/tmp/modules/1/gunk.yml",
      extractedAt: 400,
      approvedAt: null,
      removedAt: null,
      files: [
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
      ],
    });
  });

  test("excludes removed and unextracted modules", () => {
    expect(listSources(db).map(({ name }) => name)).toEqual(["source"]);
    expect(listGunks(db).map(({ name }) => name)).toEqual([
      "cli-tools",
      "auth-module",
    ]);
    expect(searchGunks(db, "payments")).toEqual([]);
    expect(getGunk(db, 3)).toBeNull();
    expect(getGunk(db, 4)).toBeNull();
  });
});

function seedStore(db: Database): void {
  db.query(
    "INSERT INTO sources (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
  ).run(1, "source", "/code/source", 100, null);
  db.query(
    "INSERT INTO sources (id, name, path, dropped_at, removed_at) VALUES (?, ?, ?, ?, ?)",
  ).run(2, "removed-source", "/code/removed-source", 200, 300);

  insertGunk(db, {
    id: 1,
    name: "auth-module",
    purpose: "Google OAuth flow",
    confidence: 0.9,
    bundlePath: "/tmp/modules/1",
    extractedAt: 400,
  });
  insertGunk(db, {
    id: 2,
    name: "cli-tools",
    purpose: "Command line maintenance helpers",
    confidence: 0.82,
    bundlePath: "/tmp/modules/2",
    extractedAt: 450,
  });
  insertGunk(db, {
    id: 3,
    name: "payments-unextracted",
    purpose: "Stripe payment form",
    confidence: 0.68,
  });
  insertGunk(db, {
    id: 4,
    name: "removed-auth",
    purpose: "Removed auth module",
    confidence: 0.95,
    bundlePath: "/tmp/modules/4",
    extractedAt: 500,
    removedAt: 600,
  });

  db.query(
    "INSERT INTO gunk_files (id, gunk_id, relpath, size) VALUES (?, ?, ?, ?)",
  ).run(1, 1, "auth.ts", 256);
  db.query(
    "INSERT INTO gunk_files (id, gunk_id, relpath, size) VALUES (?, ?, ?, ?)",
  ).run(2, 1, "oauth.ts", null);
  db.query(
    "INSERT INTO gunk_files (id, gunk_id, relpath, size) VALUES (?, ?, ?, ?)",
  ).run(3, 2, "cli.ts", 128);

  tagGunk(db, 1, "auth", 0.9);
  tagGunk(db, 1, "api", 0.7);
  tagGunk(db, 2, "cli", 0.82);
  tagGunk(db, 3, "payments", 0.68);
}

function insertGunk(
  db: Database,
  gunk: {
    id: number;
    name: string;
    purpose: string;
    confidence: number;
    bundlePath?: string | null;
    extractedAt?: number | null;
    removedAt?: number | null;
  },
): void {
  db.query(
    "INSERT INTO gunks (id, source_id, name, purpose, language, confidence, bundle_path, manifest_path, extracted_at, approved_at, removed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
  ).run(
    gunk.id,
    1,
    gunk.name,
    gunk.purpose,
    "TypeScript",
    gunk.confidence,
    gunk.bundlePath ?? null,
    gunk.bundlePath ? `${gunk.bundlePath}/gunk.yml` : null,
    gunk.extractedAt ?? null,
    null,
    gunk.removedAt ?? null,
  );
}

function tagGunk(
  db: Database,
  gunkId: number,
  tagName: string,
  confidence: number,
): void {
  const tag = db
    .query<{ id: number }, [string]>("SELECT id FROM tags WHERE name = ?")
    .get(tagName);

  expect(tag).toBeDefined();

  db.query(
    "INSERT INTO gunk_tags (gunk_id, tag_id, confidence) VALUES (?, ?, ?)",
  ).run(gunkId, tag!.id, confidence);
}
