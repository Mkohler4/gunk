import type { Database } from "bun:sqlite";

import type {
  Gunk,
  GunkEmbedding,
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

type GunkRow = Omit<Gunk, "tags" | "canonicalGunkId" | "variantCount">;

interface GunkEmbeddingRow {
  gunkId: number;
  vector: Uint8Array;
  dim: number;
  model: string;
}

interface SemanticGunkRow extends GunkRow {
  vector: Uint8Array;
  dim: number;
  model: string;
}

interface ClusterMetadata {
  canonicalGunkId: number;
  variantCount: number;
}

export interface SearchOptions {
  queryVector?: number[] | null;
}

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

export function searchGunks(
  db: Database,
  query: string,
  options: SearchOptions = {},
): Gunk[] {
  const normalizedQuery = query.trim().toLocaleLowerCase();

  if (normalizedQuery.length === 0) {
    return listGunks(db);
  }

  if (options.queryVector && options.queryVector.length > 0) {
    const semanticResults = semanticSearchGunks(db, options.queryVector);

    if (semanticResults.length > 0) {
      return semanticResults;
    }
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

export function listGunkEmbeddings(db: Database): GunkEmbedding[] {
  return db
    .query<GunkEmbeddingRow, []>(
      `SELECT
         gunk_id AS gunkId,
         vector,
         dim,
         model
       FROM gunk_embeddings
       ORDER BY gunk_id ASC`,
    )
    .all()
    .map((row) => ({
      ...row,
      vector: decodeVector(row.vector, row.dim),
    }));
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
    ...clusterMetadata(db, row.id),
  };
}

function clusterMetadata(db: Database, gunkId: number): ClusterMetadata {
  const membership = db
    .query<{ canonicalGunkId: number }, [number]>(
      `SELECT canonical_gunk_id AS canonicalGunkId
       FROM gunk_clusters
       WHERE member_gunk_id = ?`,
    )
    .get(gunkId);
  const canonicalGunkId = membership?.canonicalGunkId ?? gunkId;
  const variantCount =
    db
      .query<{ count: number }, [number]>(
        `SELECT COUNT(*) AS count
         FROM gunk_clusters
         WHERE canonical_gunk_id = ?`,
      )
      .get(canonicalGunkId)?.count ?? 0;

  return {
    canonicalGunkId,
    variantCount: Math.max(1, variantCount),
  };
}

function semanticSearchGunks(db: Database, queryVector: number[]): Gunk[] {
  return db
    .query<SemanticGunkRow, []>(
      `SELECT
         ${GUNK_COLUMNS},
         gunk_embeddings.vector AS vector,
         gunk_embeddings.dim AS dim,
         gunk_embeddings.model AS model
       FROM gunks
       JOIN gunk_embeddings ON gunk_embeddings.gunk_id = gunks.id
       WHERE ${VISIBLE_GUNK_FILTER}`,
    )
    .all()
    .map((row) => ({
      gunk: withTags(db, row),
      score: cosineSimilarity(queryVector, decodeVector(row.vector, row.dim)),
    }))
    .filter(({ score }) => score > 0)
    .sort((left, right) => {
      if (left.score !== right.score) {
        return right.score - left.score;
      }

      const confidenceDelta =
        (right.gunk.confidence ?? 0) - (left.gunk.confidence ?? 0);

      if (confidenceDelta !== 0) {
        return confidenceDelta;
      }

      return left.gunk.name.localeCompare(right.gunk.name);
    })
    .map(({ gunk }) => gunk);
}

function matchesQuery(gunk: Gunk, query: string): boolean {
  return (
    gunk.name.toLocaleLowerCase().includes(query) ||
    (gunk.purpose?.toLocaleLowerCase().includes(query) ?? false) ||
    gunk.tags.some((tag) => tag.toLocaleLowerCase().includes(query))
  );
}

function decodeVector(data: Uint8Array, dim: number): number[] {
  if (dim <= 0 || data.byteLength < dim * Float32Array.BYTES_PER_ELEMENT) {
    return [];
  }

  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  return Array.from({ length: dim }, (_, index) =>
    view.getFloat32(index * Float32Array.BYTES_PER_ELEMENT, true),
  );
}

function cosineSimilarity(left: number[], right: number[]): number {
  if (left.length === 0 || left.length !== right.length) {
    return 0;
  }

  let dotProduct = 0;
  let leftMagnitude = 0;
  let rightMagnitude = 0;

  for (let index = 0; index < left.length; index += 1) {
    dotProduct += left[index] * right[index];
    leftMagnitude += left[index] * left[index];
    rightMagnitude += right[index] * right[index];
  }

  if (leftMagnitude === 0 || rightMagnitude === 0) {
    return 0;
  }

  return dotProduct / (Math.sqrt(leftMagnitude) * Math.sqrt(rightMagnitude));
}

export type {
  Gunk,
  GunkEmbedding,
  GunkFile,
  GunkTag,
  GunkWithFiles,
  Source,
  Tag,
} from "./types.js";
