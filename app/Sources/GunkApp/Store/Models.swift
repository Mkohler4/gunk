struct Gunk: Equatable, Identifiable, Sendable {
  let id: Int64
  let name: String
  let path: String
  let droppedAt: Int64
  let removedAt: Int64?
}

struct Tag: Equatable, Sendable {
  let name: String
  let description: String
}

struct GunkTag: Equatable, Sendable {
  let gunkId: Int64
  let tag: String
  let confidence: Double
  let source: String
  let taggedAt: Int64
}

struct GunkTagInput: Equatable, Sendable {
  let tag: String
  let confidence: Double
  let source: String
}
