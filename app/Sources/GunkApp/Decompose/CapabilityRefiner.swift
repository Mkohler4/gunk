import Foundation

enum CapabilityRefinerError: Error, Equatable {
  case invalidResponse
}

struct CapabilityRefinerOptions: Equatable, Sendable {
  let maxContextCharacters: Int
  let maxFileCharacters: Int

  init(maxContextCharacters: Int = 32_000, maxFileCharacters: Int = 8_000) {
    self.maxContextCharacters = maxContextCharacters
    self.maxFileCharacters = maxFileCharacters
  }
}

final class CapabilityRefiner {
  private let store: Store
  private let provider: LLMProvider
  private let model: String
  private let maxOutputTokens: Int
  private let options: CapabilityRefinerOptions
  private let now: () -> Int64

  init(
    store: Store,
    provider: LLMProvider,
    model: String,
    maxOutputTokens: Int = 4_096,
    options: CapabilityRefinerOptions = CapabilityRefinerOptions(),
    now: @escaping () -> Int64 = Store.currentTimeInMilliseconds
  ) {
    self.store = store
    self.provider = provider
    self.model = model
    self.maxOutputTokens = maxOutputTokens
    self.options = options
    self.now = now
  }

  func refine(
    source: Source,
    expansions: [CapabilityExpansion],
    contentsByPath: [String: String],
    using client: LLMClient
  ) async throws -> [Module] {
    let allowedTags = Set(try store.listTags().map(\.name))
    var modules: [Module] = []

    for expansion in expansions {
      let startedAt = now()
      let response = try await client.complete(
        request: request(
          source: source,
          expansion: expansion,
          contentsByPath: contentsByPath,
          allowedTags: allowedTags.sorted()
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

      if let module = try parseModule(
        response.json,
        expansion: expansion,
        allowedTags: allowedTags
      ) {
        modules.append(module)
      }
    }

    return modules
  }

  private func request(
    source: Source,
    expansion: CapabilityExpansion,
    contentsByPath: [String: String],
    allowedTags: [String]
  ) -> LLMRequest {
    LLMRequest(
      model: model,
      messages: [
        LLMMessage(
          role: .system,
          content: """
          You are Pass 2 of gunk's capability-centric decomposition pipeline.
          Deep-read one expanded capability closure and return structured JSON only.

          Real-module rubric:
          - Keep only files needed for the reusable capability.
          - Separate owned files from shared dependencies.
          - Use only allowed tags and only files present in the closure.
          - Return module null with a reject reason if this is not a real module.
          """
        ),
        LLMMessage(
          role: .user,
          content: """
          Source: \(source.name)
          Allowed tags: \(allowedTags.joined(separator: ", "))

          Candidate:
          name: \(expansion.hypothesis.name)
          rationale: \(expansion.hypothesis.rationale)
          anchors: \(expansion.hypothesis.anchors.joined(separator: ", "))
          expected collaborators: \(expansion.hypothesis.expectedCollaborators.joined(separator: ", "))

          Closure:
          owned candidates: \(expansion.ownedFiles.joined(separator: ", "))
          shared dependency candidates: \(expansion.sharedDependencyFiles.joined(separator: ", "))
          excluded files: \(expansion.excludedFiles.map { "\($0.path) (\($0.reason))" }.joined(separator: ", "))

          Edge evidence:
          \(edgeEvidenceContext(expansion.edgeEvidence))

          Closure file contents:
          \(fileContentsContext(expansion: expansion, contentsByPath: contentsByPath))
          """
        )
      ],
      jsonSchemaName: "CapabilityRefinement",
      jsonSchema: Self.outputSchema(allowedTags: allowedTags),
      maxTokens: maxOutputTokens,
      temperature: 0
    )
  }

  private func edgeEvidenceContext(_ evidence: [CapabilityExpansionEdgeEvidence]) -> String {
    guard !evidence.isEmpty else {
      return "- none"
    }

    return evidence.map { edge in
      "- \(edge.fromPath) --\(edge.kind.rawValue)--> \(edge.toPath) depth=\(edge.depth)"
    }
    .joined(separator: "\n")
  }

  private func fileContentsContext(
    expansion: CapabilityExpansion,
    contentsByPath: [String: String]
  ) -> String {
    var remainingBudget = options.maxContextCharacters
    var blocks: [String] = []

    for path in expansion.closureFiles.sorted() {
      guard remainingBudget > 0 else {
        blocks.append("### \(path)\n[omitted: context budget exhausted]")
        continue
      }

      let contents = contentsByPath[path] ?? "[contents unavailable]"
      let fileBudget = min(options.maxFileCharacters, remainingBudget)
      let clipped = String(contents.prefix(fileBudget))
      let suffix = contents.count > clipped.count ? "\n[truncated]" : ""
      let block = "### \(path)\n\(clipped)\(suffix)"

      blocks.append(block)
      remainingBudget -= block.count
    }

    return blocks.joined(separator: "\n\n")
  }

  private func parseModule(
    _ value: JSONValue,
    expansion: CapabilityExpansion,
    allowedTags: Set<String>
  ) throws -> Module? {
    guard let root = value.objectValue,
          let moduleValue = root["module"],
          root["qualityGateHints"]?.objectValue != nil,
          root["reject"] != nil else {
      throw CapabilityRefinerError.invalidResponse
    }

    if moduleValue == .null {
      return nil
    }

    guard let object = moduleValue.objectValue,
          let name = object["name"]?.stringValue?.trimmedNonEmpty,
          let purpose = object["purpose"]?.stringValue?.trimmedNonEmpty,
          let ownedFiles = object["ownedFiles"]?.arrayValue?.compactMap(\.stringValue).mapNonEmptyStrings(),
          let sharedDeps = object["sharedDependencies"]?.arrayValue?.compactMap(\.stringValue).mapNonEmptyStrings(),
          let language = object["language"]?.stringValue?.trimmedNonEmpty,
          let confidence = object["confidence"]?.doubleValue else {
      throw CapabilityRefinerError.invalidResponse
    }

    let closureFiles = Set(expansion.closureFiles)
    let uniqueSharedDeps = sharedDeps.uniqued().filter { closureFiles.contains($0) }
    let sharedSet = Set(uniqueSharedDeps)
    let uniqueOwnedFiles = ownedFiles.uniqued().filter { closureFiles.contains($0) && !sharedSet.contains($0) }
    let finalFiles = (uniqueOwnedFiles + uniqueSharedDeps).uniqued()

    guard !finalFiles.isEmpty else {
      return nil
    }

    let tags = object["tags"]?.arrayValue?
      .compactMap(\.stringValue)
      .filter { allowedTags.contains($0) }
      .uniqued() ?? []
    let anchors = object["anchors"]?.arrayValue?
      .compactMap(\.stringValue)
      .mapNonEmptyStrings()
      .uniqued() ?? expansion.hypothesis.anchors
    let surface = parseSurface(
      object["entrypoints"]?.arrayValue ?? [],
      allowedFiles: Set(finalFiles)
    )

    return Module(
      name: name,
      purpose: purpose,
      tags: tags,
      files: finalFiles,
      language: language,
      confidence: confidence.clamped(to: 0...1),
      ownedFiles: uniqueOwnedFiles,
      sharedDeps: uniqueSharedDeps,
      surface: surface,
      anchors: anchors
    )
  }

  private func parseSurface(_ values: [JSONValue], allowedFiles: Set<String>) -> [ModuleSurface] {
    values.compactMap { value -> ModuleSurface? in
      guard let object = value.objectValue,
            let path = object["path"]?.stringValue?.trimmedNonEmpty,
            allowedFiles.contains(path) else {
        return nil
      }

      return ModuleSurface(
        path: path,
        symbol: object["symbol"]?.stringValue?.trimmedNonEmpty
      )
    }
    .uniqued()
  }

  static func outputSchema(allowedTags: [String]) -> JSONValue {
    let moduleSchema: JSONValue = .object([
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
        "language": .object(["type": .string("string")]),
        "ownedFiles": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")])
        ]),
        "sharedDependencies": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")])
        ]),
        "entrypoints": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("object"),
            "properties": .object([
              "path": .object(["type": .string("string")]),
              "symbol": .object(["type": .string("string")])
            ]),
            "required": .array([.string("path"), .string("symbol")]),
            "additionalProperties": .bool(false)
          ])
        ]),
        "anchors": .object([
          "type": .string("array"),
          "items": .object(["type": .string("string")])
        ]),
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
        .string("language"),
        .string("ownedFiles"),
        .string("sharedDependencies"),
        .string("entrypoints"),
        .string("anchors"),
        .string("confidence")
      ]),
      "additionalProperties": .bool(false)
    ])

    return .object([
      "type": .string("object"),
      "properties": .object([
        "module": .object([
          "anyOf": .array([
            moduleSchema,
            .object(["type": .string("null")])
          ])
        ]),
        "qualityGateHints": .object([
          "type": .string("object"),
          "properties": .object([
            "externalFacingCapability": .object(["type": .string("boolean")]),
            "multiFileCohesion": .object(["type": .string("boolean")]),
            "anchorPresent": .object(["type": .string("boolean")]),
            "rightGranularity": .object(["type": .string("boolean")])
          ]),
          "required": .array([
            .string("externalFacingCapability"),
            .string("multiFileCohesion"),
            .string("anchorPresent"),
            .string("rightGranularity")
          ]),
          "additionalProperties": .bool(false)
        ]),
        "reject": .object([
          "anyOf": .array([
            .object([
              "type": .string("object"),
              "properties": .object([
                "reason": .object(["type": .string("string")])
              ]),
              "required": .array([.string("reason")]),
              "additionalProperties": .bool(false)
            ]),
            .object(["type": .string("null")])
          ])
        ])
      ]),
      "required": .array([.string("module"), .string("qualityGateHints"), .string("reject")]),
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

private extension Array where Element == String {
  func mapNonEmptyStrings() -> [String] {
    compactMap(\.trimmedNonEmpty)
  }
}

private extension Array where Element: Hashable {
  func uniqued() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
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
