import Foundation

final class OpenAIClient: LLMClient {
  private let apiKey: String
  private let baseURL: URL
  private let sender: HTTPSender

  init(
    apiKey: String,
    baseURL: URL = URL(string: "https://api.openai.com/v1")!,
    sender: @escaping HTTPSender = LiveHTTPSender.send
  ) {
    self.apiKey = apiKey
    self.baseURL = baseURL
    self.sender = sender
  }

  func complete(request: LLMRequest) async throws -> LLMResponse {
    guard !apiKey.isEmpty else {
      throw LLMClientError.missingAPIKey
    }

    var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
      "messages": .array(
        request.messages.map {
          .object([
            "role": .string($0.role.rawValue),
            "content": .string($0.content)
          ])
        }
      ),
      "response_format": .object([
        "type": .string("json_schema"),
        "json_schema": .object([
          "name": .string(request.jsonSchemaName),
          "strict": .bool(true),
          "schema": request.jsonSchema
        ])
      ])
    ]

    if let maxTokens = request.maxTokens {
      object["max_tokens"] = .number(Double(maxTokens))
    }

    if let temperature = request.temperature {
      object["temperature"] = .number(temperature)
    }

    return .object(object)
  }

  private func parseResponse(_ data: Data) throws -> LLMResponse {
    let root = try JSONValue.parse(data)
    guard let object = root.objectValue,
          let choices = object["choices"]?.arrayValue,
          let firstChoice = choices.first?.objectValue,
          let message = firstChoice["message"]?.objectValue,
          let content = message["content"]?.stringValue else {
      throw LLMClientError.missingStructuredOutput
    }

    let usage = object["usage"]?.objectValue
    return LLMResponse(
      json: try JSONValue.parseString(content),
      usage: LLMTokenUsage(
        inputTokens: usage?["prompt_tokens"]?.intValue,
        outputTokens: usage?["completion_tokens"]?.intValue
      )
    )
  }
}
