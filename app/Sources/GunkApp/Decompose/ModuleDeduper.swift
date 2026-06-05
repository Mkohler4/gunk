import Foundation

struct ModuleDeduperOptions: Equatable, Sendable {
  let similarityThreshold: Double

  init(similarityThreshold: Double = 0.88) {
    self.similarityThreshold = similarityThreshold
  }
}

struct ModuleDedupCluster: Equatable, Sendable {
  let canonicalGunkId: Int64
  let memberGunkIds: [Int64]
  let similarityByMemberGunkId: [Int64: Double]

  var variantCount: Int {
    memberGunkIds.count
  }
}

final class ModuleDeduper {
  private let store: Store
  private let options: ModuleDeduperOptions

  init(store: Store, options: ModuleDeduperOptions = ModuleDeduperOptions()) {
    self.store = store
    self.options = options
  }

  @discardableResult
  func dedupe(gunk: Gunk) throws -> ModuleDedupCluster? {
    guard let targetEmbedding = try store.gunkEmbedding(gunkId: gunk.id) else {
      return nil
    }

    let gunksById = Dictionary(uniqueKeysWithValues: try store.listGunks().map { ($0.id, $0) })
    let targetTags = Set(try store.listGunkTags(gunkId: gunk.id).map(\.tag))

    guard !targetTags.isEmpty else {
      return nil
    }

    let candidates = try store.listGunkEmbeddings().compactMap { embedding -> Candidate? in
      guard embedding.gunkId != gunk.id,
            let candidate = gunksById[embedding.gunkId],
            candidate.sourceId != gunk.sourceId,
            candidate.removedAt == nil else {
        return nil
      }

      let candidateTags = Set(try store.listGunkTags(gunkId: candidate.id).map(\.tag))
      guard !targetTags.intersection(candidateTags).isEmpty else {
        return nil
      }

      let similarity = EmbeddingIndex.cosineSimilarity(targetEmbedding.vector, embedding.vector)
      guard similarity >= options.similarityThreshold else {
        return nil
      }

      return Candidate(gunk: candidate, similarity: similarity)
    }

    guard let bestCandidate = candidates.max(by: { lhs, rhs in
      if lhs.similarity != rhs.similarity {
        return lhs.similarity < rhs.similarity
      }

      return lhs.gunk.id > rhs.gunk.id
    }) else {
      return nil
    }

    let existingCanonicalId = try store.gunkClusterMembership(memberGunkId: bestCandidate.gunk.id)?
      .canonicalGunkId ?? bestCandidate.gunk.id
    let existingMembers = try store.gunkClusterMembers(canonicalGunkId: existingCanonicalId)
      .map(\.memberGunkId)
    let memberIds = Set(existingMembers + [existingCanonicalId, bestCandidate.gunk.id, gunk.id])
    let memberGunks = memberIds.compactMap { gunksById[$0] ?? (gunk.id == $0 ? gunk : nil) }
    let canonical = canonicalGunk(from: memberGunks)
    var similarityByMemberGunkId: [Int64: Double] = [:]

    for memberId in memberIds {
      let similarity = memberId == canonical.id
        ? 1
        : similarityBetween(gunkId: canonical.id, otherGunkId: memberId, fallback: memberId == gunk.id ? bestCandidate.similarity : 1)
      similarityByMemberGunkId[memberId] = similarity
      try store.upsertGunkClusterMembership(
        memberGunkId: memberId,
        canonicalGunkId: canonical.id,
        similarity: similarity
      )
    }

    return ModuleDedupCluster(
      canonicalGunkId: canonical.id,
      memberGunkIds: memberIds.sorted(),
      similarityByMemberGunkId: similarityByMemberGunkId
    )
  }

  private func canonicalGunk(from gunks: [Gunk]) -> Gunk {
    gunks.sorted { lhs, rhs in
      let lhsConfidence = lhs.confidence ?? 0
      let rhsConfidence = rhs.confidence ?? 0

      if lhsConfidence != rhsConfidence {
        return lhsConfidence > rhsConfidence
      }

      return lhs.id < rhs.id
    }
    .first!
  }

  private func similarityBetween(gunkId: Int64, otherGunkId: Int64, fallback: Double) -> Double {
    guard let lhs = try? store.gunkEmbedding(gunkId: gunkId),
          let rhs = try? store.gunkEmbedding(gunkId: otherGunkId) else {
      return fallback
    }

    let similarity = EmbeddingIndex.cosineSimilarity(lhs.vector, rhs.vector)
    return similarity > 0 ? similarity : fallback
  }
}

private struct Candidate {
  let gunk: Gunk
  let similarity: Double
}
