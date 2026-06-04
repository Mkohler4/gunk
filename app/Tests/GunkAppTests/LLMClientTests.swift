import Foundation
import XCTest
@testable import GunkApp

final class LLMClientTests: XCTestCase {
  func testOpenAIBuildsStructuredRequest() async throws {
    let sender = RecordingSender(
      data: """
      {
        "choices": [
          {
            "message": {
              "content": "{\\"modules\\":[{\\"name\\":\\"auth\\"}]}"
            }
          }
        ],
        "usage": { "prompt_tokens": 11, "completion_tokens": 7 }
      }
      """
    )
    let client = OpenAIClient(apiKey: "test-key", sender: sender.send)

    let response = try await client.complete(request: makeRequest())

    XCTAssertEqual(sender.requests.count, 1)
    let request = try XCTUnwrap(sender.requests.first)
    XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

    let body = try XCTUnwrap(request.httpBody).jsonObject
    XCTAssertEqual(body["model"]?.stringValue, "fixture-model")
    XCTAssertEqual(
      body["response_format"]?.objectValue?["type"]?.stringValue,
      "json_schema"
    )
    XCTAssertEqual(
      body["response_format"]?.objectValue?["json_schema"]?.objectValue?["strict"]?.boolValue,
      true
    )
    XCTAssertEqual(response.usage, LLMTokenUsage(inputTokens: 11, outputTokens: 7))
  }

  func testAnthropicParsesUsage() async throws {
    let sender = RecordingSender(
      data: """
      {
        "content": [
          {
            "type": "tool_use",
            "name": "structured_output",
            "input": { "modules": [{ "name": "auth" }] }
          }
        ],
        "usage": { "input_tokens": 19, "output_tokens": 13 }
      }
      """
    )
    let client = AnthropicClient(apiKey: "test-key", sender: sender.send)

    let response = try await client.complete(request: makeRequest())

    let request = try XCTUnwrap(sender.requests.first)
    XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")

    let body = try XCTUnwrap(request.httpBody).jsonObject
    XCTAssertEqual(body["tool_choice"]?.objectValue?["name"]?.stringValue, "structured_output")
    XCTAssertEqual(response.json.objectValue?["modules"]?.arrayValue?.count, 1)
    XCTAssertEqual(response.usage, LLMTokenUsage(inputTokens: 19, outputTokens: 13))
  }

  func testOllamaParsesStructuredResponse() async throws {
    let sender = RecordingSender(
      data: """
      {
        "message": {
          "role": "assistant",
          "content": "{\\"modules\\":[{\\"name\\":\\"cli\\"}]}"
        },
        "prompt_eval_count": 23,
        "eval_count": 5
      }
      """
    )
    let client = OllamaClient(sender: sender.send)

    let response = try await client.complete(request: makeRequest())

    let request = try XCTUnwrap(sender.requests.first)
    XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/api/chat")

    let body = try XCTUnwrap(request.httpBody).jsonObject
    XCTAssertEqual(body["stream"]?.boolValue, false)
    XCTAssertEqual(body["format"], makeSchema())
    XCTAssertEqual(response.json.objectValue?["modules"]?.arrayValue?.count, 1)
    XCTAssertEqual(response.usage, LLMTokenUsage(inputTokens: 23, outputTokens: 5))
  }

  func testKeychainRoundTrip() throws {
    let store = InMemorySecretStore()

    try store.setSecret("sk-test", for: LLMProvider.openAI.secretAccount)

    XCTAssertEqual(try store.secret(for: LLMProvider.openAI.secretAccount), "sk-test")

    try store.setSecret(nil, for: LLMProvider.openAI.secretAccount)

    XCTAssertNil(try store.secret(for: LLMProvider.openAI.secretAccount))
  }

  func testOpenAILiveSmoke() async throws {
    guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
          !apiKey.isEmpty else {
      throw XCTSkip("OPENAI_API_KEY is not configured")
    }

    let configuredModel = ProcessInfo.processInfo.environment["OPENAI_MODEL"]
    let model = configuredModel?.isEmpty == false
      ? configuredModel!
      : LLMProvider.openAI.defaultModel
    let response = try await OpenAIClient(apiKey: apiKey).complete(
      request: LLMRequest(
        model: model,
        messages: [
          LLMMessage(role: .user, content: "Return {\"ok\": true}.")
        ],
        jsonSchemaName: "LiveSmoke",
        jsonSchema: .object([
          "type": .string("object"),
          "properties": .object([
            "ok": .object(["type": .string("boolean")])
          ]),
          "required": .array([.string("ok")]),
          "additionalProperties": .bool(false)
        ]),
        maxTokens: 64,
        temperature: 0
      )
    )

    XCTAssertEqual(response.json.objectValue?["ok"], .bool(true))
  }

  private func makeRequest() -> LLMRequest {
    LLMRequest(
      model: "fixture-model",
      messages: [
        LLMMessage(role: .system, content: "You extract modules."),
        LLMMessage(role: .user, content: "Analyze this project.")
      ],
      jsonSchemaName: "GunkModules",
      jsonSchema: makeSchema(),
      maxTokens: 512,
      temperature: 0
    )
  }

  private func makeSchema() -> JSONValue {
    .object([
      "type": .string("object"),
      "properties": .object([
        "modules": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("object"),
            "properties": .object([
              "name": .object(["type": .string("string")])
            ]),
            "required": .array([.string("name")]),
            "additionalProperties": .bool(true)
          ])
        ])
      ]),
      "required": .array([.string("modules")]),
      "additionalProperties": .bool(false)
    ])
  }
}

private final class RecordingSender {
  private let data: Data
  private(set) var requests: [URLRequest] = []

  init(data: String) {
    self.data = Data(data.utf8)
  }

  func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    return (data, response)
  }
}

private extension Data {
  var jsonObject: [String: JSONValue] {
    get throws {
      try XCTUnwrap(try JSONValue.parse(self).objectValue)
    }
  }
}

private extension JSONValue {
  var boolValue: Bool? {
    if case .bool(let value) = self {
      return value
    }

    return nil
  }
}
