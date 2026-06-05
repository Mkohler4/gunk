import Foundation

enum CapabilitySurveyError: Error, Equatable {
  case invalidResponse
}

final class CapabilitySurvey {
  private let store: Store
  private let provider: LLMProvider
  private let model: String
  private let maxOutputTokens: Int
  private let now: () -> Int64

  init(
    store: Store,
    provider: LLMProvider,
    model: String,
    maxOutputTokens: Int = 4_096,
    now: @escaping () -> Int64 = Store.currentTimeInMilliseconds
  ) {
    self.store = store
    self.provider = provider
    self.model = model
    self.maxOutputTokens = maxOutputTokens
    self.now = now
  }

  func survey(source: Source, repoMap: String, using client: LLMClient) async throws -> [CapabilityHypothesis] {
    let sourceFiles = try store.filesForSource(sourceId: source.id)
    let knownFiles = Set(sourceFiles.map(\.relpath))

    let startedAt = now()
    let response = try await client.complete(
      request: request(source: source, repoMap: repoMap, knownFiles: sourceFiles.map(\.relpath))
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

    return try parseHypotheses(response.json, knownFiles: knownFiles)
  }

  private func request(source: Source, repoMap: String, knownFiles: [String]) -> LLMRequest {
    LLMRequest(
      model: model,
      messages: [
        LLMMessage(
          role: .system,
          content: """
          You are Pass 1 of gunk's capability-centric decomposition pipeline.
          Propose capability hypotheses from the structural repo map only.

          Real-module rubric:
          - A real module is a reusable capability or feature slice that spans the files needed to stand alone.
          - Prefer user-visible or integration-visible capabilities such as OAuth login, Stripe checkout, upload pipeline, API endpoint group, CLI command, SDK client, or workflow.
          - Reject file-level chunks, type-only files, generic utilities, config-only groups, generated files, docs-only groups, and arbitrary folders.
          - Each hypothesis needs at least one structural anchor: route, entrypoint, public export, dependency capability hint, env/config key, or strongly connected graph cluster.
          - Name the capability by what it does, not by a filename.
          """
        ),
        LLMMessage(
          role: .user,
          content: """
          Source: \(source.name)

          Known source files:
          \(knownFiles.sorted().map { "- \($0)" }.joined(separator: "\n"))

          Return capability hypotheses with anchors, seed files, expected collaborators, and granularity.

          Structural repo map:
          \(repoMap)
          """
        )
      ],
      jsonSchemaName: "CapabilitySurvey",
      jsonSchema: Self.outputSchema(),
      maxTokens: maxOutputTokens,
      temperature: 0
    )
  }

  private func parseHypotheses(_ value: JSONValue, knownFiles: Set<String>) throws -> [CapabilityHypothesis] {
    guard let hypotheses = value.objectValue?["hypotheses"]?.arrayValue else {
      throw CapabilitySurveyError.invalidResponse
    }

    return try hypotheses.compactMap { value in
      guard let object = value.objectValue,
            let name = object["name"]?.stringValue?.trimmedNonEmpty,
            let rationale = object["rationale"]?.stringValue?.trimmedNonEmpty,
            let anchors = object["anchors"]?.arrayValue?.compactMap(\.stringValue).mapNonEmptyStrings(),
            let seedFiles = object["seedFiles"]?.arrayValue?.compactMap(\.stringValue).mapNonEmptyStrings(),
            let expectedCollaborators = object["expectedCollaborators"]?.arrayValue?.compactMap(\.stringValue).mapNonEmptyStrings(),
            let granularity = object["granularity"]?.stringValue?.trimmedNonEmpty else {
        throw CapabilitySurveyError.invalidResponse
      }

      let uniqueSeedFiles = seedFiles.uniqued()
      let uniqueCollaborators = expectedCollaborators.uniqued()
      let citedFiles = Set(uniqueSeedFiles + uniqueCollaborators.filter { knownFiles.contains($0) })

      guard !uniqueSeedFiles.isEmpty,
            uniqueSeedFiles.allSatisfy({ knownFiles.contains($0) }) else {
        return nil
      }

      if uniqueCollaborators.contains(where: { !knownFiles.contains($0) }) {
        return nil
      }

      let priority: CapabilityHypothesis.Priority = anchors.isEmpty && citedFiles.count < 2 ? .low : .normal

      return CapabilityHypothesis(
        name: name,
        rationale: rationale,
        anchors: anchors.uniqued(),
        seedFiles: uniqueSeedFiles,
        expectedCollaborators: uniqueCollaborators,
        granularity: granularity,
        priority: priority
      )
    }
  }

  static func outputSchema() -> JSONValue {
    .object([
      "type": .string("object"),
      "properties": .object([
        "hypotheses": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("object"),
            "properties": .object([
              "name": .object(["type": .string("string")]),
              "rationale": .object(["type": .string("string")]),
              "anchors": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")])
              ]),
              "seedFiles": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")])
              ]),
              "expectedCollaborators": .object([
                "type": .string("array"),
                "items": .object(["type": .string("string")])
              ]),
              "granularity": .object(["type": .string("string")])
            ]),
            "required": .array([
              .string("name"),
              .string("rationale"),
              .string("anchors"),
              .string("seedFiles"),
              .string("expectedCollaborators"),
              .string("granularity")
            ]),
            "additionalProperties": .bool(false)
          ])
        ])
      ]),
      "required": .array([.string("hypotheses")]),
      "additionalProperties": .bool(false)
    ])
  }
}

private extension Array where Element == String {
  func mapNonEmptyStrings() -> [String] {
    compactMap(\.trimmedNonEmpty)
  }

  func uniqued() -> [String] {
    var seen = Set<String>()
    return filter { seen.insert($0).inserted }
  }
}

private extension String {
  var trimmedNonEmpty: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}
