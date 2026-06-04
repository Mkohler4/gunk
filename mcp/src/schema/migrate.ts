import type { Database } from "bun:sqlite";

import v0Sql from "./v0.sql" with { type: "text" };

const V0_VERSION = 0;

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

  if (from >= V0_VERSION) {
    return { from, to: from };
  }

  db.transaction(() => {
    db.exec(v0Sql);
    db.query(
      "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
    ).run(V0_VERSION, Date.now());
  })();

  return { from, to: V0_VERSION };
}
