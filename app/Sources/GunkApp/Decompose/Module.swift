struct Module: Equatable, Sendable {
  let name: String
  let purpose: String?
  let tags: [String]
  let files: [String]
  let language: String?
  let confidence: Double
}
