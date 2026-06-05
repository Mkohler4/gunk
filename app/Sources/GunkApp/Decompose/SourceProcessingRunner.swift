import Foundation

@MainActor
final class SourceProcessingRunner {
  typealias ClientFactory = @MainActor (LLMProvider, String, SecretStore) throws -> LLMClient

  private let store: Store
  private let processingModel: ProcessingModel
  private let secretStore: SecretStore
  private let userDefaults: UserDefaults
  private let fileManager: FileManager
  private let notificationCenter: NotificationCenter
  private let gunkHome: URL
  private let clientFactory: ClientFactory
  private let contextBudgetTokens: Int

  init(
    store: Store,
    processingModel: ProcessingModel,
    secretStore: SecretStore = KeychainStore(),
    userDefaults: UserDefaults = .standard,
    fileManager: FileManager = .default,
    notificationCenter: NotificationCenter = .default,
    gunkHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gunk"),
    contextBudgetTokens: Int = 20_000,
    clientFactory: @escaping ClientFactory = SourceProcessingRunner.liveClient
  ) {
    self.store = store
    self.processingModel = processingModel
    self.secretStore = secretStore
    self.userDefaults = userDefaults
    self.fileManager = fileManager
    self.notificationCenter = notificationCenter
    self.gunkHome = gunkHome
    self.contextBudgetTokens = contextBudgetTokens
    self.clientFactory = clientFactory
  }

  func process(source: Source) async {
    processingModel.begin(sourceId: source.id)

    do {
      try await run(source: source)
      processingModel.complete(sourceId: source.id)
      notificationCenter.post(name: .gunkInserted, object: source)
    } catch {
      processingModel.fail(sourceId: source.id, error: error)
    }
  }

  private func run(source: Source) async throws {
    let provider = selectedProvider()
    let model = selectedModel(for: provider)
    let client = try clientFactory(provider, model, secretStore)
    let sourceURL = URL(fileURLWithPath: source.path)

    let files = try SourceScanner(
      fileManager: fileManager,
      store: store,
      sourceId: source.id
    ).scan(folder: sourceURL)
    processingModel.update(sourceId: source.id, progress: 0.2)

    let context = try ContextBuilder(fileManager: fileManager)
      .build(files: files, budgetTokens: contextBudgetTokens)
    processingModel.update(sourceId: source.id, progress: 0.35)

    let modules = try await DecompositionEngine(
      store: store,
      provider: provider,
      model: model
    ).decompose(source: source, context: context, using: client)
    processingModel.update(
      sourceId: source.id,
      progress: 0.8,
      modulesFound: modules.count
    )

    try extractHighConfidenceGunks(sourceId: source.id)
    processingModel.update(
      sourceId: source.id,
      progress: 1,
      modulesFound: modules.count
    )
  }

  private func extractHighConfidenceGunks(sourceId: Int64) throws {
    let threshold = confidenceThreshold()
    let extractor = Extractor(
      store: store,
      gunkHome: gunkHome,
      confidenceThreshold: threshold,
      fileManager: fileManager
    )

    for gunk in try store.gunksForSource(sourceId: sourceId) {
      guard (gunk.confidence ?? 0) >= threshold,
            gunk.extractedAt == nil else {
        continue
      }

      _ = try extractor.extract(gunk: gunk)
    }
  }

  private func selectedProvider() -> LLMProvider {
    if let rawValue = userDefaults.string(forKey: "llm.provider"),
       let provider = LLMProvider(rawValue: rawValue) {
      return provider
    }

    return .openAI
  }

  private func selectedModel(for provider: LLMProvider) -> String {
    let model = userDefaults.string(forKey: "llm.model") ?? ""
    return model.isEmpty ? provider.defaultModel : model
  }

  private func confidenceThreshold() -> Double {
    guard userDefaults.object(forKey: "llm.confidenceThreshold") != nil else {
      return Extractor.defaultConfidenceThreshold
    }

    return userDefaults.double(forKey: "llm.confidenceThreshold")
  }

  private static func liveClient(
    provider: LLMProvider,
    model: String,
    secretStore: SecretStore
  ) throws -> LLMClient {
    _ = model

    switch provider {
    case .openAI:
      return OpenAIClient(
        apiKey: try secretStore.secret(for: provider.secretAccount) ?? ""
      )
    case .anthropic:
      return AnthropicClient(
        apiKey: try secretStore.secret(for: provider.secretAccount) ?? ""
      )
    case .ollama:
      return OllamaClient()
    }
  }
}
