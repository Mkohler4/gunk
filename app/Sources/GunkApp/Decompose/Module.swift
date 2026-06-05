struct Module: Equatable, Sendable {
  let name: String
  let purpose: String?
  let tags: [String]
  let files: [String]
  let language: String?
  let confidence: Double
  let ownedFiles: [String]
  let sharedDeps: [String]
  let surface: [ModuleSurface]
  let anchors: [String]

  init(
    name: String,
    purpose: String?,
    tags: [String],
    files: [String],
    language: String?,
    confidence: Double,
    ownedFiles: [String]? = nil,
    sharedDeps: [String] = [],
    surface: [ModuleSurface] = [],
    anchors: [String] = []
  ) {
    self.name = name
    self.purpose = purpose
    self.tags = tags
    self.files = files
    self.language = language
    self.confidence = confidence
    self.ownedFiles = ownedFiles ?? files
    self.sharedDeps = sharedDeps
    self.surface = surface
    self.anchors = anchors
  }
}

struct ModuleSurface: Equatable, Hashable, Sendable {
  let path: String
  let symbol: String?
}
