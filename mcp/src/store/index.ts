import type { Database } from "bun:sqlite";

import type { Gunk, GunkFile, GunkTag, Source, Tag } from "./types.js";

const SOURCE_COLUMNS = `
  id,
  name,
  path,
  dropped_at AS droppedAt,
  removed_at AS removedAt
`;

const GUNK_COLUMNS = `
  id,
  source_id AS sourceId,
  name,
  purpose,
  language,
  confidence,
  bundle_path AS bundlePath,
  manifest_path AS manifestPath,
  extracted_at AS extractedAt,
  approved_at AS approvedAt,
  removed_at AS removedAt
`;

export function listSources(db: Database): Source[] {
  return db
    .query<Source, []>(
      `SELECT ${SOURCE_COLUMNS}
       FROM sources
       WHERE removed_at IS NULL
       ORDER BY dropped_at DESC`,
    )
    .all();
}

export function listGunks(db: Database): Gunk[] {
  return db
    .query<Gunk, []>(
      `SELECT ${GUNK_COLUMNS}
       FROM gunks
       WHERE removed_at IS NULL
       ORDER BY id DESC`,
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
       FROM gunk_files
       WHERE gunk_id = ?
       ORDER BY relpath ASC`,
    )
    .all(gunkId);
}

export function listTags(db: Database): Tag[] {
  return db
    .query<Tag, []>(
      `SELECT id, name
       FROM tags
       ORDER BY name ASC`,
    )
    .all();
}

export function listGunkTags(db: Database, gunkId: number): GunkTag[] {
  return db
    .query<GunkTag, [number]>(
      `SELECT
         gunk_tags.gunk_id AS gunkId,
         gunk_tags.tag_id AS tagId,
         tags.name AS tag,
         gunk_tags.confidence AS confidence
       FROM gunk_tags
       JOIN tags ON tags.id = gunk_tags.tag_id
       WHERE gunk_id = ?
       ORDER BY confidence DESC, tag ASC`,
    )
    .all(gunkId);
}

export type { Gunk, GunkFile, GunkTag, Source, Tag } from "./types.js";
