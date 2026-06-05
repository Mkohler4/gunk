import type { Database } from "bun:sqlite";

import type {
  Gunk,
  GunkFile,
  GunkTag,
  GunkWithFiles,
  Source,
  Tag,
} from "./types.js";

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

const VISIBLE_GUNK_FILTER = `
  removed_at IS NULL
  AND (extracted_at IS NOT NULL OR approved_at IS NOT NULL)
`;

type GunkRow = Omit<Gunk, "tags">;

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
  const rows = db
    .query<GunkRow, []>(
      `SELECT ${GUNK_COLUMNS}
       FROM gunks
       WHERE ${VISIBLE_GUNK_FILTER}
       ORDER BY id DESC`,
    )
    .all();

  return rows.map((row) => withTags(db, row));
}

export function searchGunks(db: Database, query: string): Gunk[] {
  const normalizedQuery = query.trim().toLocaleLowerCase();

  if (normalizedQuery.length === 0) {
    return listGunks(db);
  }

  return listGunks(db)
    .filter((gunk) => matchesQuery(gunk, normalizedQuery))
    .sort((left, right) => {
      const confidenceDelta = (right.confidence ?? 0) - (left.confidence ?? 0);

      if (confidenceDelta !== 0) {
        return confidenceDelta;
      }

      return left.name.localeCompare(right.name);
    });
}

export function getGunk(db: Database, id: number): GunkWithFiles | null {
  const row =
    db
      .query<GunkRow, [number]>(
        `SELECT ${GUNK_COLUMNS}
         FROM gunks
         WHERE id = ? AND ${VISIBLE_GUNK_FILTER}`,
      )
      .get(id) ?? null;

  if (!row) {
    return null;
  }

  return {
    ...withTags(db, row),
    files: getGunkFiles(db, id),
  };
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

function withTags(db: Database, row: GunkRow): Gunk {
  return {
    ...row,
    tags: listGunkTags(db, row.id).map(({ tag }) => tag),
  };
}

function matchesQuery(gunk: Gunk, query: string): boolean {
  return (
    gunk.name.toLocaleLowerCase().includes(query) ||
    (gunk.purpose?.toLocaleLowerCase().includes(query) ?? false) ||
    gunk.tags.some((tag) => tag.toLocaleLowerCase().includes(query))
  );
}

export type {
  Gunk,
  GunkFile,
  GunkTag,
  GunkWithFiles,
  Source,
  Tag,
} from "./types.js";
