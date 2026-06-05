import Foundation

protocol EmbeddingProvider {
  var model: String { get }

  func embed(text: String) async throws -> [Double]
}

struct EmbeddingSearchResult: Equatable, Sendable {
  let gunk: Gunk
  let score: Double
}

final class EmbeddingIndex {
  private let store: Store
  private let embedder: EmbeddingProvider

  init(
    store: Store,
    embedder: EmbeddingProvider = OllamaEmbeddingProvider()
  ) {
    self.store = store
    self.embedder = embedder
  }

  @discardableResult
  func index(gunk: Gunk) async throws -> GunkEmbedding {
    let vector = try await embedder.embed(text: try document(for: gunk))
    guard !vector.isEmpty else {
      throw LLMClientError.invalidStructuredOutput
    }

    return try store.upsertGunkEmbedding(
      gunkId: gunk.id,
      vector: vector,
      model: embedder.model
    )
  }

  func search(query: String, limit: Int = 10) async throws -> [EmbeddingSearchResult] {
    let queryVector = try await embedder.embed(text: query)
    let gunksById = Dictionary(uniqueKeysWithValues: try store.listGunks().map { ($0.id, $0) })

    return try store.listGunkEmbeddings()
      .compactMap { embedding -> EmbeddingSearchResult? in
        guard let gunk = gunksById[embedding.gunkId],
              gunk.removedAt == nil else {
          return nil
        }

        let score = Self.cosineSimilarity(queryVector, embedding.vector)
        guard score > 0 else {
          return nil
        }

        return EmbeddingSearchResult(gunk: gunk, score: score)
      }
      .sorted { lhs, rhs in
        if lhs.score != rhs.score {
          return lhs.score > rhs.score
        }

        return lhs.gunk.name.localizedStandardCompare(rhs.gunk.name) == .orderedAscending
      }
      .prefix(max(0, limit))
      .map { $0 }
  }

  private func document(for gunk: Gunk) throws -> String {
    let tags = try store.listGunkTags(gunkId: gunk.id).map(\.tag)
    let files = try store.filesForGunk(gunkId: gunk.id).map(\.relpath)

    return [
      gunk.name,
      gunk.purpose ?? "",
      gunk.language ?? "",
      tags.joined(separator: " "),
      files.joined(separator: " "),
      files.map(Self.signatureTokens(for:)).joined(separator: " ")
    ]
    .filter { !$0.isEmpty }
    .joined(separator: "\n")
  }

  static func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
    guard !lhs.isEmpty, lhs.count == rhs.count else {
      return 0
    }

    var dotProduct = 0.0
    var lhsMagnitude = 0.0
    var rhsMagnitude = 0.0

    for index in lhs.indices {
      dotProduct += lhs[index] * rhs[index]
      lhsMagnitude += lhs[index] * lhs[index]
      rhsMagnitude += rhs[index] * rhs[index]
    }

    guard lhsMagnitude > 0, rhsMagnitude > 0 else {
      return 0
    }

    return dotProduct / (sqrt(lhsMagnitude) * sqrt(rhsMagnitude))
  }

  private static func signatureTokens(for path: String) -> String {
    URL(fileURLWithPath: path)
      .deletingPathExtension()
      .lastPathComponent
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "_", with: " ")
  }
}

final class OllamaEmbeddingProvider: EmbeddingProvider {
  let model: String

  private let baseURL: URL
  private let sender: HTTPSender

  init(
    model: String = "nomic-embed-text",
    baseURL: URL = URL(string: "http://localhost:11434")!,
    sender: @escaping HTTPSender = LiveHTTPSender.send
  ) {
    self.model = model
    self.baseURL = baseURL
    self.sender = sender
  }

  func embed(text: String) async throws -> [Double] {
    var request = URLRequest(url: baseURL.appendingPathComponent("api/embeddings"))
    request.httpMethod = "POST"
    try request.setJSONBody(
      .object([
        "model": .string(model),
        "prompt": .string(text)
      ])
    )

    let (data, response) = try await sender(request)
    guard (200..<300).contains(response.statusCode) else {
      throw LLMClientError.invalidHTTPStatus(response.statusCode)
    }

    return try parseResponse(data)
  }

  private func parseResponse(_ data: Data) throws -> [Double] {
    let root = try JSONValue.parse(data)

    if let embedding = root.objectValue?["embedding"]?.arrayValue {
      return embedding.compactMap(\.numberValue)
    }

    if let embeddings = root.objectValue?["embeddings"]?.arrayValue,
       let first = embeddings.first?.arrayValue {
      return first.compactMap(\.numberValue)
    }

    throw LLMClientError.invalidStructuredOutput
  }
}

final class OpenAIEmbeddingProvider: EmbeddingProvider {
  let model: String

  private let apiKey: String
  private let baseURL: URL
  private let sender: HTTPSender

  init(
    apiKey: String,
    model: String = "text-embedding-3-small",
    baseURL: URL = URL(string: "https://api.openai.com/v1")!,
    sender: @escaping HTTPSender = LiveHTTPSender.send
  ) {
    self.apiKey = apiKey
    self.model = model
    self.baseURL = baseURL
    self.sender = sender
  }

  func embed(text: String) async throws -> [Double] {
    guard !apiKey.isEmpty else {
      throw LLMClientError.missingAPIKey
    }

    var request = URLRequest(url: baseURL.appendingPathComponent("embeddings"))
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    try request.setJSONBody(
      .object([
        "model": .string(model),
        "input": .string(text)
      ])
    )

    let (data, response) = try await sender(request)
    guard (200..<300).contains(response.statusCode) else {
      throw LLMClientError.invalidHTTPStatus(response.statusCode)
    }

    return try parseResponse(data)
  }

  private func parseResponse(_ data: Data) throws -> [Double] {
    let root = try JSONValue.parse(data)
    guard let embedding = root.objectValue?["data"]?.arrayValue?.first?
      .objectValue?["embedding"]?.arrayValue else {
      throw LLMClientError.invalidStructuredOutput
    }

    return embedding.compactMap(\.numberValue)
  }
}

private extension JSONValue {
  var numberValue: Double? {
    if case .number(let value) = self {
      return value
    }

    return nil
  }
}
