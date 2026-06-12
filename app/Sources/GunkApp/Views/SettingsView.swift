import Foundation
import SwiftUI

struct SettingsStatusItem: Equatable {
  enum State: String {
    case ready = "Ready"
    case needsSetup = "Needs setup"
    case unavailable = "Unavailable"
  }

  let title: String
  let value: String
  let message: String
  let state: State
}

struct SettingsStatusSnapshot: Equatable {
  let configuration: SettingsStatusItem
  let apiKey: SettingsStatusItem
  let store: SettingsStatusItem
  let engine: SettingsStatusItem

  static func make(
    provider: LLMProvider,
    model: String,
    storePath: String?,
    secretStore: SecretStore,
    resolveEngine: () -> ResolvedEngine?
  ) -> SettingsStatusSnapshot {
    SettingsStatusSnapshot(
      configuration: configurationStatus(provider: provider, model: model),
      apiKey: apiKeyStatus(provider: provider, secretStore: secretStore),
      store: storeStatus(path: storePath),
      engine: engineStatus(resolveEngine: resolveEngine)
    )
  }

  private static func configurationStatus(provider: LLMProvider, model: String) -> SettingsStatusItem {
    let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedModel.isEmpty {
      return SettingsStatusItem(
        title: "Provider / model",
        value: provider.rawValue,
        message: "Choose a model before dropping a source.",
        state: .needsSetup
      )
    }

    return SettingsStatusItem(
      title: "Provider / model",
      value: "\(provider.rawValue) · \(trimmedModel)",
      message: "New decompositions use this provider and model.",
      state: .ready
    )
  }

  private static func apiKeyStatus(provider: LLMProvider, secretStore: SecretStore) -> SettingsStatusItem {
    if provider == .ollama {
      return SettingsStatusItem(
        title: "API key",
        value: "Not required",
        message: "Ollama runs locally and does not use a hosted provider key.",
        state: .ready
      )
    }

    do {
      let secret = try secretStore.secret(for: provider.secretAccount) ?? ""
      if secret.isEmpty {
        return SettingsStatusItem(
          title: "API key",
          value: "Missing",
          message: "Save a \(provider.rawValue) API key before processing sources with this provider.",
          state: .needsSetup
        )
      }

      return SettingsStatusItem(
        title: "API key",
        value: "Saved in Keychain",
        message: "The key is stored locally in Keychain, not in SQLite.",
        state: .ready
      )
    } catch {
      return SettingsStatusItem(
        title: "API key",
        value: "Unavailable",
        message: error.localizedDescription,
        state: .unavailable
      )
    }
  }

  private static func storeStatus(path: String?) -> SettingsStatusItem {
    guard let path, !path.isEmpty else {
      return SettingsStatusItem(
        title: "Local store",
        value: "In-memory",
        message: "Engine processing requires an on-disk SQLite store.",
        state: .needsSetup
      )
    }

    return SettingsStatusItem(
      title: "Local store",
      value: path,
      message: "The app, engine, and MCP server share this SQLite database.",
      state: .ready
    )
  }

  private static func engineStatus(resolveEngine: () -> ResolvedEngine?) -> SettingsStatusItem {
    guard let resolved = resolveEngine() else {
      return SettingsStatusItem(
        title: "Engine binary",
        value: "Not found",
        message: "Build the app with `make app`, or set GUNK_ENGINE_BIN for development.",
        state: .needsSetup
      )
    }

    let path = resolved.executableURL.path
    let mode = resolved.leadingArguments.isEmpty ? "binary" : "dev runner"
    return SettingsStatusItem(
      title: "Engine binary",
      value: path,
      message: "Resolved \(mode) for source decomposition.",
      state: .ready
    )
  }
}

@MainActor
struct SettingsView: View {
  @AppStorage("llm.provider") private var providerRawValue = LLMProvider.openAI.rawValue
  @AppStorage("llm.model") private var model = LLMProvider.openAI.defaultModel
  @AppStorage("llm.confidenceThreshold") private var confidenceThreshold = 0.7

  @State private var apiKey: String
  @State private var statusSnapshot: SettingsStatusSnapshot?
  @State private var statusMessage: String?
  @State private var isTestingConnection = false

  /// Shared with the shell's chip and the setup sheet (T-8.10): one
  /// `MCPClientConfigurator` source, so a toggle here re-checks everywhere.
  @ObservedObject private var mcpSetup: MCPSetupModel

  private let secretStore: SecretStore
  private let testConnection: (LLMProvider, String, String) async throws -> Void
  private let storePath: String?
  private let resolveEngine: () -> ResolvedEngine?
  private let openConfig: (URL) -> Void

  init(
    provider: LLMProvider = .openAI,
    model: String? = nil,
    apiKey: String = "",
    confidenceThreshold: Double = 0.7,
    secretStore: SecretStore = KeychainStore(),
    testConnection: @escaping (LLMProvider, String, String) async throws -> Void = SettingsView.liveTestConnection,
    storePath: String? = Store.defaultURL.path,
    resolveEngine: @escaping () -> ResolvedEngine? = { EngineBinary.resolve() },
    mcpSetup: MCPSetupModel? = nil,
    openConfig: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
  ) {
    self._providerRawValue = AppStorage(
      wrappedValue: provider.rawValue,
      "llm.provider"
    )
    self._model = AppStorage(
      wrappedValue: model ?? provider.defaultModel,
      "llm.model"
    )
    self._confidenceThreshold = AppStorage(
      wrappedValue: confidenceThreshold,
      "llm.confidenceThreshold"
    )
    self._apiKey = State(initialValue: apiKey)
    self.secretStore = secretStore
    self.testConnection = testConnection
    self.storePath = storePath
    self.resolveEngine = resolveEngine
    self.mcpSetup = mcpSetup ?? MCPSetupModel()
    self.openConfig = openConfig
  }

  var body: some View {
    Form {
      Section("Provider") {
        Picker("Provider", selection: providerBinding) {
          ForEach(LLMProvider.allCases) { provider in
            Text(provider.rawValue).tag(provider)
          }
        }

        TextField("Model", text: $model)

        if selectedProvider != .ollama {
          SecureField("API key", text: $apiKey)
        }

        VStack(alignment: .leading) {
          Slider(value: $confidenceThreshold, in: 0...1, step: 0.05)
          Text(confidenceThreshold.formatted(.number.precision(.fractionLength(2))))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        HStack {
          Button("Save") {
            save()
          }

          Button(isTestingConnection ? "Testing..." : "Test connection") {
            Task {
              await runConnectionTest()
            }
          }
          .disabled(isTestingConnection)
        }

        if let statusMessage {
          Text(statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("Status") {
        if let statusSnapshot {
          statusRow(statusSnapshot.configuration)
          statusRow(statusSnapshot.apiKey)
          statusRow(statusSnapshot.store)
          statusRow(statusSnapshot.engine)
        }

        Button("Refresh status") {
          refreshStatus()
        }
      }

      // T-8.10: the old single Cursor MCP row is replaced by per-client
      // toggles backed by the same `MCPClientConfigurator` the chip and the
      // setup sheet read — statuses stay in agreement everywhere.
      Section("MCP clients") {
        ForEach(mcpSetup.rows) { row in
          mcpClientRow(row)
        }
      }
    }
    .formStyle(.grouped)
    .padding(16)
    .frame(width: 520)
    .onAppear {
      loadSecret(for: selectedProvider)
      refreshStatus()
    }
    .onChange(of: model) {
      refreshStatus()
    }
  }

  // MARK: MCP clients (T-8.10)

  private func mcpClientRow(_ row: MCPSetupModel.ClientRow) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Toggle(isOn: mcpToggleBinding(for: row)) {
        VStack(alignment: .leading, spacing: 3) {
          HStack(alignment: .firstTextBaseline) {
            Text(row.client.displayName)
              .font(.caption.weight(.medium))
            Spacer(minLength: 8)
            Text(row.displayStatus.label)
              .font(.caption2.bold())
              .foregroundStyle(mcpStatusColor(row.displayStatus))
          }

          Text(row.configURL.path)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
        }
      }
      .toggleStyle(.switch)
      .controlSize(.small)

      if let problem = mcpProblemMessage(for: row) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(problem)
            .font(.caption2)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)

          Button("Open config") {
            openConfig(row.configURL)
          }
          .font(.caption2)
        }
      }
    }
    .padding(.vertical, 3)
  }

  private func mcpToggleBinding(for row: MCPSetupModel.ClientRow) -> Binding<Bool> {
    Binding(
      get: { row.isConnected },
      set: { wired in
        if wired {
          mcpSetup.connect(row.client)
        } else {
          mcpSetup.disconnect(row.client)
        }
      }
    )
  }

  /// A wire/unwire failure (verbatim, with the open-config way out — the
  /// configurator never clobbers a malformed file) or an unreadable-config
  /// status message.
  private func mcpProblemMessage(for row: MCPSetupModel.ClientRow) -> String? {
    if let actionError = row.actionError {
      return actionError
    }
    if case .problem(let message) = row.displayStatus {
      return message
    }
    return nil
  }

  private func mcpStatusColor(_ status: MCPSetupModel.DisplayStatus) -> Color {
    switch status {
    case .connected:
      return .green
    case .notSetUp:
      return .orange
    case .notDetected:
      return .secondary
    case .problem:
      return .red
    }
  }

  private func statusRow(_ item: SettingsStatusItem) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: item.state.systemImage)
        .foregroundStyle(item.state.color)
        .frame(width: 16)

      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline) {
          Text(item.title)
            .font(.caption.weight(.medium))
          Spacer(minLength: 8)
          Text(item.state.rawValue)
            .font(.caption2.bold())
            .foregroundStyle(item.state.color)
        }

        Text(item.value)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .truncationMode(.middle)
          .textSelection(.enabled)

        Text(item.message)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 3)
  }

  private func save() {
    do {
      if selectedProvider != .ollama {
        try secretStore.setSecret(apiKey, for: selectedProvider.secretAccount)
      }
      statusMessage = "Saved"
      refreshStatus()
    } catch {
      statusMessage = error.localizedDescription
      refreshStatus()
    }
  }

  private func runConnectionTest() async {
    isTestingConnection = true
    defer { isTestingConnection = false }

    do {
      save()
      try await testConnection(selectedProvider, model, apiKey)
      statusMessage = "Connection ok"
      refreshStatus()
    } catch {
      statusMessage = error.localizedDescription
      refreshStatus()
    }
  }

  private var selectedProvider: LLMProvider {
    LLMProvider(rawValue: providerRawValue) ?? .openAI
  }

  private var providerBinding: Binding<LLMProvider> {
    Binding(
      get: { selectedProvider },
      set: { newProvider in
        providerRawValue = newProvider.rawValue
        model = newProvider.defaultModel
        loadSecret(for: newProvider)
        refreshStatus()
      }
    )
  }

  private func loadSecret(for provider: LLMProvider) {
    if provider == .ollama {
      apiKey = ""
    } else {
      apiKey = (try? secretStore.secret(for: provider.secretAccount)) ?? ""
    }
  }

  private func refreshStatus() {
    statusSnapshot = SettingsStatusSnapshot.make(
      provider: selectedProvider,
      model: model,
      storePath: storePath,
      secretStore: secretStore,
      resolveEngine: resolveEngine
    )
    mcpSetup.refresh()
  }

  private static func liveTestConnection(
    provider: LLMProvider,
    model: String,
    apiKey: String
  ) async throws {
    let request = LLMRequest(
      model: model,
      messages: [
        LLMMessage(role: .user, content: "Return {\"ok\": true}.")
      ],
      jsonSchemaName: "ConnectionSmoke",
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

    switch provider {
    case .openAI:
      _ = try await OpenAIClient(apiKey: apiKey).complete(request: request)
    case .anthropic:
      _ = try await AnthropicClient(apiKey: apiKey).complete(request: request)
    case .ollama:
      _ = try await OllamaClient().complete(request: request)
    }
  }
}

private extension SettingsStatusItem.State {
  var color: Color {
    switch self {
    case .ready:
      return .green
    case .needsSetup:
      return .orange
    case .unavailable:
      return .red
    }
  }

  var systemImage: String {
    switch self {
    case .ready:
      return "checkmark.circle"
    case .needsSetup:
      return "exclamationmark.triangle"
    case .unavailable:
      return "xmark.circle"
    }
  }
}
