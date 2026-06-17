import Foundation

protocol LLMClient {
  func complete(request: LLMRequest) async throws -> LLMResponse
}

enum LLMProvider: String, CaseIterable, Identifiable {
  case openAI = "OpenAI"
  case anthropic = "Anthropic"
  case ollama = "Ollama"

  var id: String { rawValue }

  var defaultModel: String {
    switch self {
    case .openAI:
      return "gpt-4.1-mini"
    case .anthropic:
      return "claude-sonnet-4-20250514"
    case .ollama:
      return "llama3.2"
    }
  }

  var secretAccount: String {
    switch self {
    case .openAI:
      return "openai-api-key"
    case .anthropic:
      return "anthropic-api-key"
    case .ollama:
      return "ollama-api-key"
    }
  }

  var modelStorageKey: String {
    switch self {
    case .openAI:
      return "llm.model.openai"
    case .anthropic:
      return "llm.model.anthropic"
    case .ollama:
      return "llm.model.ollama"
    }
  }
}

enum LLMRole: String, Codable, Equatable {
  case system
  case user
  case assistant
}

struct LLMMessage: Codable, Equatable {
  let role: LLMRole
  let content: String
}

struct LLMRequest: Equatable {
  let model: String
  let messages: [LLMMessage]
  let jsonSchemaName: String
  let jsonSchema: JSONValue
  let maxTokens: Int?
  let temperature: Double?

  init(
    model: String,
    messages: [LLMMessage],
    jsonSchemaName: String,
    jsonSchema: JSONValue,
    maxTokens: Int? = nil,
    temperature: Double? = nil
  ) {
    self.model = model
    self.messages = messages
    self.jsonSchemaName = jsonSchemaName
    self.jsonSchema = jsonSchema
    self.maxTokens = maxTokens
    self.temperature = temperature
  }
}

struct LLMResponse: Equatable {
  let json: JSONValue
  let usage: LLMTokenUsage
}

struct LLMTokenUsage: Equatable {
  let inputTokens: Int?
  let outputTokens: Int?
}

enum LLMClientError: Error, Equatable {
  case missingAPIKey
  case invalidHTTPStatus(Int)
  case missingStructuredOutput
  case invalidStructuredOutput
}

extension LLMClientError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .missingAPIKey:
      return "Add an API key in Settings before dropping a folder."
    case .invalidHTTPStatus(let statusCode):
      return "LLM request failed with HTTP \(statusCode)."
    case .missingStructuredOutput:
      return "The LLM response did not include structured output."
    case .invalidStructuredOutput:
      return "The LLM response was not valid structured output."
    }
  }
}

typealias HTTPSender = (URLRequest) async throws -> (Data, HTTPURLResponse)

enum LiveHTTPSender {
  static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMClientError.invalidStructuredOutput
    }

    return (data, httpResponse)
  }
}

enum JSONValue: Codable, Equatable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    switch self {
    case .object(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    case .null:
      try container.encodeNil()
    }
  }

  var objectValue: [String: JSONValue]? {
    if case .object(let value) = self {
      return value
    }

    return nil
  }

  var arrayValue: [JSONValue]? {
    if case .array(let value) = self {
      return value
    }

    return nil
  }

  var stringValue: String? {
    if case .string(let value) = self {
      return value
    }

    return nil
  }

  var intValue: Int? {
    if case .number(let value) = self {
      return Int(value)
    }

    return nil
  }
}

extension JSONValue {
  static func parse(_ data: Data) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: data)
  }

  static func parseString(_ string: String) throws -> JSONValue {
    guard let data = string.data(using: .utf8) else {
      throw LLMClientError.invalidStructuredOutput
    }

    return try parse(data)
  }

  func encodedData() throws -> Data {
    try JSONEncoder().encode(self)
  }
}

extension URLRequest {
  mutating func setJSONBody(_ value: JSONValue) throws {
    httpBody = try value.encodedData()
    setValue("application/json", forHTTPHeaderField: "Content-Type")
  }
}
