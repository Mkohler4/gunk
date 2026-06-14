struct Source: Equatable, Identifiable, Sendable {
  let id: Int64
  let name: String
  let path: String
  let droppedAt: Int64
  let removedAt: Int64?
}

struct Gunk: Equatable, Identifiable, Sendable {
  let id: Int64
  let sourceId: Int64
  let name: String
  let purpose: String?
  let language: String?
  let confidence: Double?
  let bundlePath: String?
  let manifestPath: String?
  let extractedAt: Int64?
  let approvedAt: Int64?
  let removedAt: Int64?
  /// Durable model attribution (T-9.2): the provider/model that created this
  /// module, written at extraction time (or backfilled from a `RunTrace`).
  /// `nil` for modules with no resolvable run — they render the neutral mark.
  /// Defaulted so the many existing `Gunk(...)` call sites are unaffected.
  var provider: String? = nil
  var model: String? = nil
}

struct Tag: Equatable, Identifiable, Sendable {
  let id: Int64
  let name: String
}

struct GunkTag: Equatable, Sendable {
  let gunkId: Int64
  let tagId: Int64
  let tag: String
  let confidence: Double?
}

struct GunkFile: Equatable, Identifiable, Sendable {
  let id: Int64
  let gunkId: Int64
  let relpath: String
  let size: Int64?
}

struct LLMRun: Equatable, Identifiable, Sendable {
  let id: Int64
  let sourceId: Int64?
  let provider: String
  let model: String
  let inputTokens: Int64?
  let outputTokens: Int64?
  let costUsd: Double?
  let startedAt: Int64
  let finishedAt: Int64?
}

struct GunkEmbedding: Equatable, Identifiable, Sendable {
  var id: Int64 { gunkId }

  let gunkId: Int64
  let vector: [Double]
  let dim: Int
  let model: String
}
