import Foundation

final class OllamaClient: LLMClient {
  static let defaultBaseURL = URL(string: "http://localhost:11434")!
  static let baseURLStorageKey = "llm.ollama.baseURL"

  private let baseURL: URL
  private let sender: HTTPSender

  init(
    baseURL: URL = OllamaClient.defaultBaseURL,
    sender: @escaping HTTPSender = LiveHTTPSender.send
  ) {
    self.baseURL = baseURL
    self.sender = sender
  }

  static func normalizedBaseURL(from rawValue: String) -> URL? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return defaultBaseURL
    }

    let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
    guard var components = URLComponents(string: withScheme),
          let host = components.host,
          !host.isEmpty else {
      return nil
    }

    components.path = ""
    components.query = nil
    components.fragment = nil
    return components.url
  }

  static func configuredBaseURL(userDefaults: UserDefaults = .standard) -> URL {
    let stored = userDefaults.string(forKey: baseURLStorageKey) ?? ""
    return normalizedBaseURL(from: stored) ?? defaultBaseURL
  }

  func complete(request: LLMRequest) async throws -> LLMResponse {
    var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
    urlRequest.httpMethod = "POST"
    try urlRequest.setJSONBody(body(for: request))

    let (data, response) = try await sender(urlRequest)
    guard (200..<300).contains(response.statusCode) else {
      throw LLMClientError.invalidHTTPStatus(response.statusCode)
    }

    return try parseResponse(data)
  }

  func listModels() async throws -> [String] {
    let urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
    let (data, response) = try await sender(urlRequest)
    guard (200..<300).contains(response.statusCode) else {
      throw LLMClientError.invalidHTTPStatus(response.statusCode)
    }

    let root = try JSONValue.parse(data)
    guard let models = root.objectValue?["models"]?.arrayValue else {
      throw LLMClientError.invalidStructuredOutput
    }

    return models.compactMap { model in
      model.objectValue?["name"]?.stringValue
    }
  }

  func body(for request: LLMRequest) -> JSONValue {
    var object: [String: JSONValue] = [
      "model": .string(request.model),
      "stream": .bool(false),
      "format": request.jsonSchema,
      "messages": .array(
        request.messages.map {
          .object([
            "role": .string($0.role.rawValue),
            "content": .string($0.content)
          ])
        }
      )
    ]

    if let temperature = request.temperature {
      object["options"] = .object(["temperature": .number(temperature)])
    }

    return .object(object)
  }

  private func parseResponse(_ data: Data) throws -> LLMResponse {
    let root = try JSONValue.parse(data)
    guard let object = root.objectValue,
          let message = object["message"]?.objectValue,
          let content = message["content"]?.stringValue else {
      throw LLMClientError.missingStructuredOutput
    }

    return LLMResponse(
      json: try JSONValue.parseString(content),
      usage: LLMTokenUsage(
        inputTokens: object["prompt_eval_count"]?.intValue,
        outputTokens: object["eval_count"]?.intValue
      )
    )
  }
}
