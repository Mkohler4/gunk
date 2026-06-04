import type { Database } from "bun:sqlite";

import type { Gunk, GunkFile } from "./types.js";

const GUNK_COLUMNS = `
  id,
  name,
  path,
  dropped_at AS droppedAt,
  removed_at AS removedAt
`;

export function listGunks(db: Database): Gunk[] {
  return db
    .query<Gunk, []>(
      `SELECT ${GUNK_COLUMNS}
       FROM gunks
       WHERE removed_at IS NULL
       ORDER BY dropped_at DESC`,
    )
    .all();
}

export function getGunk(db: Database, id: number): Gunk | null {
  return (
    db
      .query<Gunk, [number]>(
        `SELECT ${GUNK_COLUMNS}
         FROM gunks
         WHERE id = ?`,
      )
      .get(id) ?? null
  );
}

export function getGunkFiles(db: Database, gunkId: number): GunkFile[] {
  return db
    .query<GunkFile, [number]>(
      `SELECT
         id,
         gunk_id AS gunkId,
         relpath,
         size
       FROM files
       WHERE gunk_id = ?
       ORDER BY relpath ASC`,
    )
    .all(gunkId);
}

export type { Gunk, GunkFile } from "./types.js";
