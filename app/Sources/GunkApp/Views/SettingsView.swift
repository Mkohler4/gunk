import SwiftUI

struct SettingsView: View {
  @AppStorage("llm.provider") private var providerRawValue = LLMProvider.openAI.rawValue
  @AppStorage("llm.model") private var model = LLMProvider.openAI.defaultModel
  @AppStorage("llm.confidenceThreshold") private var confidenceThreshold = 0.7

  @State private var apiKey: String
  @State private var statusMessage: String?
  @State private var isTestingConnection = false

  private let secretStore: SecretStore
  private let store: Store?
  private let testConnection: (LLMProvider, String, String) async throws -> Void

  init(
    store: Store? = nil,
    provider: LLMProvider = .openAI,
    model: String? = nil,
    apiKey: String = "",
    confidenceThreshold: Double = 0.7,
    secretStore: SecretStore = KeychainStore(),
    testConnection: @escaping (LLMProvider, String, String) async throws -> Void = SettingsView.liveTestConnection
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
    self.store = store
    self.secretStore = secretStore
    self.testConnection = testConnection
  }

  var body: some View {
    Form {
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

      if let store {
        Divider()

        CostMeterView(store: store)
      }
    }
    .formStyle(.grouped)
    .padding(16)
    .frame(width: 420)
    .onAppear {
      loadSecret(for: selectedProvider)
    }
  }

  private func save() {
    do {
      if selectedProvider != .ollama {
        try secretStore.setSecret(apiKey, for: selectedProvider.secretAccount)
      }
      statusMessage = "Saved"
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  private func runConnectionTest() async {
    isTestingConnection = true
    defer { isTestingConnection = false }

    do {
      save()
      try await testConnection(selectedProvider, model, apiKey)
      statusMessage = "Connection ok"
    } catch {
      statusMessage = error.localizedDescription
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
