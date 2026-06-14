import Foundation

/// Drives a single source through the decomposition pipeline by spawning the
/// cross-platform `gunk-engine` subprocess and mapping its NDJSON events onto
/// `ProcessingModel`. The engine writes gunks/files/embeddings directly into the
/// shared SQLite store; this type only orchestrates and reflects progress.
@MainActor
final class SourceProcessingRunner {
  private let store: Store
  private let processingModel: ProcessingModel
  private let secretStore: SecretStore
  private let userDefaults: UserDefaults
  private let notificationCenter: NotificationCenter
  private let gunkHome: URL
  private let contextBudgetTokens: Int
  private let launcher: EngineLauncher

  /// Default confidence threshold below which a module needs manual approval.
  /// Matches the engine's `confidenceThreshold` default.
  static let defaultConfidenceThreshold = 0.7

  init(
    store: Store,
    processingModel: ProcessingModel,
    secretStore: SecretStore = KeychainStore(),
    userDefaults: UserDefaults = .standard,
    notificationCenter: NotificationCenter = .default,
    gunkHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gunk"),
    contextBudgetTokens: Int = 20_000,
    launcher: EngineLauncher = ProcessEngineLauncher()
  ) {
    self.store = store
    self.processingModel = processingModel
    self.secretStore = secretStore
    self.userDefaults = userDefaults
    self.notificationCenter = notificationCenter
    self.gunkHome = gunkHome
    self.contextBudgetTokens = contextBudgetTokens
    self.launcher = launcher
  }

  func process(source: Source) async {
    processingModel.begin(sourceId: source.id)

    do {
      let outcome = try await run(source: source)
      // Durable model attribution (T-9.2): the engine wrote the gunk rows but
      // doesn't know the run's provider/model — write it app-side now that the
      // run reported its ids, so new modules are attributed without a trace
      // lookup. Best-effort: a provenance write must never fail the run.
      try? store.setGunkProvenance(
        gunkIds: outcome.gunkIds,
        provider: outcome.provider,
        model: outcome.model
      )
      processingModel.complete(sourceId: source.id)
      notificationCenter.post(name: .gunkInserted, object: source)
    } catch {
      processingModel.fail(sourceId: source.id, error: error)
    }
  }

  /// What a completed run produced: the persisted module ids plus the
  /// provider/model that made them (the same strings handed to the engine), so
  /// the caller can record durable attribution (T-9.2).
  private struct RunOutcome {
    let gunkIds: [Int64]
    let provider: String
    let model: String
  }

  private func run(source: Source) async throws -> RunOutcome {
    let provider = selectedProvider()
    let model = selectedModel(for: provider)

    guard let databasePath = store.databasePath else {
      throw EngineLaunchError.launchFailed("The store is in-memory; engine processing requires an on-disk database.")
    }

    let arguments = [
      source.path,
      "--provider", provider.cliName,
      "--model", model,
      "--source-id", String(source.id),
      "--db", databasePath,
      "--gunk-home", gunkHome.path,
      "--confidence", String(confidenceThreshold()),
      "--context-budget", String(contextBudgetTokens),
      "--json",
      "--trace",
    ]

    let stream = launcher.launch(arguments: arguments, environment: try environment(for: provider))

    var sawResult = false
    var resultGunkIds: [Int64] = []
    for try await event in stream {
      switch event {
      case .progress(_, let fraction, let modulesFound):
        processingModel.update(sourceId: source.id, progress: fraction, modulesFound: modulesFound)
      case .stage:
        break
      case .result(_, let gunkIds, _, _, _, _):
        sawResult = true
        resultGunkIds = gunkIds
        processingModel.update(sourceId: source.id, progress: 1, modulesFound: gunkIds.count)
      case .error(let message, _):
        throw EngineLaunchError.engineFailed(message)
      }
    }

    if !sawResult {
      throw EngineLaunchError.missingResult
    }

    // Store the same provider/model strings the engine was launched with, so a
    // stored value matches what the trace-derived fallback would have produced.
    return RunOutcome(gunkIds: resultGunkIds, provider: provider.cliName, model: model)
  }

  private func environment(for provider: LLMProvider) throws -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    if provider != .ollama, let apiKey = try secretStore.secret(for: provider.secretAccount), !apiKey.isEmpty {
      environment["GUNK_API_KEY"] = apiKey
    }
    return environment
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
      return SourceProcessingRunner.defaultConfidenceThreshold
    }

    return userDefaults.double(forKey: "llm.confidenceThreshold")
  }
}

private extension LLMProvider {
  /// CLI token understood by `gunk-engine --provider`.
  var cliName: String {
    switch self {
    case .openAI:
      return "openai"
    case .anthropic:
      return "anthropic"
    case .ollama:
      return "ollama"
    }
  }
}
