import Foundation

final class AnthropicClient: LLMClient {
  private let apiKey: String
  private let baseURL: URL
  private let sender: HTTPSender

  init(
    apiKey: String,
    baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
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

    var urlRequest = URLRequest(url: baseURL.appendingPathComponent("messages"))
    urlRequest.httpMethod = "POST"
    urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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
      "max_tokens": .number(Double(request.maxTokens ?? 1024)),
      "messages": .array(
        request.messages
          .filter { $0.role != .system }
          .map {
            .object([
              "role": .string($0.role.rawValue),
              "content": .string($0.content)
            ])
          }
      ),
      "tools": .array([
        .object([
          "name": .string("structured_output"),
          "description": .string("Return the response using the requested JSON schema."),
          "input_schema": request.jsonSchema
        ])
      ]),
      "tool_choice": .object([
        "type": .string("tool"),
        "name": .string("structured_output")
      ])
    ]

    let systemMessages = request.messages
      .filter { $0.role == .system }
      .map(\.content)
      .joined(separator: "\n\n")

    if !systemMessages.isEmpty {
      object["system"] = .string(systemMessages)
    }

    if let temperature = request.temperature {
      object["temperature"] = .number(temperature)
    }

    return .object(object)
  }

  private func parseResponse(_ data: Data) throws -> LLMResponse {
    let root = try JSONValue.parse(data)
    guard let object = root.objectValue,
          let content = object["content"]?.arrayValue else {
      throw LLMClientError.missingStructuredOutput
    }

    let toolUse = content
      .compactMap(\.objectValue)
      .first { block in
        block["type"]?.stringValue == "tool_use"
          && block["name"]?.stringValue == "structured_output"
      }

    guard let input = toolUse?["input"] else {
      throw LLMClientError.missingStructuredOutput
    }

    let usage = object["usage"]?.objectValue
    return LLMResponse(
      json: input,
      usage: LLMTokenUsage(
        inputTokens: usage?["input_tokens"]?.intValue,
        outputTokens: usage?["output_tokens"]?.intValue
      )
    )
  }
}
