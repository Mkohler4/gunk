import Foundation

/// The result of generating an analysis: the content plus the model that wrote
/// it (for the honesty footer). The generation seam (`BrowseModel`) returns
/// this so the model name is recorded alongside the cached text.
struct GeneratedAnalysis: Sendable {
  let content: ModuleAnalysisContent
  let model: String?
}

enum ModuleAnalysisError: Error, Equatable {
  /// The model returned nothing usable — treated as "not analyzed" so we never
  /// cache an empty shell.
  case emptyAnalysis
}

extension ModuleAnalysisError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .emptyAnalysis:
      return "The analysis came back empty. Try again."
    }
  }
}

/// The production "How this works" generator: resolves the user's configured
/// provider/model and key exactly as the rest of the app does (the
/// `llm.provider`/`llm.model` defaults + the keychain), builds the request via
/// `ModuleAnalysisComposer`, and parses the structured response.
///
/// This is the default seam `BrowseModel` calls; tests inject a canned closure
/// instead so no network is touched.
enum LiveModuleAnalysisGenerator {
  static func generate(
    input: ModuleAnalysisInput,
    userDefaults: UserDefaults = .standard,
    secretStore: SecretStore = KeychainStore()
  ) async throws -> GeneratedAnalysis {
    let provider = selectedProvider(userDefaults)
    let model = selectedModel(for: provider, userDefaults)
    let client = try makeClient(provider: provider, secretStore: secretStore)

    let response = try await client.complete(
      request: ModuleAnalysisComposer.request(for: input, model: model)
    )

    guard let content = ModuleAnalysisComposer.parse(response.json) else {
      throw ModuleAnalysisError.emptyAnalysis
    }

    return GeneratedAnalysis(content: content, model: model)
  }

  private static func makeClient(
    provider: LLMProvider,
    secretStore: SecretStore
  ) throws -> LLMClient {
    switch provider {
    case .ollama:
      return OllamaClient()
    case .openAI:
      return OpenAIClient(apiKey: try requireKey(provider, secretStore))
    case .anthropic:
      return AnthropicClient(apiKey: try requireKey(provider, secretStore))
    }
  }

  private static func requireKey(_ provider: LLMProvider, _ secretStore: SecretStore) throws -> String {
    guard let key = try secretStore.secret(for: provider.secretAccount), !key.isEmpty else {
      throw LLMClientError.missingAPIKey
    }
    return key
  }

  private static func selectedProvider(_ userDefaults: UserDefaults) -> LLMProvider {
    if let raw = userDefaults.string(forKey: "llm.provider"),
       let provider = LLMProvider(rawValue: raw) {
      return provider
    }
    return .openAI
  }

  private static func selectedModel(for provider: LLMProvider, _ userDefaults: UserDefaults) -> String {
    let model = userDefaults.string(forKey: "llm.model") ?? ""
    return model.isEmpty ? provider.defaultModel : model
  }
}
