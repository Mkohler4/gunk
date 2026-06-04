import Foundation

enum DecompositionEngineError: Error, Equatable {
  case invalidResponse
}

final class DecompositionEngine {
  private let store: Store
  private let provider: LLMProvider
  private let model: String
  private let maxOutputTokens: Int
  private let now: () -> Int64

  init(
    store: Store,
    provider: LLMProvider,
    model: String,
    maxOutputTokens: Int = 2_048,
    now: @escaping () -> Int64 = Store.currentTimeInMilliseconds
  ) {
    self.store = store
    self.provider = provider
    self.model = model
    self.maxOutputTokens = maxOutputTokens
    self.now = now
  }

  func decompose(source: Source, context: String, using client: LLMClient) async throws -> [Module] {
    let tags = try store.listTags()
    let sourceFiles = try store.filesForSource(sourceId: source.id)
    let sourceFileByPath = Dictionary(uniqueKeysWithValues: sourceFiles.map { ($0.relpath, $0) })
    let allowedTags = Set(tags.map(\.name))
    let tagByName = Dictionary(uniqueKeysWithValues: tags.map { ($0.name, $0) })

    let startedAt = now()
    let response = try await client.complete(
      request: request(
        source: source,
        context: context,
        allowedTags: tags.map(\.name)
      )
    )
    let finishedAt = now()

    try store.recordLLMRun(
      sourceId: source.id,
      provider: provider.rawValue,
      model: model,
      inputTokens: response.usage.inputTokens.map(Int64.init),
      outputTokens: response.usage.outputTokens.map(Int64.init),
      startedAt: startedAt,
      finishedAt: finishedAt
    )

    let modules = try parseModules(
      response.json,
      allowedTags: allowedTags,
      sourceFileByPath: sourceFileByPath
    )

    for module in modules {
      let gunk = try store.insertGunk(
        sourceId: source.id,
        name: module.name,
        purpose: module.purpose,
        language: module.language,
        confidence: module.confidence
      )

      for tagName in module.tags {
        guard let tag = tagByName[tagName] else {
          continue
        }

        try store.addGunkTag(
          gunkId: gunk.id,
          tagId: tag.id,
          confidence: module.confidence
        )
      }

      for relpath in module.files {
        try store.addGunkFile(
          gunkId: gunk.id,
          relpath: relpath,
          size: sourceFileByPath[relpath]?.size
        )
      }
    }

    return modules
  }

  private func request(source: Source, context: String, allowedTags: [String]) -> LLMRequest {
    LLMRequest(
      model: model,
      messages: [
        LLMMessage(
          role: .system,
          content: """
          You decompose a software project into reusable modules for gunk.
          Return only structured JSON that matches the schema.
          Use only the allowed tag taxonomy and only cite files present in the source file tree.
          """
        ),
        LLMMessage(
          role: .user,
          content: """
          Source: \(source.name)
          Allowed tags: \(allowedTags.joined(separator: ", "))

          \(context)
          """
        )
      ],
      jsonSchemaName: "GunkModules",
      jsonSchema: Self.outputSchema(allowedTags: allowedTags),
      maxTokens: maxOutputTokens,
      temperature: 0
    )
  }

  private func parseModules(
    _ value: JSONValue,
    allowedTags: Set<String>,
    sourceFileByPath: [String: SourceFile]
  ) throws -> [Module] {
    guard let modules = value.objectValue?["modules"]?.arrayValue else {
      throw DecompositionEngineError.invalidResponse
    }

    return try modules.compactMap { value in
      guard let object = value.objectValue,
            let name = object["name"]?.stringValue?.trimmedNonEmpty,
            let files = object["files"]?.arrayValue?.compactMap(\.stringValue),
            let confidence = object["confidence"]?.doubleValue else {
        throw DecompositionEngineError.invalidResponse
      }

      let uniqueFiles = files.uniqued()
      guard !uniqueFiles.isEmpty,
            uniqueFiles.allSatisfy({ sourceFileByPath[$0] != nil }) else {
        return nil
      }

      let tags = object["tags"]?.arrayValue?
        .compactMap(\.stringValue)
        .filter { allowedTags.contains($0) }
        .uniqued() ?? []

      return Module(
        name: name,
        purpose: object["purpose"]?.stringValue?.trimmedNonEmpty,
        tags: tags,
        files: uniqueFiles,
        language: object["language"]?.stringValue?.trimmedNonEmpty,
        confidence: confidence.clamped(to: 0...1)
      )
    }
  }

  static func outputSchema(allowedTags: [String]) -> JSONValue {
    .object([
      "type": .string("object"),
      "properties": .object([
        "modules": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("object"),
            "properties": .object([
              "name": .object(["type": .string("string")]),
              "purpose": .object(["type": .string("string")]),
              "tags": .object([
                "type": .string("array"),
                "items": .object([
                  "type": .string("string"),
                  "enum": .array(allowedTags.map(JSONValue.string))
                ])
              ]),
              "files": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")])
              ]),
              "language": .object(["type": .string("string")]),
              "confidence": .object([
                "type": .string("number"),
                "minimum": .number(0),
                "maximum": .number(1)
              ])
            ]),
            "required": .array([
              .string("name"),
              .string("purpose"),
              .string("tags"),
              .string("files"),
              .string("language"),
              .string("confidence")
            ]),
            "additionalProperties": .bool(false)
          ])
        ])
      ]),
      "required": .array([.string("modules")]),
      "additionalProperties": .bool(false)
    ])
  }
}

private extension JSONValue {
  var doubleValue: Double? {
    if case .number(let value) = self {
      return value
    }

    return nil
  }
}

private extension String {
  var trimmedNonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}

private extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double {
    min(max(self, range.lowerBound), range.upperBound)
  }
}

private extension Array where Element: Hashable {
  func uniqued() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
