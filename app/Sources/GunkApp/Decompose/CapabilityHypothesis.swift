import Foundation

struct CapabilityHypothesis: Equatable, Sendable {
  enum Priority: String, Equatable, Sendable {
    case normal
    case low
  }

  let name: String
  let rationale: String
  let anchors: [String]
  let seedFiles: [String]
  let expectedCollaborators: [String]
  let granularity: String
  let priority: Priority
}
