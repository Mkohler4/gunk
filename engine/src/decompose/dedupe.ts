// Cross-source module dedupe. Ported from
// app/Sources/GunkApp/Decompose/ModuleDeduper.swift.

import type { Database } from "bun:sqlite";

import {
  cosineSimilarity,
  gunkClusterMembers,
  gunkClusterMembership,
  gunkEmbedding,
  listGunkEmbeddings,
  listGunks,
  listGunkTags,
  upsertGunkClusterMembership,
  type Gunk,
} from "../store/index.js";

export interface ModuleDedupCluster {
  canonicalGunkId: number;
  memberGunkIds: number[];
  similarityByMemberGunkId: Record<number, number>;
}

export interface ModuleDeduperOptions {
  similarityThreshold: number;
}

export const defaultDeduperOptions: ModuleDeduperOptions = { similarityThreshold: 0.88 };

export function dedupe(
  db: Database,
  gunk: Gunk,
  options: ModuleDeduperOptions = defaultDeduperOptions,
): ModuleDedupCluster | null {
  const targetEmbedding = gunkEmbedding(db, gunk.id);
  if (!targetEmbedding) return null;

  const gunksById = new Map<number, Gunk>(listGunks(db).map((g) => [g.id, g]));
  const targetTags = new Set(listGunkTags(db, gunk.id).map((t) => t.tag));
  if (targetTags.size === 0) return null;

  const candidates: { gunk: Gunk; similarity: number }[] = [];
  for (const embedding of listGunkEmbeddings(db)) {
    if (embedding.gunkId === gunk.id) continue;
    const candidate = gunksById.get(embedding.gunkId);
    if (!candidate || candidate.sourceId === gunk.sourceId || candidate.removedAt !== null) continue;
    const candidateTags = new Set(listGunkTags(db, candidate.id).map((t) => t.tag));
    if (![...targetTags].some((t) => candidateTags.has(t))) continue;
    const similarity = cosineSimilarity(targetEmbedding.vector, embedding.vector);
    if (similarity < options.similarityThreshold) continue;
    candidates.push({ gunk: candidate, similarity });
  }

  let best: { gunk: Gunk; similarity: number } | null = null;
  for (const candidate of candidates) {
    if (
      !best ||
      candidate.similarity > best.similarity ||
      (candidate.similarity === best.similarity && candidate.gunk.id > best.gunk.id)
    ) {
      best = candidate;
    }
  }
  if (!best) return null;

  const existingCanonicalId = gunkClusterMembership(db, best.gunk.id)?.canonicalGunkId ?? best.gunk.id;
  const existingMembers = gunkClusterMembers(db, existingCanonicalId).map((m) => m.memberGunkId);
  const memberIds = new Set<number>([...existingMembers, existingCanonicalId, best.gunk.id, gunk.id]);
  const memberGunks: Gunk[] = [...memberIds]
    .map((id) => gunksById.get(id) ?? (gunk.id === id ? gunk : null))
    .filter((g): g is Gunk => g !== null);
  const canonical = canonicalGunk(memberGunks);

  const similarityByMemberGunkId: Record<number, number> = {};
  for (const memberId of memberIds) {
    const similarity =
      memberId === canonical.id
        ? 1
        : similarityBetween(db, canonical.id, memberId, memberId === gunk.id ? best.similarity : 1);
    similarityByMemberGunkId[memberId] = similarity;
    upsertGunkClusterMembership(db, memberId, canonical.id, similarity);
  }

  return {
    canonicalGunkId: canonical.id,
    memberGunkIds: [...memberIds].sort((a, b) => a - b),
    similarityByMemberGunkId,
  };
}

function canonicalGunk(gunks: Gunk[]): Gunk {
  return [...gunks].sort((lhs, rhs) => {
    const lc = lhs.confidence ?? 0;
    const rc = rhs.confidence ?? 0;
    if (lc !== rc) return rc - lc;
    return lhs.id - rhs.id;
  })[0];
}

function similarityBetween(db: Database, gunkId: number, otherGunkId: number, fallback: number): number {
  const lhs = gunkEmbedding(db, gunkId);
  const rhs = gunkEmbedding(db, otherGunkId);
  if (!lhs || !rhs) return fallback;
  const similarity = cosineSimilarity(lhs.vector, rhs.vector);
  return similarity > 0 ? similarity : fallback;
}
