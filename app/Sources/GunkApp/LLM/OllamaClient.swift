import Foundation

final class OllamaClient: LLMClient {
  private let baseURL: URL
  private let sender: HTTPSender

  init(
    baseURL: URL = URL(string: "http://localhost:11434")!,
    sender: @escaping HTTPSender = LiveHTTPSender.send
  ) {
    self.baseURL = baseURL
    self.sender = sender
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
