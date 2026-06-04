import { Database } from "bun:sqlite";

import { runMigrations } from "./migrate.js";

export function openStore(path: string): Database {
  const db = new Database(path, { create: true });

  db.exec("PRAGMA journal_mode = WAL;");
  db.exec("PRAGMA foreign_keys = ON;");
  runMigrations(db);

  return db;
}

export { runMigrations } from "./migrate.js";
export type { MigrationResult } from "./migrate.js";
