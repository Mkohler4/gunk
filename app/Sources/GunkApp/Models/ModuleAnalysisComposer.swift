import Foundation

/// The signals a "How this works" analysis is generated from — everything the
/// module already exposes (no new store state). The composer turns these into
/// the model prompt; `BrowseModel.analysisInput(for:)` assembles it from a
/// `BrowseModuleDetail`.
struct ModuleAnalysisInput: Equatable, Sendable {
  let name: String
  let purpose: String?
  let language: String?
  let entrypoints: [BrowseEntrypoint]
  let requirements: ModuleRequirements?
  let ownedFiles: [String]
  /// The "Call it" snippets (T-10.5) — the human-facing invocation shape, a
  /// strong hint for the data-flow and key-function read.
  let callItSnippets: [CallItSnippet]
}

/// Builds the model request for a "How this works" analysis and parses the
/// structured response. Pure and side-effect-free: no I/O, no store, no live
/// model call — `BrowseModel` owns the actual `LLMClient.complete` so this
/// stays unit-testable (prompt shape, schema, parsing) without a network.
enum ModuleAnalysisComposer {
  static let jsonSchemaName = "module_analysis"

  static func request(for input: ModuleAnalysisInput, model: String) -> LLMRequest {
    LLMRequest(
      model: model,
      messages: [
        LLMMessage(role: .system, content: systemPrompt()),
        LLMMessage(role: .user, content: userPrompt(for: input)),
      ],
      jsonSchemaName: jsonSchemaName,
      jsonSchema: jsonSchema(),
      maxTokens: 1_200,
      temperature: 0.2
    )
  }

  static func systemPrompt() -> String {
    """
    You explain how a small software module works to a developer who is deciding \
    whether to reuse it. Be precise, concrete, and honest. Base everything on the \
    facts provided — never invent functions, files, or dependencies that are not \
    shown. If a section has nothing to say, return an empty list for it rather \
    than padding it.

    Write:
    - summary: one or two plain sentences on what the module does.
    - dataFlow: the path data takes, input → transform → output, as ordered steps.
    - keyFunctions: the few functions or symbols a reader must know. `name` is the \
    literal symbol (it will be shown as code); `role` is one plain sentence.
    - touches: what the module reads, writes, depends on, or reaches (files, \
    packages, env vars, network) — facts, not warnings.
    - limits: honest caveats — what it does not handle and the assumptions it makes.

    Do not use Markdown formatting inside any field. Keep each line short.
    """
  }

  static func userPrompt(for input: ModuleAnalysisInput) -> String {
    var lines: [String] = ["Module: \(input.name)"]

    if let language = input.language, !language.isEmpty {
      lines.append("Language: \(language)")
    }
    if let purpose = input.purpose, !purpose.isEmpty {
      lines.append("Purpose: \(purpose)")
    }

    if !input.entrypoints.isEmpty {
      lines.append("Entrypoints:")
      for entrypoint in input.entrypoints {
        if let symbol = entrypoint.symbol, !symbol.isEmpty {
          lines.append("  - \(entrypoint.path) · \(symbol)")
        } else {
          lines.append("  - \(entrypoint.path)")
        }
      }
    }

    if let requirements = input.requirements {
      if let runtime = requirements.runtime, !runtime.isEmpty {
        lines.append("Runtime: \(runtime)")
      }
      if !requirements.packages.isEmpty {
        lines.append("Packages: \(requirements.packages.joined(separator: ", "))")
      }
      if !requirements.env.isEmpty {
        lines.append("Env vars: \(requirements.env.joined(separator: ", "))")
      }
    }

    if !input.ownedFiles.isEmpty {
      lines.append("Files:")
      // Cap the file list so a large module doesn't blow the prompt; the
      // entrypoints + call-it snippet carry the structural signal.
      for file in input.ownedFiles.prefix(40) {
        lines.append("  - \(file)")
      }
    }

    if !input.callItSnippets.isEmpty {
      lines.append("How a developer calls it:")
      for snippet in input.callItSnippets {
        lines.append(snippet.code)
      }
    }

    return lines.joined(separator: "\n")
  }

  static func jsonSchema() -> JSONValue {
    .object([
      "type": .string("object"),
      "additionalProperties": .bool(false),
      "properties": .object([
        "summary": .object(["type": .string("string")]),
        "dataFlow": stringArraySchema,
        "keyFunctions": .object([
          "type": .string("array"),
          "items": .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
              "name": .object(["type": .string("string")]),
              "role": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("name"), .string("role")]),
          ]),
        ]),
        "touches": stringArraySchema,
        "limits": stringArraySchema,
      ]),
      "required": .array([
        .string("summary"),
        .string("dataFlow"),
        .string("keyFunctions"),
        .string("touches"),
        .string("limits"),
      ]),
    ])
  }

  private static let stringArraySchema = JSONValue.object([
    "type": .string("array"),
    "items": .object(["type": .string("string")]),
  ])

  /// Maps a model's structured JSON into `ModuleAnalysisContent`. Returns `nil`
  /// when the payload is unusable (no object, or nothing to show) so the caller
  /// treats it as "not analyzed" rather than caching an empty shell.
  static func parse(_ json: JSONValue) -> ModuleAnalysisContent? {
    guard let object = json.objectValue else {
      return nil
    }

    let content = ModuleAnalysisContent(
      summary: object["summary"]?.stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
      dataFlow: stringList(object["dataFlow"]),
      keyFunctions: functionList(object["keyFunctions"]),
      touches: stringList(object["touches"]),
      limits: stringList(object["limits"])
    )

    return content.isEmpty ? nil : content
  }

  private static func stringList(_ value: JSONValue?) -> [String] {
    (value?.arrayValue ?? [])
      .compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func functionList(_ value: JSONValue?) -> [AnalysisFunction] {
    (value?.arrayValue ?? []).compactMap { item in
      guard let object = item.objectValue,
            let name = object["name"]?.stringValue?
              .trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
      else {
        return nil
      }

      let role = object["role"]?.stringValue?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return AnalysisFunction(name: name, role: role)
    }
  }
}
