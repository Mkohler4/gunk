import type { Database } from "bun:sqlite";

import v0Sql from "./v0.sql" with { type: "text" };
import v1Sql from "./v1.sql" with { type: "text" };
import v2Sql from "./v2.sql" with { type: "text" };

const MIGRATIONS = [
  { sql: v0Sql, version: 0 },
  { sql: v1Sql, version: 1 },
  { sql: v2Sql, version: 2 },
] as const;

const LATEST_VERSION = MIGRATIONS.at(-1)?.version ?? -1;

interface TableRow {
  name: string;
}

interface VersionRow {
  version: number | null;
}

export interface MigrationResult {
  from: number;
  to: number;
}

function currentVersion(db: Database): number {
  const schemaVersionTable = db
    .query<
      TableRow,
      []
    >("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'schema_version'")
    .get();

  if (!schemaVersionTable) {
    return -1;
  }

  return (
    db
      .query<
        VersionRow,
        []
      >("SELECT MAX(version) AS version FROM schema_version")
      .get()?.version ?? -1
  );
}

export function runMigrations(db: Database): MigrationResult {
  const from = currentVersion(db);

  if (from >= LATEST_VERSION) {
    return { from, to: from };
  }

  db.transaction(() => {
    for (const migration of MIGRATIONS) {
      if (migration.version <= from) {
        continue;
      }

      db.exec(migration.sql);
      db.query(
        "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
      ).run(migration.version, Date.now());
    }
  })();

  return { from, to: LATEST_VERSION };
}
