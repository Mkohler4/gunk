import { Database } from "bun:sqlite";

import { runMigrations } from "./migrate.js";

export interface Source {
  id: number;
  name: string;
  path: string;
  droppedAt: number;
  removedAt: number | null;
}

export interface SourceFile {
  id: number;
  sourceId: number;
  relpath: string;
  size: number | null;
}

export interface Gunk {
  id: number;
  sourceId: number;
  name: string;
  purpose: string | null;
  language: string | null;
  confidence: number | null;
  bundlePath: string | null;
  manifestPath: string | null;
  extractedAt: number | null;
  approvedAt: number | null;
  removedAt: number | null;
}

export interface Tag {
  id: number;
  name: string;
}

export interface GunkTag {
  gunkId: number;
  tagId: number;
  tag: string;
  confidence: number | null;
}

export interface GunkEmbedding {
  gunkId: number;
  vector: number[];
  dim: number;
  model: string;
}

export interface GunkClusterMembership {
  memberGunkId: number;
  canonicalGunkId: number;
  similarity: number;
}

export function openStore(path: string): Database {
  const db = new Database(path, { create: true });
  db.exec("PRAGMA journal_mode = WAL;");
  db.exec("PRAGMA foreign_keys = ON;");
  runMigrations(db);
  return db;
}

// --- Reads ---

export function filesForSource(db: Database, sourceId: number): SourceFile[] {
  return db
    .query<SourceFile, [number]>(
      `SELECT id, source_id AS sourceId, relpath, size
       FROM files WHERE source_id = ? ORDER BY relpath ASC`,
    )
    .all(sourceId);
}

export function sourceById(db: Database, id: number): Source | null {
  return (
    db
      .query<Source, [number]>(
        `SELECT id, name, path, dropped_at AS droppedAt, removed_at AS removedAt FROM sources WHERE id = ?`,
      )
      .get(id) ?? null
  );
}

export interface GunkFile {
  id: number;
  gunkId: number;
  relpath: string;
  size: number | null;
}

export function filesForGunk(db: Database, gunkId: number): GunkFile[] {
  return db
    .query<GunkFile, [number]>(
      `SELECT id, gunk_id AS gunkId, relpath, size FROM gunk_files WHERE gunk_id = ? ORDER BY relpath ASC`,
    )
    .all(gunkId);
}

export function listTags(db: Database): Tag[] {
  return db.query<Tag, []>(`SELECT id, name FROM tags ORDER BY name ASC`).all();
}

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

export function gunkById(db: Database, id: number): Gunk | null {
  return (
    db.query<Gunk, [number]>(`SELECT ${GUNK_COLUMNS} FROM gunks WHERE id = ?`).get(id) ?? null
  );
}

export function listGunks(db: Database): Gunk[] {
  return db.query<Gunk, []>(`SELECT ${GUNK_COLUMNS} FROM gunks ORDER BY id DESC`).all();
}

export function gunksForSource(db: Database, sourceId: number): Gunk[] {
  return db
    .query<Gunk, [number]>(
      `SELECT ${GUNK_COLUMNS} FROM gunks WHERE source_id = ? AND removed_at IS NULL ORDER BY id ASC`,
    )
    .all(sourceId);
}

export function listGunkTags(db: Database, gunkId: number): GunkTag[] {
  return db
    .query<GunkTag, [number]>(
      `SELECT gunk_tags.gunk_id AS gunkId, gunk_tags.tag_id AS tagId,
              tags.name AS tag, gunk_tags.confidence AS confidence
       FROM gunk_tags JOIN tags ON tags.id = gunk_tags.tag_id
       WHERE gunk_id = ? ORDER BY confidence DESC, tag ASC`,
    )
    .all(gunkId);
}

interface EmbeddingRow {
  gunkId: number;
  vector: Uint8Array;
  dim: number;
  model: string;
}

export function listGunkEmbeddings(db: Database): GunkEmbedding[] {
  return db
    .query<EmbeddingRow, []>(
      `SELECT gunk_id AS gunkId, vector, dim, model FROM gunk_embeddings ORDER BY gunk_id ASC`,
    )
    .all()
    .map((row) => ({ gunkId: row.gunkId, dim: row.dim, model: row.model, vector: decodeVector(row.vector, row.dim) }));
}

export function gunkEmbedding(db: Database, gunkId: number): GunkEmbedding | null {
  const row = db
    .query<EmbeddingRow, [number]>(
      `SELECT gunk_id AS gunkId, vector, dim, model FROM gunk_embeddings WHERE gunk_id = ?`,
    )
    .get(gunkId);
  if (!row) return null;
  return { gunkId: row.gunkId, dim: row.dim, model: row.model, vector: decodeVector(row.vector, row.dim) };
}

export function gunkClusterMembership(
  db: Database,
  memberGunkId: number,
): GunkClusterMembership | null {
  return (
    db
      .query<GunkClusterMembership, [number]>(
        `SELECT member_gunk_id AS memberGunkId, canonical_gunk_id AS canonicalGunkId, similarity
         FROM gunk_clusters WHERE member_gunk_id = ?`,
      )
      .get(memberGunkId) ?? null
  );
}

export function gunkClusterMembers(
  db: Database,
  canonicalGunkId: number,
): GunkClusterMembership[] {
  return db
    .query<GunkClusterMembership, [number]>(
      `SELECT member_gunk_id AS memberGunkId, canonical_gunk_id AS canonicalGunkId, similarity
       FROM gunk_clusters WHERE canonical_gunk_id = ?`,
    )
    .all(canonicalGunkId);
}

// --- Writes ---

export function insertSource(
  db: Database,
  name: string,
  path: string,
  droppedAt: number = Date.now(),
): Source {
  const id = Number(
    db
      .query<{ id: number }, [string, string, number]>(
        `INSERT INTO sources (name, path, dropped_at) VALUES (?, ?, ?)
         ON CONFLICT(path) DO UPDATE SET removed_at = NULL RETURNING id`,
      )
      .get(name, path, droppedAt)?.id,
  );
  return db.query<Source, [number]>(
    `SELECT id, name, path, dropped_at AS droppedAt, removed_at AS removedAt FROM sources WHERE id = ?`,
  ).get(id)!;
}

export function addSourceFile(
  db: Database,
  sourceId: number,
  relpath: string,
  size: number | null,
): void {
  db.query(
    `INSERT INTO files (source_id, relpath, size) VALUES (?, ?, ?)
     ON CONFLICT(source_id, relpath) DO UPDATE SET size = excluded.size`,
  ).run(sourceId, relpath, size);
}

export function insertGunk(
  db: Database,
  fields: {
    sourceId: number;
    name: string;
    purpose: string | null;
    language: string | null;
    confidence: number | null;
  },
): Gunk {
  const id = Number(
    db
      .query<{ id: number }, [number, string, string | null, string | null, number | null]>(
        `INSERT INTO gunks (source_id, name, purpose, language, confidence)
         VALUES (?, ?, ?, ?, ?) RETURNING id`,
      )
      .get(fields.sourceId, fields.name, fields.purpose, fields.language, fields.confidence)?.id,
  );
  return gunkById(db, id)!;
}

export interface ClearedGunks {
  removed: number;
  bundlePaths: string[];
}

/**
 * Replace semantics for a re-run: hard-delete every gunk belonging to a source
 * so a fresh decomposition does not accumulate stale modules from earlier runs
 * (e.g. capabilities that were later excluded by an ignore rule). Dependent
 * rows — gunk_files, gunk_tags, gunk_embeddings, gunk_cluster memberships —
 * cascade via the schema's `ON DELETE CASCADE` (requires `PRAGMA foreign_keys
 * = ON`, which `openStore` sets). `llm_runs` reference `sources`, not `gunks`,
 * so spend history is preserved. Returns the count removed and the on-disk
 * bundle paths so the caller can delete their extracted bundle directories.
 */
export function clearGunksForSource(db: Database, sourceId: number): ClearedGunks {
  const rows = db
    .query<{ bundlePath: string | null }, [number]>(
      `SELECT bundle_path AS bundlePath FROM gunks WHERE source_id = ?`,
    )
    .all(sourceId);
  db.query(`DELETE FROM gunks WHERE source_id = ?`).run(sourceId);
  return {
    removed: rows.length,
    bundlePaths: rows
      .map((row) => row.bundlePath)
      .filter((path): path is string => path !== null && path.length > 0),
  };
}

export function upsertTag(db: Database, name: string): Tag {
  db.query(`INSERT INTO tags (name) VALUES (?) ON CONFLICT(name) DO NOTHING`).run(name);
  return db.query<Tag, [string]>(`SELECT id, name FROM tags WHERE name = ?`).get(name)!;
}

export function addGunkTag(
  db: Database,
  gunkId: number,
  tagId: number,
  confidence: number | null,
): void {
  db.query(
    `INSERT INTO gunk_tags (gunk_id, tag_id, confidence) VALUES (?, ?, ?)
     ON CONFLICT(gunk_id, tag_id) DO UPDATE SET confidence = excluded.confidence`,
  ).run(gunkId, tagId, confidence);
}

export function addGunkFile(
  db: Database,
  gunkId: number,
  relpath: string,
  size: number | null,
): void {
  db.query(
    `INSERT INTO gunk_files (gunk_id, relpath, size) VALUES (?, ?, ?)
     ON CONFLICT(gunk_id, relpath) DO UPDATE SET size = excluded.size`,
  ).run(gunkId, relpath, size);
}

export function recordLLMRun(
  db: Database,
  run: {
    sourceId: number | null;
    provider: string;
    model: string;
    inputTokens: number | null;
    outputTokens: number | null;
    costUsd?: number | null;
    startedAt: number;
    finishedAt: number | null;
  },
): void {
  db.query(
    `INSERT INTO llm_runs (source_id, provider, model, input_tokens, output_tokens, cost_usd, started_at, finished_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  ).run(
    run.sourceId,
    run.provider,
    run.model,
    run.inputTokens,
    run.outputTokens,
    run.costUsd ?? null,
    run.startedAt,
    run.finishedAt,
  );
}

export function markGunkExtracted(
  db: Database,
  gunkId: number,
  bundlePath: string,
  manifestPath: string,
  extractedAt: number = Date.now(),
): void {
  db.query(
    `UPDATE gunks SET bundle_path = ?, manifest_path = ?, extracted_at = ? WHERE id = ?`,
  ).run(bundlePath, manifestPath, extractedAt, gunkId);
}

export function upsertGunkEmbedding(
  db: Database,
  gunkId: number,
  vector: number[],
  model: string,
): void {
  db.query(
    `INSERT INTO gunk_embeddings (gunk_id, vector, dim, model) VALUES (?, ?, ?, ?)
     ON CONFLICT(gunk_id) DO UPDATE SET vector = excluded.vector, dim = excluded.dim, model = excluded.model`,
  ).run(gunkId, encodeVector(vector), vector.length, model);
}

export function upsertGunkClusterMembership(
  db: Database,
  memberGunkId: number,
  canonicalGunkId: number,
  similarity: number,
): void {
  db.query(
    `INSERT INTO gunk_clusters (member_gunk_id, canonical_gunk_id, similarity) VALUES (?, ?, ?)
     ON CONFLICT(member_gunk_id) DO UPDATE SET canonical_gunk_id = excluded.canonical_gunk_id, similarity = excluded.similarity`,
  ).run(memberGunkId, canonicalGunkId, similarity);
}

// --- Vector helpers (little-endian Float32, matching gunk-mcp) ---

export function encodeVector(vector: number[]): Uint8Array {
  const buffer = new ArrayBuffer(vector.length * Float32Array.BYTES_PER_ELEMENT);
  const view = new DataView(buffer);
  vector.forEach((value, index) => {
    view.setFloat32(index * Float32Array.BYTES_PER_ELEMENT, value, true);
  });
  return new Uint8Array(buffer);
}

export function decodeVector(data: Uint8Array, dim: number): number[] {
  if (dim <= 0 || data.byteLength < dim * Float32Array.BYTES_PER_ELEMENT) {
    return [];
  }
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  return Array.from({ length: dim }, (_, index) =>
    view.getFloat32(index * Float32Array.BYTES_PER_ELEMENT, true),
  );
}

export function cosineSimilarity(left: number[], right: number[]): number {
  if (left.length === 0 || left.length !== right.length) {
    return 0;
  }
  let dot = 0;
  let leftMag = 0;
  let rightMag = 0;
  for (let i = 0; i < left.length; i += 1) {
    dot += left[i] * right[i];
    leftMag += left[i] * left[i];
    rightMag += right[i] * right[i];
  }
  if (leftMag === 0 || rightMag === 0) {
    return 0;
  }
  return dot / (Math.sqrt(leftMag) * Math.sqrt(rightMag));
}

export { runMigrations } from "./migrate.js";
export type { MigrationResult } from "./migrate.js";
