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
