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
  let localModel: SettingsStatusItem
  let store: SettingsStatusItem
  let engine: SettingsStatusItem

  static func make(
    provider: LLMProvider,
    model: String,
    ollamaModel: String,
    ollamaReachability: LocalModelReachabilityState,
    storePath: String?,
    secretStore: SecretStore,
    resolveEngine: () -> ResolvedEngine?
  ) -> SettingsStatusSnapshot {
    SettingsStatusSnapshot(
      configuration: configurationStatus(provider: provider, model: model),
      apiKey: apiKeyStatus(provider: provider, secretStore: secretStore),
      localModel: localModelStatus(
        provider: provider,
        model: ollamaModel,
        reachability: ollamaReachability
      ),
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

  private static func localModelStatus(
    provider: LLMProvider,
    model: String,
    reachability: LocalModelReachabilityState
  ) -> SettingsStatusItem {
    switch reachability {
    case .reachable(let reachableModel, _):
      let activeSuffix = provider == .ollama ? " Ollama is active for new decompositions." : " Hosted provider is in use."
      return SettingsStatusItem(
        title: "Local model (Ollama)",
        value: "Reachable · \(reachableModel)",
        message: "The local server answered and \(reachableModel) is loaded.\(activeSuffix)",
        state: .ready
      )
    case .checking:
      return SettingsStatusItem(
        title: "Local model (Ollama)",
        value: "Checking",
        message: "Asking Ollama for its loaded models.",
        state: .needsSetup
      )
    case .unreachable:
      return SettingsStatusItem(
        title: "Local model (Ollama)",
        value: "Unreachable",
        message: "Ollama is configured but the app cannot reach the local server.",
        state: .unavailable
      )
    case .unchecked:
      let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
      return SettingsStatusItem(
        title: "Local model (Ollama)",
        value: provider == .ollama ? (trimmedModel.isEmpty ? "Active" : "Active · \(trimmedModel)") : "Optional",
        message: provider == .ollama
          ? "Run a reachability check to confirm the local server before processing."
          : "Not configured — hosted provider is in use.",
        state: provider == .ollama ? .needsSetup : .ready
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

enum SettingsSection: String, CaseIterable, Identifiable {
  case providerKeys
  case localModel
  case spend
  case processing
  case pipelineHealth

  var id: String { rawValue }

  var title: String {
    switch self {
    case .providerKeys:
      return "Provider & keys"
    case .localModel:
      return "Local model"
    case .spend:
      return "Spend"
    case .processing:
      return "Processing"
    case .pipelineHealth:
      return "Pipeline health"
    }
  }

  var systemImage: String {
    switch self {
    case .providerKeys:
      return "key"
    case .localModel:
      return "desktopcomputer"
    case .spend:
      return "chart.bar.doc.horizontal"
    case .processing:
      return "slider.horizontal.3"
    case .pipelineHealth:
      return "waveform.path.ecg"
    }
  }
}

private enum ProviderTestStatus: Equatable {
  case idle
  case testing
  case success(milliseconds: Int)
  case failure(String)
}

enum LocalModelReachabilityState: Equatable {
  case unchecked
  case checking
  case reachable(model: String, milliseconds: Int)
  case unreachable(String)
}

private enum LocalModelField: Hashable {
  case baseURL
  case model
}

private struct ProviderBanner: Equatable {
  enum Variant {
    case success
    case failure
  }

  let variant: Variant
  let title: String
  let message: String
}

@MainActor
struct SettingsView: View {
  @AppStorage("llm.provider") private var providerRawValue = LLMProvider.openAI.rawValue
  @AppStorage("llm.model") private var model = LLMProvider.openAI.defaultModel
  @AppStorage(LLMProvider.openAI.modelStorageKey) private var openAIModel = LLMProvider.openAI.defaultModel
  @AppStorage(LLMProvider.anthropic.modelStorageKey) private var anthropicModel = LLMProvider.anthropic.defaultModel
  @AppStorage(LLMProvider.ollama.modelStorageKey) private var ollamaModel = LLMProvider.ollama.defaultModel
  @AppStorage(OllamaClient.baseURLStorageKey) private var ollamaBaseURLText = "http://localhost:11434"
  @AppStorage(LLMSettings.confidenceThresholdKey) private var confidenceThreshold = LLMSettings.defaultConfidenceThreshold
  @AppStorage(LLMSettings.monthlyCostCapEnabledKey) private var monthlyCostCapEnabled = false
  @AppStorage(LLMSettings.monthlyCostCapUSDKey) private var monthlyCostCapUSD = LLMSettings.defaultMonthlyCostCapUSD

  @State private var selectedSection: SettingsSection
  @State private var statusSnapshot: SettingsStatusSnapshot?
  @State private var savedProviderKeys: [LLMProvider: String] = [:]
  @State private var keyReadErrors: [LLMProvider: String] = [:]
  @State private var editingProvider: LLMProvider?
  @State private var editingAPIKey: String
  @State private var editingModel: String
  @State private var providerTestStatuses: [LLMProvider: ProviderTestStatus] = [:]
  @State private var providerBanner: ProviderBanner?
  @State private var removeCandidate: LLMProvider?
  @State private var localReachability: LocalModelReachabilityState
  @State private var arrivedFromMCP = false
  @State private var spendModel: SpendModel?
  @State private var spendErrorMessage: String?
  @State private var isAdjustingConfidenceThreshold = false
  @State private var showsStagedConfidenceDrag = false
  @FocusState private var focusedLocalModelField: LocalModelField?

  /// Shared with the shell's chip and the setup sheet (T-8.10): one
  /// `MCPClientConfigurator` source, so a toggle here re-checks everywhere.
  @ObservedObject private var mcpSetup: MCPSetupModel

  private let mcpDeepLinkNonce: Int
  private let mcpDeepLinkOnAppear: Bool
  private let secretStore: SecretStore
  private let testConnection: (LLMProvider, String, String) async throws -> Void
  private let checkOllamaReachability: (URL) async throws -> [String]
  private let storePath: String?
  private let loadSpendModel: () throws -> SpendModel
  private let resolveEngine: () -> ResolvedEngine?
  private let openConfig: (URL) -> Void
  private let onOpenApproval: () -> Void
  private let onConfidenceThresholdChanged: () -> Void
  private static let hostedProviders: [LLMProvider] = [.anthropic, .openAI]

  init(
    provider: LLMProvider = .openAI,
    model: String? = nil,
    apiKey: String = "",
    confidenceThreshold: Double = LLMSettings.defaultConfidenceThreshold,
    initialSection: SettingsSection = .providerKeys,
    mcpDeepLinkNonce: Int = 0,
    mcpDeepLinkOnAppear: Bool = false,
    secretStore: SecretStore = KeychainStore(),
    testConnection: @escaping (LLMProvider, String, String) async throws -> Void = SettingsView.liveTestConnection,
    checkOllamaReachability: @escaping (URL) async throws -> [String] = SettingsView.liveOllamaReachabilityCheck,
    storePath: String? = Store.defaultURL.path,
    loadSpendModel: @escaping () throws -> SpendModel = {
      try SpendModel.load(store: Store(path: Store.defaultURL))
    },
    resolveEngine: @escaping () -> ResolvedEngine? = { EngineBinary.resolve() },
    mcpSetup: MCPSetupModel? = nil,
    openConfig: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
    onOpenApproval: @escaping () -> Void = {},
    onConfidenceThresholdChanged: @escaping () -> Void = {}
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
      LLMSettings.confidenceThresholdKey
    )
    self._monthlyCostCapEnabled = AppStorage(
      wrappedValue: false,
      LLMSettings.monthlyCostCapEnabledKey
    )
    self._monthlyCostCapUSD = AppStorage(
      wrappedValue: LLMSettings.defaultMonthlyCostCapUSD,
      LLMSettings.monthlyCostCapUSDKey
    )
    self._selectedSection = State(initialValue: initialSection)
    self._editingAPIKey = State(initialValue: apiKey)
    self._editingModel = State(initialValue: model ?? provider.defaultModel)
    self._localReachability = State(initialValue: .unchecked)
    self.mcpDeepLinkNonce = mcpDeepLinkNonce
    self.mcpDeepLinkOnAppear = mcpDeepLinkOnAppear
    self.secretStore = secretStore
    self.testConnection = testConnection
    self.checkOllamaReachability = checkOllamaReachability
    self.storePath = storePath
    self.loadSpendModel = loadSpendModel
    self.resolveEngine = resolveEngine
    self.mcpSetup = mcpSetup ?? MCPSetupModel()
    self.openConfig = openConfig
    self.onOpenApproval = onOpenApproval
    self.onConfidenceThresholdChanged = onConfidenceThresholdChanged
  }

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      sectionRail
        .frame(width: 232)

      Rectangle()
        .fill(BrandColors.separator)
        .frame(width: 1)

      detailPane
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(BrandColors.backgroundPrimary)
    .onAppear {
      migrateLegacyActiveModelIfNeeded()
      syncActiveModelFromMemory()
      refreshProviderKeyStates()
      refreshStatus()
      refreshSpend()
      applySettingsDebugOverride()
      if mcpDeepLinkOnAppear {
        activateMCPDeepLink()
      }
    }
    .onChange(of: model) {
      refreshStatus()
    }
    .onChange(of: ollamaModel) {
      if selectedProvider == .ollama {
        model = normalizedModel(ollamaModel, provider: .ollama)
      }
      resetLocalReachability()
    }
    .onChange(of: ollamaBaseURLText) {
      resetLocalReachability()
    }
    .onChange(of: providerRawValue) {
      refreshStatus()
    }
    .onChange(of: confidenceThreshold) {
      onConfidenceThresholdChanged()
    }
    .onChange(of: selectedSection) {
      if selectedSection == .spend {
        refreshSpend()
      }
    }
    .onChange(of: mcpDeepLinkNonce) {
      activateMCPDeepLink()
    }
    .confirmationDialog(
      "Remove API key?",
      isPresented: removeConfirmationBinding,
      titleVisibility: .visible,
      presenting: removeCandidate
    ) { provider in
      Button("Remove \(provider.rawValue) key", role: .destructive) {
        removeProviderKey(provider)
      }
      Button("Cancel", role: .cancel) {
        removeCandidate = nil
      }
    } message: { provider in
      Text("This clears the \(provider.rawValue) Keychain slot. The remembered model stays in Settings.")
    }
  }

  // MARK: Shell

  private var sectionRail: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
      Text("SETTINGS")
        .font(BrandTypography.caption.weight(.semibold))
        .foregroundStyle(BrandColors.textTertiary)
        .padding(.top, BrandMetrics.Spacing.lg)

      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        ForEach(SettingsSection.allCases) { section in
          railButton(section)
        }
      }

      Spacer(minLength: BrandMetrics.Spacing.lg)

      HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.sm) {
        Image(systemName: "lock")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textTertiary)
        Text("Keys stored in your Keychain")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
      }
      .padding(.bottom, BrandMetrics.Spacing.lg)
    }
    .padding(.horizontal, BrandMetrics.Spacing.lg)
    .frame(maxHeight: .infinity, alignment: .topLeading)
    .background(BrandColors.backgroundSecondary)
  }

  private func railButton(_ section: SettingsSection) -> some View {
    let isSelected = selectedSection == section
    let needsSetup = section == .pipelineHealth && !mcpSetup.isAnyClientConnected

    return Button {
      withAnimation(BrandMotion.standard) {
        selectedSection = section
      }
    } label: {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        Image(systemName: section.systemImage)
          .font(BrandTypography.callout)
          .frame(width: 16)

        Text(section.title)
          .font(BrandTypography.callout)
          .lineLimit(1)

        Spacer(minLength: BrandMetrics.Spacing.sm)

        if needsSetup {
          Circle()
            .fill(BrandColors.warning)
            .frame(width: 6, height: 6)
            .accessibilityLabel("Needs setup")
        }
      }
      .foregroundStyle(isSelected ? BrandColors.textPrimary : BrandColors.textSecondary)
      .padding(.horizontal, BrandMetrics.Spacing.sm)
      .padding(.vertical, BrandMetrics.Spacing.sm)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
          .fill(isSelected ? BrandColors.backgroundElevated : .clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
          .strokeBorder(isSelected ? BrandColors.separator : .clear)
      )
      .contentShape(RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private var detailPane: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
          switch selectedSection {
          case .providerKeys:
            providerKeysSection
          case .localModel:
            localModelSection
          case .spend:
            spendSection
          case .processing:
            processingSection
          case .pipelineHealth:
            pipelineHealthSection
          }
        }
        .frame(maxWidth: 820, alignment: .leading)
        .padding(.horizontal, BrandMetrics.Spacing.xl)
        .padding(.vertical, BrandMetrics.Spacing.xl)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .onChange(of: mcpDeepLinkNonce) {
        guard selectedSection == .pipelineHealth else {
          return
        }
        DispatchQueue.main.async {
          withAnimation(BrandMotion.standard) {
            proxy.scrollTo("mcp-server-row", anchor: .center)
          }
        }
      }
    }
  }

  private var providerKeysSection: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
      sectionHeader(
        "Bring your own key.",
        description: "gunk talks to hosted models on your behalf. Hosted keys stay in your system Keychain, never in gunk's database."
      )

      if let providerBanner {
        providerBannerView(providerBanner)
      }

      settingsPanel {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
          activeProviderHeader
          activeHostedProviderSelector
          activeProviderConsequence
        }
      }

      settingsPanel {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
          HStack(alignment: .center, spacing: BrandMetrics.Spacing.sm) {
            Text("Saved providers")
              .font(BrandTypography.headline)
              .foregroundStyle(BrandColors.textPrimary)

            Text("OpenAI and Anthropic")
              .font(BrandTypography.caption)
              .foregroundStyle(BrandColors.textSecondary)

            Spacer(minLength: BrandMetrics.Spacing.md)

            Button {
              addProvider()
            } label: {
              Label("Add provider", systemImage: "plus")
            }
            .buttonStyle(.brandSecondary)
            .disabled(firstProviderWithoutKey == nil)
          }

          Divider()
            .background(BrandColors.separator)
            .padding(.horizontal, -BrandMetrics.Spacing.lg)

          VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.hostedProviders) { provider in
              providerRow(provider)
              if provider != Self.hostedProviders.last {
                Divider()
                  .background(BrandColors.separator)
                  .padding(.horizontal, -BrandMetrics.Spacing.lg)
              }
            }
          }
        }
      }

      Text("Keys are read from your macOS Keychain at call time. gunk's database stores only which provider is active and each provider's chosen model.")
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var activeProviderHeader: some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      Image(systemName: "arrow.right")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.textSecondary)
      Text("Active hosted provider for new decompositions")
        .font(BrandTypography.headline)
        .foregroundStyle(BrandColors.textPrimary)
    }
  }

  private var activeHostedProviderSelector: some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      ForEach(Self.hostedProviders) { provider in
        hostedProviderPill(provider)
      }
    }
  }

  private var activeProviderConsequence: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      if Self.hostedProviders.contains(selectedProvider) {
        Text("Decompositions will run on \(selectedProvider.rawValue) `\(modelForDisplay(selectedProvider))`.")
      } else {
        Text("Ollama is active from the Local model flow. Choose a hosted provider here to run new decompositions on OpenAI or Anthropic.")
      }

      Text("Each provider keeps its own model, so switching here never overwrites what you typed.")
        .foregroundStyle(BrandColors.textTertiary)
    }
    .font(BrandTypography.caption)
    .foregroundStyle(BrandColors.textSecondary)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func hostedProviderPill(_ provider: LLMProvider) -> some View {
    let isActive = selectedProvider == provider
    // Selected state is tinted in the provider's own accent (the same color as
    // its `ProviderMark`), not the loud full-bleed brand green — a calm,
    // readable "selected" rather than a shouting block. No checkmark, so the
    // pill never changes width when activated.
    let providerAccent = BrandColors.providerAccent(for: provider.rawValue)

    return Button {
      activateHostedProvider(provider)
    } label: {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        ProviderMark(provider: provider.rawValue, size: 18)
        Text(provider.rawValue)
          .font(BrandTypography.callout.weight(.medium))
      }
      .foregroundStyle(BrandColors.textPrimary)
      .padding(.horizontal, BrandMetrics.Spacing.md)
      .padding(.vertical, BrandMetrics.Spacing.sm)
      .background(
        Capsule()
          .fill(
            isActive
              ? providerAccent.opacity(BrandMetrics.Control.tintedFillOpacity)
              : BrandColors.surfaceGlass
          )
      )
      .overlay(
        Capsule()
          .strokeBorder(
            isActive ? providerAccent.opacity(0.6) : BrandColors.separator,
            lineWidth: isActive ? 1.5 : 1
          )
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private func providerBannerView(_ banner: ProviderBanner) -> some View {
    let color = banner.variant == .success ? BrandColors.success : BrandColors.danger
    let icon = banner.variant == .success ? "checkmark.circle" : "xmark.circle"

    return HStack(alignment: .top, spacing: BrandMetrics.Spacing.sm) {
      Image(systemName: icon)
        .font(BrandTypography.callout)
        .foregroundStyle(color)

      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        Text(banner.title)
          .font(BrandTypography.callout.weight(.semibold))
          .foregroundStyle(BrandColors.textPrimary)
        Text(banner.message)
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(BrandMetrics.Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(color.opacity(BrandMetrics.Control.tintedFillOpacity))
    )
    .overlay(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .strokeBorder(color.opacity(0.35))
    )
  }

  private func providerRow(_ provider: LLMProvider) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
      HStack(alignment: .top, spacing: BrandMetrics.Spacing.md) {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(hasSavedKey(provider) ? BrandColors.success : BrandColors.warning)
          .frame(width: 9, height: 9)
          .padding(.top, 7)

        ProviderMark(provider: provider.rawValue, size: 22)

        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
          HStack(spacing: BrandMetrics.Spacing.sm) {
            Text(provider.rawValue)
              .font(BrandTypography.headline)
              .foregroundStyle(BrandColors.textPrimary)

            providerKeyStateBadge(provider)

            if selectedProvider == provider {
              StatusBadge("Active", variant: .success)
            }
          }

          HStack(spacing: BrandMetrics.Spacing.md) {
            Text("KEY \(maskedAPIKey(for: provider))")
            Text("MODEL \(modelForDisplay(provider))")
          }
          .font(BrandTypography.mono)
          .foregroundStyle(BrandColors.textSecondary)
          .lineLimit(1)
          .truncationMode(.middle)

          if let error = keyReadErrors[provider] {
            Text(error)
              .font(BrandTypography.caption)
              .foregroundStyle(BrandColors.danger)
              .fixedSize(horizontal: false, vertical: true)
          }
        }

        Spacer(minLength: BrandMetrics.Spacing.md)

        providerRowActions(provider)
      }

      if let testChip = providerTestChip(provider) {
        testChip
      }

      if editingProvider == provider {
        providerEditForm(provider)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .padding(.vertical, BrandMetrics.Spacing.md)
  }

  private func providerRowActions(_ provider: LLMProvider) -> some View {
    HStack(spacing: BrandMetrics.Spacing.xs) {
      Button(testButtonTitle(provider)) {
        Task {
          await runConnectionTest(provider)
        }
      }
      .buttonStyle(.brandSecondary)
      .disabled(providerTestStatuses[provider] == .testing)

      Button {
        beginEditing(provider)
      } label: {
        Image(systemName: "pencil")
      }
      .buttonStyle(.brandIcon)
      .help(hasSavedKey(provider) ? "Edit \(provider.rawValue) key and model" : "Add \(provider.rawValue) key")

      Button {
        removeCandidate = provider
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.brandIcon)
      .disabled(!hasSavedKey(provider))
      .help("Remove \(provider.rawValue) key")
    }
  }

  @ViewBuilder
  private func providerKeyStateBadge(_ provider: LLMProvider) -> some View {
    if hasSavedKey(provider) {
      StatusBadge("Key saved", variant: .success)
    } else {
      StatusBadge("No key", variant: .warning)
    }
  }

  private func providerTestChip(_ provider: LLMProvider) -> AnyView? {
    switch providerTestStatuses[provider] ?? .idle {
    case .idle:
      return nil
    case .testing:
      return AnyView(
        StatusBadge("Testing...", variant: .neutral, systemImage: "arrow.clockwise")
      )
    case .success(let milliseconds):
      return AnyView(
        StatusBadge("Connected · \(milliseconds)ms", variant: .success, systemImage: "checkmark.circle")
      )
    case .failure(let message):
      return AnyView(
        StatusBadge(message, variant: .danger, systemImage: "xmark.circle")
      )
    }
  }

  private func providerEditForm(_ provider: LLMProvider) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        Text("API key")
          .font(BrandTypography.callout)
          .foregroundStyle(BrandColors.textSecondary)
        SecureField(hasSavedKey(provider) ? "paste to replace" : "paste API key", text: $editingAPIKey)
          .textFieldStyle(.roundedBorder)
      }

      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        Text("Model for \(provider.rawValue)")
          .font(BrandTypography.callout)
          .foregroundStyle(BrandColors.textSecondary)
        TextField("Model", text: $editingModel)
          .textFieldStyle(.roundedBorder)
        Text("Remembered per provider — switching the active provider won't change this.")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textTertiary)
      }

      HStack(spacing: BrandMetrics.Spacing.sm) {
        Image(systemName: "lock")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textTertiary)
        Text("Saved to your system Keychain, never to gunk's database.")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)

        Spacer(minLength: BrandMetrics.Spacing.md)

        Button("Cancel") {
          cancelEditing()
        }
        .buttonStyle(.brandSecondary)

        Button("Save key") {
          saveProvider(provider)
        }
        .buttonStyle(.brandPrimary)
      }
    }
    .padding(BrandMetrics.Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(BrandColors.backgroundSecondary)
    )
  }

  private var localModelSection: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
      sectionHeader(
        "Run decompositions on a model you host with Ollama.",
        description: "No hosted call, no key, nothing leaves your machine."
      )

      settingsPanel {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
          HStack(alignment: .center, spacing: BrandMetrics.Spacing.sm) {
            StatusBadge("Runs locally · no key", variant: .neutral, systemImage: "desktopcomputer")
            if selectedProvider == .ollama {
              StatusBadge("Active", variant: .success, systemImage: "checkmark.circle")
            }
            Spacer(minLength: BrandMetrics.Spacing.md)
            localReachabilityBadge
          }

          VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
            Text("Host / base URL")
              .font(BrandTypography.callout)
              .foregroundStyle(BrandColors.textSecondary)
            TextField("localhost:11434", text: $ollamaBaseURLText)
              .textFieldStyle(.roundedBorder)
              .focused($focusedLocalModelField, equals: .baseURL)
            Text("Point this elsewhere if you run it on another host or port.")
              .font(BrandTypography.caption)
              .foregroundStyle(BrandColors.textTertiary)
          }

          VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
            Text("Model")
              .font(BrandTypography.callout)
              .foregroundStyle(BrandColors.textSecondary)
            TextField("llama3.2", text: localModelBinding)
              .textFieldStyle(.roundedBorder)
              .focused($focusedLocalModelField, equals: .model)
            Text("Any model you've pulled in Ollama. gunk lists what's loaded when it can reach the host.")
              .font(BrandTypography.caption)
              .foregroundStyle(BrandColors.textTertiary)
          }

          localReachabilityPanel

          Toggle(isOn: useLocalModelBinding) {
            VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
              Text("Use local model for new decompositions")
                .font(BrandTypography.callout.weight(.semibold))
                .foregroundStyle(BrandColors.textPrimary)
              Text(localToggleHelperText)
                .font(BrandTypography.caption)
                .foregroundStyle(BrandColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .toggleStyle(.switch)
          .controlSize(.small)
          .disabled(!localModelCanBecomeActive && selectedProvider != .ollama)

          localEngineCaveat
        }
      }
    }
  }

  private var localReachabilityBadge: some View {
    switch localReachability {
    case .unchecked:
      return StatusBadge("Not checked yet", variant: .neutral, systemImage: "questionmark.circle")
    case .checking:
      return StatusBadge("Checking", variant: .neutral, systemImage: "arrow.clockwise")
    case .reachable(_, let milliseconds):
      return StatusBadge("Reachable · \(milliseconds)ms", variant: .success, systemImage: "checkmark.circle")
    case .unreachable:
      return StatusBadge("Unreachable", variant: .danger, systemImage: "xmark.circle")
    }
  }

  private var localReachabilityPanel: some View {
    HStack(alignment: .top, spacing: BrandMetrics.Spacing.md) {
      Image(systemName: localReachabilityIcon)
        .font(BrandTypography.headline)
        .foregroundStyle(localReachabilityColor)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        Text(localReachabilityTitle)
          .font(BrandTypography.callout.weight(.semibold))
          .foregroundStyle(BrandColors.textPrimary)
        Text(localReachabilityMessage)
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: BrandMetrics.Spacing.md)

      Button {
        Task {
          await checkLocalReachability()
        }
      } label: {
        Label(localReachabilityButtonTitle, systemImage: "arrow.triangle.2.circlepath")
      }
      .buttonStyle(.brandSecondary)
      .disabled(localReachability == .checking || normalizedOllamaBaseURL == nil)
    }
    .padding(BrandMetrics.Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(localReachabilityColor.opacity(BrandMetrics.Control.tintedFillOpacity))
    )
    .overlay(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .strokeBorder(localReachabilityColor.opacity(0.35))
    )
  }

  @ViewBuilder
  private var localEngineCaveat: some View {
    if normalizedOllamaBaseURL != OllamaClient.defaultBaseURL {
      HStack(alignment: .top, spacing: BrandMetrics.Spacing.sm) {
        Image(systemName: "info.circle")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.warning)
        Text("In-app checks and module analysis use this host. New decompositions still use the engine's built-in Ollama host, `localhost:11434`, until engine support for custom hosts lands.")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var spendSection: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
      sectionHeader(
        "What decompositions have cost you, estimated from real token usage.",
        description: "Grouped by provider and model, computed from the tokens recorded during decomposition."
      )

      if let spendErrorMessage {
        spendErrorPanel(spendErrorMessage)
      } else if let spendModel {
        SpendView(model: spendModel)
      } else {
        settingsPanel {
          HStack(spacing: BrandMetrics.Spacing.sm) {
            ProgressView()
              .controlSize(.small)
            Text("Loading spend")
              .font(BrandTypography.body)
              .foregroundStyle(BrandColors.textSecondary)
          }
        }
      }
    }
  }

  private var processingSection: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
      sectionHeader(
        "How extracted capabilities move into your agent's toolbox.",
        description: "Decide what gunk can add by itself, and what should wait for your review."
      )

      settingsPanel {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
          HStack(alignment: .top, spacing: BrandMetrics.Spacing.lg) {
            VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
              Text("Auto-accept threshold")
                .font(BrandTypography.headline)
                .foregroundStyle(BrandColors.textPrimary)

              thresholdHelperText
                .font(BrandTypography.body)
                .foregroundStyle(BrandColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: BrandMetrics.Spacing.md)

            Text(confidencePercentText)
              .font(BrandTypography.display)
              .foregroundStyle(BrandColors.accent)
              .monospacedDigit()
              .accessibilityLabel("Auto-accept threshold \(confidencePercentText)")
          }

          VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
            thresholdSlider

            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 2) {
                Text("50%")
                  .font(BrandTypography.mono)
                  .foregroundStyle(BrandColors.textPrimary)
                Text("more reaches you")
                  .font(BrandTypography.caption)
                  .foregroundStyle(BrandColors.textTertiary)
              }

              Spacer(minLength: BrandMetrics.Spacing.md)

              VStack(alignment: .trailing, spacing: 2) {
                Text("100%")
                  .font(BrandTypography.mono)
                  .foregroundStyle(BrandColors.textPrimary)
                Text("more auto-accepts")
                  .font(BrandTypography.caption)
                  .foregroundStyle(BrandColors.textTertiary)
              }
            }
          }

          Button {
            onOpenApproval()
          } label: {
            Text("What is Approval? →")
              .font(BrandTypography.callout.weight(.semibold))
              .foregroundStyle(BrandColors.accent)
          }
          .buttonStyle(.plain)
          .help("Open the Library scoped to modules that need approval")
        }
      }

      settingsPanel {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
          Toggle(isOn: $monthlyCostCapEnabled) {
            VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
              Text("Warn me past a monthly cap")
                .font(BrandTypography.headline)
                .foregroundStyle(BrandColors.textPrimary)

              Text("A soft budget. gunk shows a warning when projected spend crosses it — it never blocks a decomposition.")
                .font(BrandTypography.body)
                .foregroundStyle(BrandColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .toggleStyle(.switch)

          HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.md) {
            Text("Monthly cap $")
              .font(BrandTypography.callout.weight(.semibold))
              .foregroundStyle(monthlyCostCapEnabled ? BrandColors.textPrimary : BrandColors.textSecondary)

            TextField("25.00", value: monthlyCostCapBinding, format: .number.precision(.fractionLength(2)))
              .textFieldStyle(.roundedBorder)
              .frame(width: 120)
              .monospacedDigit()
              .disabled(!monthlyCostCapEnabled)
              .accessibilityLabel("Monthly cap in estimated dollars")

            Spacer(minLength: BrandMetrics.Spacing.md)
          }

          monthlyCostCapReadout
        }
      }
    }
  }

  private var thresholdHelperText: Text {
    var text = AttributedString("Modules at or above this auto-accept into your toolbox; below it they go to Approval for you to review.")
    if let range = text.range(of: "auto-accept") {
      text[range].inlinePresentationIntent = .stronglyEmphasized
    }
    if let range = text.range(of: "Approval") {
      text[range].inlinePresentationIntent = .stronglyEmphasized
    }
    return Text(text)
  }

  private var thresholdSlider: some View {
    BrandThresholdSlider(
      value: confidenceThresholdBinding,
      range: 0.5...1,
      step: 0.05,
      leadingLabel: "APPROVAL",
      trailingLabel: "AUTO-ACCEPT",
      bubbleText: confidencePercentText,
      showsBubble: showsConfidenceThresholdBubble,
      onEditingChanged: { editing in
        isAdjustingConfidenceThreshold = editing
      }
    )
    .accessibilityLabel("Approval to auto-accept threshold")
    .accessibilityValue(confidencePercentText)
  }

  private var monthlyCostCapReadout: some View {
    let projection = currentSpendProjection
    let isOverCap = monthlyCostCapEnabled && monthlyCostCapUSD > 0 && projection.estimatedUSD > monthlyCostCapUSD
    let color = isOverCap ? BrandColors.warning : BrandColors.textSecondary
    let icon = isOverCap ? "exclamationmark.triangle" : "chart.bar.doc.horizontal"

    return VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.sm) {
        Image(systemName: icon)
          .font(BrandTypography.callout)
          .foregroundStyle(color)

        Text("Projected this month: \(Self.formatEstimatedUSD(projection.estimatedUSD)) ESTIMATED")
          .font(BrandTypography.callout.weight(.semibold))
          .foregroundStyle(isOverCap ? BrandColors.warning : BrandColors.textPrimary)
          .monospacedDigit()
      }

      Text(monthlyCostCapProjectionCopy(projection: projection, isOverCap: isOverCap))
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(BrandMetrics.Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(isOverCap ? BrandColors.warning.opacity(BrandMetrics.Control.tintedFillOpacity) : BrandColors.backgroundSecondary)
    )
    .overlay(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .strokeBorder(isOverCap ? BrandColors.warning.opacity(0.55) : .clear)
    )
    .accessibilityLabel(monthlyCostCapAccessibilityLabel(projection: projection, isOverCap: isOverCap))
  }

  private var pipelineHealthSection: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
      sectionHeader(
        "Everything that has to be true for your agent to call your toolbox.",
        description: "MCP setup and the existing app status checks live here."
      )

      if arrivedFromMCP {
        arrivalBanner
      }

      settingsPanel {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
          if let statusSnapshot {
            statusRow(statusSnapshot.configuration)
            statusRow(statusSnapshot.apiKey)
            statusRow(statusSnapshot.localModel)
            statusRow(statusSnapshot.store)
            statusRow(statusSnapshot.engine)
          }

          mcpServerRow
            .id("mcp-server-row")

          Button("Refresh status") {
            refreshStatus()
          }
          .buttonStyle(.brandSecondary)
          .padding(.top, BrandMetrics.Spacing.xs)
        }
      }

      settingsPanel {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
          Text("Connect your agent over MCP")
            .font(BrandTypography.headline)
            .foregroundStyle(BrandColors.textPrimary)

          Text("These toggles update the same MCP configuration status read by the sidebar chip and setup sheet.")
            .font(BrandTypography.body)
            .foregroundStyle(BrandColors.textSecondary)

          VStack(spacing: BrandMetrics.Spacing.sm) {
            ForEach(mcpSetup.rows) { row in
              mcpClientRow(row)
            }
          }

          mcpConfigSnippet
        }
      }
    }
  }

  private var arrivalBanner: some View {
    HStack(alignment: .top, spacing: BrandMetrics.Spacing.sm) {
      Image(systemName: "arrow.turn.down.right")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.warning)

      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        Text("Arrived from \"MCP not set up\"")
          .font(BrandTypography.callout.weight(.semibold))
          .foregroundStyle(BrandColors.textPrimary)
        Text("The MCP server row is highlighted below.")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
      }
    }
    .padding(BrandMetrics.Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(BrandColors.warning.opacity(BrandMetrics.Control.tintedFillOpacity))
    )
  }

  private var mcpServerRow: some View {
    let item = SettingsStatusItem(
      title: "MCP server",
      value: mcpSetup.isAnyClientConnected ? "Connected" : "Not set up",
      message: mcpSetup.isAnyClientConnected
        ? "At least one agent client can see gunk."
        : "Your capabilities are verified, but nothing is exposing them to an agent yet.",
      state: mcpSetup.isAnyClientConnected ? .ready : .needsSetup
    )

    return statusRow(item, isHighlighted: arrivedFromMCP && !mcpSetup.isAnyClientConnected)
  }

  private var mcpConfigSnippet: some View {
    let installPath = MCPBinary.installURL().path
    let snippet = """
    {
      "mcpServers": {
        "gunk": {
          "command": "\(installPath)",
          "args": []
        }
      }
    }
    """

    return VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      Text("Claude Desktop example")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.textSecondary)
      Text(snippet)
        .font(BrandTypography.mono)
        .foregroundStyle(BrandColors.textSecondary)
        .textSelection(.enabled)
        .padding(BrandMetrics.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: BrandMetrics.Radius.small, style: .continuous)
            .fill(BrandColors.backgroundSecondary)
        )
    }
  }

  private func sectionHeader(_ title: String, description: String) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      Text(selectedSection.title)
        .font(BrandTypography.title)
        .foregroundStyle(BrandColors.textPrimary)

      Text(title)
        .font(BrandTypography.headline)
        .foregroundStyle(BrandColors.textPrimary)

      Text(description)
        .font(BrandTypography.body)
        .foregroundStyle(BrandColors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func settingsPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
      .padding(BrandMetrics.Spacing.lg)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
          .fill(BrandColors.backgroundElevated)
      )
  }

  // MARK: MCP clients (T-8.10)

  private func mcpClientRow(_ row: MCPSetupModel.ClientRow) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(alignment: .center, spacing: BrandMetrics.Spacing.md) {
        VStack(alignment: .leading, spacing: 3) {
          Text(row.client.displayName)
            .font(BrandTypography.callout)
            .foregroundStyle(BrandColors.textPrimary)

          Text(shortenedConfigPath(row.configURL))
            .font(BrandTypography.mono)
            .foregroundStyle(BrandColors.textSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
        }

        Spacer(minLength: BrandMetrics.Spacing.lg)

        Text(row.displayStatus.label)
          .font(BrandTypography.caption.weight(.semibold))
          .foregroundStyle(mcpStatusColor(row.displayStatus))

        Toggle("", isOn: mcpToggleBinding(for: row))
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
          .tint(BrandColors.accentSecondary)
      }

      if let problem = mcpProblemMessage(for: row) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(problem)
            .font(BrandTypography.caption)
            .foregroundStyle(BrandColors.danger)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)

          Button("Open config") {
            openConfig(row.configURL)
          }
          .font(.caption2)
        }
      }
    }
    .padding(BrandMetrics.Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(BrandColors.backgroundSecondary)
    )
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
      // The green toggle already signals the active state; keep the label
      // muted rather than a loud success green.
      return BrandColors.textSecondary
    case .notSetUp:
      return BrandColors.warning
    case .notDetected:
      return BrandColors.textTertiary
    case .problem:
      return BrandColors.danger
    }
  }

  /// Collapses the user's home directory to `~` so long config paths fit on a
  /// single line without leaning on truncation.
  private func shortenedConfigPath(_ url: URL) -> String {
    (url.path as NSString).abbreviatingWithTildeInPath
  }

  private func statusRow(_ item: SettingsStatusItem, isHighlighted: Bool = false) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: item.state.systemImage)
        .foregroundStyle(item.state.color)
        .frame(width: 16)

      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline) {
          Text(item.title)
            .font(BrandTypography.callout)
            .foregroundStyle(BrandColors.textPrimary)
          Spacer(minLength: 8)
          Text(item.state.rawValue)
            .font(BrandTypography.caption.weight(.semibold))
            .foregroundStyle(item.state.color)
        }

        Text(item.value)
          .font(BrandTypography.mono)
          .foregroundStyle(BrandColors.textSecondary)
          .lineLimit(2)
          .truncationMode(.middle)
          .textSelection(.enabled)

        Text(item.message)
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(BrandMetrics.Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(isHighlighted ? BrandColors.warning.opacity(BrandMetrics.Control.tintedFillOpacity) : .clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .strokeBorder(isHighlighted ? BrandColors.warning.opacity(0.6) : .clear)
    )
  }

  private var selectedProvider: LLMProvider {
    LLMProvider(rawValue: providerRawValue) ?? .openAI
  }

  private var normalizedOllamaBaseURL: URL? {
    OllamaClient.normalizedBaseURL(from: ollamaBaseURLText)
  }

  private var ollamaHostDisplay: String {
    normalizedOllamaBaseURL?.absoluteString.replacingOccurrences(of: "http://", with: "") ?? ollamaBaseURLText
  }

  private var localModelBinding: Binding<String> {
    Binding(
      get: { ollamaModel },
      set: { value in
        ollamaModel = value
        if selectedProvider == .ollama {
          model = normalizedModel(value, provider: .ollama)
        }
      }
    )
  }

  private var useLocalModelBinding: Binding<Bool> {
    Binding(
      get: { selectedProvider == .ollama },
      set: { useLocal in
        if useLocal {
          activateLocalModel()
        } else if selectedProvider == .ollama {
          activateHostedProvider(.openAI)
          selectedSection = .localModel
        }
      }
    )
  }

  private var localModelCanBecomeActive: Bool {
    if case .reachable = localReachability {
      return true
    }
    return false
  }

  private var localToggleHelperText: String {
    if selectedProvider == .ollama {
      return "Ollama is the active engine for new decompositions."
    }
    if localModelCanBecomeActive {
      return "Makes Ollama the active engine instead of a hosted provider."
    }
    return "Available once a reachability check passes."
  }

  private var localReachabilityColor: Color {
    switch localReachability {
    case .reachable:
      return BrandColors.success
    case .unreachable:
      return BrandColors.danger
    case .unchecked, .checking:
      return BrandColors.textSecondary
    }
  }

  private var localReachabilityIcon: String {
    switch localReachability {
    case .unchecked:
      return "questionmark.circle"
    case .checking:
      return "arrow.clockwise"
    case .reachable:
      return "checkmark.circle"
    case .unreachable:
      return "xmark.circle"
    }
  }

  private var localReachabilityTitle: String {
    switch localReachability {
    case .unchecked:
      return "Not checked yet"
    case .checking:
      return "Checking \(ollamaHostDisplay)..."
    case .reachable:
      return "Ollama reachable"
    case .unreachable:
      return "Can't reach \(ollamaHostDisplay)"
    }
  }

  private var localReachabilityMessage: String {
    switch localReachability {
    case .unchecked:
      return "A reachability check is different from a hosted Test connection — there's no account or key to authenticate, gunk just confirms the local server answers."
    case .checking:
      return "Checking \(ollamaHostDisplay)... Asking Ollama for its loaded models."
    case .reachable(let model, let milliseconds):
      return "Ollama reachable. `\(model)` is loaded and answered in \(milliseconds) ms."
    case .unreachable(let message):
      return "\(message) Is Ollama running? Start it with `ollama serve`, then check again."
    }
  }

  private var localReachabilityButtonTitle: String {
    localReachability == .unchecked ? "Check reachability" : "Check again"
  }

  private var removeConfirmationBinding: Binding<Bool> {
    Binding(
      get: { removeCandidate != nil },
      set: { isPresented in
        if !isPresented {
          removeCandidate = nil
        }
      }
    )
  }

  private var firstProviderWithoutKey: LLMProvider? {
    Self.hostedProviders.first { !hasSavedKey($0) }
  }

  private func addProvider() {
    guard let provider = firstProviderWithoutKey else {
      return
    }
    beginEditing(provider)
  }

  private func activateHostedProvider(_ provider: LLMProvider) {
    let oldProvider = selectedProvider
    rememberModel(model, for: oldProvider)
    providerRawValue = provider.rawValue
    syncActiveModelFromMemory()
    providerBanner = ProviderBanner(
      variant: .success,
      title: "\(provider.rawValue) is active",
      message: "\(oldProvider.rawValue)'s remembered model was left untouched."
    )
    refreshStatus()
  }

  private func activateLocalModel() {
    guard localModelCanBecomeActive else {
      return
    }

    let oldProvider = selectedProvider
    rememberModel(model, for: oldProvider)
    rememberModel(ollamaModel, for: .ollama)
    providerRawValue = LLMProvider.ollama.rawValue
    syncActiveModelFromMemory()
    providerBanner = nil
    refreshStatus()
    refreshSpend()
  }

  private func resetLocalReachability() {
    guard localReachability != .checking else {
      return
    }
    localReachability = .unchecked
    refreshStatus()
  }

  private func checkLocalReachability() async {
    guard let baseURL = normalizedOllamaBaseURL else {
      localReachability = .unreachable("The host/base URL is not a valid URL.")
      refreshStatus()
      return
    }

    localReachability = .checking
    refreshStatus()
    let started = Date()
    let requestedModel = normalizedModel(ollamaModel, provider: .ollama)

    do {
      let loadedModels = try await checkOllamaReachability(baseURL)
      let elapsed = max(1, Int(Date().timeIntervalSince(started) * 1000))
      if loadedModels.contains(requestedModel) {
        localReachability = .reachable(model: requestedModel, milliseconds: elapsed)
      } else {
        let loaded = loadedModels.isEmpty ? "No models were reported as loaded." : "Loaded models: \(loadedModels.joined(separator: ", "))."
        localReachability = .unreachable("Ollama answered, but `\(requestedModel)` is not loaded. \(loaded)")
      }
    } catch {
      localReachability = .unreachable(shortReachabilityError(error))
    }

    refreshStatus()
  }

  private func beginEditing(_ provider: LLMProvider) {
    editingProvider = provider
    editingAPIKey = ""
    editingModel = modelForDisplay(provider)
    providerBanner = nil
  }

  private func cancelEditing() {
    editingProvider = nil
    editingAPIKey = ""
    editingModel = ""
  }

  private func saveProvider(_ provider: LLMProvider) {
    let trimmedKey = editingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let savedModel = normalizedModel(editingModel, provider: provider)

    do {
      if !trimmedKey.isEmpty {
        try secretStore.setSecret(trimmedKey, for: provider.secretAccount)
      }
      rememberModel(savedModel, for: provider)
      if selectedProvider == provider {
        model = savedModel
      }
      editingProvider = nil
      editingAPIKey = ""
      editingModel = ""
      providerTestStatuses[provider] = .idle
      providerBanner = ProviderBanner(
        variant: .success,
        title: "\(provider.rawValue) saved",
        message: "The key stays in Keychain and \(provider.rawValue)'s model is remembered separately."
      )
      refreshProviderKeyStates()
      refreshStatus()
      refreshSpend()
    } catch {
      providerBanner = ProviderBanner(
        variant: .failure,
        title: "\(provider.rawValue) was not saved",
        message: error.localizedDescription
      )
      refreshProviderKeyStates()
      refreshStatus()
    }
  }

  private func removeProviderKey(_ provider: LLMProvider) {
    do {
      try secretStore.setSecret(nil, for: provider.secretAccount)
      providerTestStatuses[provider] = .idle
      providerBanner = ProviderBanner(
        variant: .success,
        title: "\(provider.rawValue) key removed",
        message: "The Keychain slot was cleared. The remembered model stays available."
      )
      if editingProvider == provider {
        cancelEditing()
      }
    } catch {
      providerBanner = ProviderBanner(
        variant: .failure,
        title: "\(provider.rawValue) key was not removed",
        message: error.localizedDescription
      )
    }
    removeCandidate = nil
    refreshProviderKeyStates()
    refreshStatus()
    refreshSpend()
  }

  private func runConnectionTest(_ provider: LLMProvider) async {
    guard let apiKey = savedProviderKeys[provider]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !apiKey.isEmpty else {
      providerTestStatuses[provider] = .failure("No key saved")
      providerBanner = ProviderBanner(
        variant: .failure,
        title: "\(provider.rawValue) test failed",
        message: "Save a \(provider.rawValue) API key before testing the connection."
      )
      return
    }

    providerTestStatuses[provider] = .testing
    let started = Date()

    do {
      try await testConnection(provider, modelForDisplay(provider), apiKey)
      let elapsed = max(1, Int(Date().timeIntervalSince(started) * 1000))
      providerTestStatuses[provider] = .success(milliseconds: elapsed)
      providerBanner = nil
      refreshStatus()
    } catch {
      let message = shortTestError(error)
      providerTestStatuses[provider] = .failure(message)
      providerBanner = ProviderBanner(
        variant: .failure,
        title: "\(provider.rawValue) test failed",
        message: "The saved key didn't authenticate. Edit the key and test again; nothing else changed."
      )
      refreshStatus()
    }
  }

  private func refreshProviderKeyStates() {
    var keys: [LLMProvider: String] = [:]
    var errors: [LLMProvider: String] = [:]

    for provider in Self.hostedProviders {
      do {
        keys[provider] = try secretStore.secret(for: provider.secretAccount) ?? ""
      } catch {
        keys[provider] = ""
        errors[provider] = error.localizedDescription
      }
    }

    savedProviderKeys = keys
    keyReadErrors = errors
  }

  private func hasSavedKey(_ provider: LLMProvider) -> Bool {
    let key = savedProviderKeys[provider] ?? ""
    return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func maskedAPIKey(for provider: LLMProvider) -> String {
    let trimmed = (savedProviderKeys[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return "not saved"
    }

    return "••••••\(trimmed.suffix(4))"
  }

  private func testButtonTitle(_ provider: LLMProvider) -> String {
    providerTestStatuses[provider] == .testing ? "Testing..." : "Test connection"
  }

  private func shortTestError(_ error: Error) -> String {
    let message = error.localizedDescription
    if let status = message.range(of: #"HTTP\s+(\d+)"#, options: .regularExpression) {
      let code = message[status].replacingOccurrences(of: "HTTP ", with: "")
      return "\(code) · connection failed"
    }
    return message
  }

  private func shortReachabilityError(_ error: Error) -> String {
    if let urlError = error as? URLError {
      switch urlError.code {
      case .cannotConnectToHost, .networkConnectionLost, .timedOut, .notConnectedToInternet:
        return "No response."
      default:
        return urlError.localizedDescription
      }
    }
    return error.localizedDescription
  }

  private func migrateLegacyActiveModelIfNeeded() {
    let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return
    }

    let remembered = rememberedModel(for: selectedProvider)
    if remembered == selectedProvider.defaultModel && trimmed != selectedProvider.defaultModel {
      rememberModel(trimmed, for: selectedProvider)
    }
  }

  private func syncActiveModelFromMemory() {
    model = rememberedModel(for: selectedProvider)
  }

  private func rememberedModel(for provider: LLMProvider) -> String {
    switch provider {
    case .openAI:
      return normalizedModel(openAIModel, provider: provider)
    case .anthropic:
      return normalizedModel(anthropicModel, provider: provider)
    case .ollama:
      return normalizedModel(ollamaModel, provider: provider)
    }
  }

  private func rememberModel(_ value: String, for provider: LLMProvider) {
    let normalized = normalizedModel(value, provider: provider)
    switch provider {
    case .openAI:
      openAIModel = normalized
    case .anthropic:
      anthropicModel = normalized
    case .ollama:
      ollamaModel = normalized
    }
  }

  private func modelForDisplay(_ provider: LLMProvider) -> String {
    rememberedModel(for: provider)
  }

  private func normalizedModel(_ value: String, provider: LLMProvider) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? provider.defaultModel : trimmed
  }

  private var confidencePercentText: String {
    "\(Int((confidenceThreshold * 100).rounded()))%"
  }

  private var showsConfidenceThresholdBubble: Bool {
    isAdjustingConfidenceThreshold || showsStagedConfidenceDrag
  }

  private var confidenceThresholdBinding: Binding<Double> {
    Binding(
      get: {
        min(max(confidenceThreshold, 0.5), 1)
      },
      set: { newValue in
        confidenceThreshold = newValue
      }
    )
  }

  private var monthlyCostCapBinding: Binding<Double> {
    Binding(
      get: { monthlyCostCapUSD },
      set: { newValue in
        monthlyCostCapUSD = max(0, newValue)
      }
    )
  }

  private var currentSpendProjection: SpendModel.Projection {
    (spendModel ?? .fixtureEmpty).projectedMonthlySpend
  }

  private func monthlyCostCapProjectionCopy(
    projection: SpendModel.Projection,
    isOverCap: Bool
  ) -> String {
    let capCopy: String
    if monthlyCostCapEnabled, monthlyCostCapUSD > 0 {
      capCopy = isOverCap
        ? "This is over your \(Self.formatEstimatedUSD(monthlyCostCapUSD)) estimated monthly cap. The cap is warn-only; decompositions still run."
        : "This is under your \(Self.formatEstimatedUSD(monthlyCostCapUSD)) estimated monthly cap. The cap is warn-only; decompositions still run."
    } else if monthlyCostCapEnabled {
      capCopy = "Enter a cap above $0. The cap is warn-only; decompositions still run."
    } else {
      capCopy = "Off by default. Turn this on to show a warning when the estimate crosses your soft budget."
    }

    guard projection.hasUnknownPriceGaps else {
      return "\(capCopy) Based on estimated decomposition spend from the price table."
    }

    let noun = projection.unknownPriceRowCount == 1 ? "model" : "models"
    return "\(capCopy) Projection excludes \(projection.unknownPriceRowCount) \(noun) with no price on file."
  }

  private func monthlyCostCapAccessibilityLabel(
    projection: SpendModel.Projection,
    isOverCap: Bool
  ) -> String {
    let state = isOverCap ? "Over cap" : "Projected spend"
    return "\(state), \(Self.formatEstimatedUSD(projection.estimatedUSD)) estimated"
  }

  private static func formatEstimatedUSD(_ value: Double) -> String {
    String(format: "$%.2f", value)
  }

  private func refreshStatus() {
    statusSnapshot = SettingsStatusSnapshot.make(
      provider: selectedProvider,
      model: model,
      ollamaModel: normalizedModel(ollamaModel, provider: .ollama),
      ollamaReachability: localReachability,
      storePath: storePath,
      secretStore: secretStore,
      resolveEngine: resolveEngine
    )
    mcpSetup.refresh()
  }

  private func refreshSpend() {
    if let debugModel = Self.debugSpendModel() {
      spendModel = debugModel
      spendErrorMessage = nil
      return
    }

    do {
      spendModel = try loadSpendModel()
      spendErrorMessage = nil
    } catch {
      spendModel = nil
      spendErrorMessage = error.localizedDescription
    }
  }

  private func spendErrorPanel(_ message: String) -> some View {
    settingsPanel {
      HStack(alignment: .top, spacing: BrandMetrics.Spacing.sm) {
        Image(systemName: "exclamationmark.triangle")
          .font(BrandTypography.callout)
          .foregroundStyle(BrandColors.warning)

        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
          Text("Spend is unavailable")
            .font(BrandTypography.headline)
            .foregroundStyle(BrandColors.textPrimary)
          Text(message)
            .font(BrandTypography.caption)
            .foregroundStyle(BrandColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }

        Spacer(minLength: BrandMetrics.Spacing.md)

        Button("Retry") {
          refreshSpend()
        }
        .buttonStyle(.brandSecondary)
      }
    }
  }

  private func activateMCPDeepLink() {
    withAnimation(BrandMotion.standard) {
      selectedSection = .pipelineHealth
      arrivedFromMCP = true
    }
  }

  private func applySettingsDebugOverride() {
    if Self.debugSpendModel() != nil {
      selectedSection = .spend
      refreshSpend()
    }

    if let rawSection = ProcessInfo.processInfo.environment["GUNK_DEBUG_SETTINGS_SECTION"],
       let section = SettingsSection(rawValue: rawSection) {
      selectedSection = section
    }

    if ProcessInfo.processInfo.environment["GUNK_DEBUG_SETTINGS_MCP_DEEPLINK"] == "1" {
      activateMCPDeepLink()
    }

    applyProviderKeysDebugOverride()
    applyLocalModelDebugOverride()
    applyProcessingDebugOverride()
  }

  private func applyProviderKeysDebugOverride() {
    guard let fixture = ProcessInfo.processInfo.environment["GUNK_DEBUG_SETTINGS_PROVIDER_KEYS"] else {
      return
    }

    selectedSection = .providerKeys
    providerRawValue = LLMProvider.openAI.rawValue
    openAIModel = "gpt-4.1-mini"
    anthropicModel = "claude-sonnet-4-20250514"
    syncActiveModelFromMemory()
    refreshProviderKeyStates()

    switch fixture {
    case "edit":
      beginEditing(.openAI)
      editingAPIKey = "sk-proj-demo-replacement"
      editingModel = "gpt-4.1"
    case "test-ok":
      providerTestStatuses[.openAI] = .success(milliseconds: 420)
    case "test-failed":
      providerTestStatuses[.anthropic] = .failure("401 · invalid key")
      providerBanner = ProviderBanner(
        variant: .failure,
        title: "Anthropic test failed",
        message: "The saved key didn't authenticate. Edit the key and test again; nothing else changed."
      )
    case "remove":
      removeCandidate = .openAI
    default:
      break
    }
  }

  private static func debugSpendModel() -> SpendModel? {
    switch ProcessInfo.processInfo.environment["GUNK_DEBUG_SETTINGS_SPEND"] {
    case "populated":
      return .fixturePopulated
    case "unknown":
      return .fixtureUnknownPrice
    case "empty":
      return .fixtureEmpty
    case "local":
      return .fixtureLocal
    default:
      return nil
    }
  }

  static func debugProviderKeysSecretStore() -> SecretStore? {
    guard let fixture = ProcessInfo.processInfo.environment["GUNK_DEBUG_SETTINGS_PROVIDER_KEYS"] else {
      return nil
    }

    let store = InMemorySecretStore()
    switch fixture {
    case "empty":
      break
    case "test-failed":
      try? store.setSecret("sk-ant-invalid-demo", for: LLMProvider.anthropic.secretAccount)
      try? store.setSecret("sk-proj-openai-demo", for: LLMProvider.openAI.secretAccount)
    default:
      try? store.setSecret("sk-proj-openai-demo", for: LLMProvider.openAI.secretAccount)
      if fixture == "multi" || fixture == "test-ok" || fixture == "edit" || fixture == "remove" {
        try? store.setSecret("sk-ant-demo", for: LLMProvider.anthropic.secretAccount)
      }
    }
    return store
  }

  private func applyLocalModelDebugOverride() {
    guard let fixture = ProcessInfo.processInfo.environment["GUNK_DEBUG_SETTINGS_LOCAL_MODEL"] else {
      return
    }

    selectedSection = .localModel
    ollamaBaseURLText = "http://localhost:11434"
    ollamaModel = "llama3.1:8b"
    if fixture == "active" {
      providerRawValue = LLMProvider.ollama.rawValue
      syncActiveModelFromMemory()
    }

    switch fixture {
    case "checking":
      localReachability = .checking
    case "reachable", "active":
      localReachability = .reachable(model: "llama3.1:8b", milliseconds: 180)
    case "unreachable":
      localReachability = .unreachable("No response.")
    default:
      localReachability = .unchecked
    }
    focusedLocalModelField = nil
    DispatchQueue.main.async {
      focusedLocalModelField = nil
    }
    refreshStatus()
  }

  private func applyProcessingDebugOverride() {
    guard let fixture = ProcessInfo.processInfo.environment["GUNK_DEBUG_SETTINGS_PROCESSING"] else {
      return
    }

    selectedSection = .processing
    confidenceThreshold = 0.85
    showsStagedConfidenceDrag = fixture == "dragging"

    switch fixture {
    case "cap-off":
      monthlyCostCapEnabled = false
      monthlyCostCapUSD = 25
      spendModel = .fixturePopulated
    case "cap-under":
      monthlyCostCapEnabled = true
      monthlyCostCapUSD = 25
      spendModel = .fixturePopulated
    case "cap-exceeded":
      monthlyCostCapEnabled = true
      monthlyCostCapUSD = 5
      spendModel = .fixturePopulated
    case "cap-unknown":
      monthlyCostCapEnabled = true
      monthlyCostCapUSD = 25
      spendModel = .fixtureUnknownPrice
    default:
      break
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
      _ = try await OllamaClient(baseURL: OllamaClient.configuredBaseURL()).complete(request: request)
    }
  }

  private static func liveOllamaReachabilityCheck(baseURL: URL) async throws -> [String] {
    try await OllamaClient(baseURL: baseURL).listModels()
  }
}

private extension SettingsStatusItem.State {
  var color: Color {
    switch self {
    case .ready:
      return BrandColors.success
    case .needsSetup:
      return BrandColors.warning
    case .unavailable:
      return BrandColors.danger
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

/// Brand-themed range slider used by the Processing section's auto-accept
/// threshold. Replaces the native `Slider` (which renders in the system blue
/// accent and grows its own bounds when an overlay appears) with a fixed-height
/// green band: the value fill, the inline APPROVAL / AUTO-ACCEPT labels, the
/// handle, and the drag bubble all live inside a constant layout so adjusting
/// the value never nudges the surrounding settings rows.
private struct BrandThresholdSlider: View {
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double
  let leadingLabel: String
  let trailingLabel: String
  let bubbleText: String
  let showsBubble: Bool
  var onEditingChanged: (Bool) -> Void

  @State private var isDragging = false

  private let bandHeight: CGFloat = 36
  private let bubbleZoneHeight: CGFloat = 22
  private let bubbleSpacing: CGFloat = 6
  private let handleWidth: CGFloat = 12
  private let bandRadius: CGFloat = BrandMetrics.Radius.medium

  private var totalHeight: CGFloat { bubbleZoneHeight + bubbleSpacing + bandHeight }

  private var fraction: CGFloat {
    let span = range.upperBound - range.lowerBound
    guard span > 0 else { return 0 }
    return CGFloat((value - range.lowerBound) / span)
  }

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let travel = max(width - handleWidth, 1)
      let handleCenterX = handleWidth / 2 + fraction * travel

      VStack(spacing: bubbleSpacing) {
        bubbleZone(handleCenterX: handleCenterX, width: width)
        band(handleCenterX: handleCenterX)
      }
      .contentShape(Rectangle())
      .gesture(dragGesture(width: width, travel: travel))
    }
    .frame(height: totalHeight)
    .animation(BrandMotion.standard, value: showsBubble)
    .animation(BrandMotion.standard, value: isDragging)
  }

  private func bubbleZone(handleCenterX: CGFloat, width: CGFloat) -> some View {
    let bubbleWidth: CGFloat = 46
    let clampedX = min(max(handleCenterX - bubbleWidth / 2, 0), max(0, width - bubbleWidth))

    return ZStack(alignment: .topLeading) {
      Color.clear
      Text(bubbleText)
        .font(BrandTypography.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(BrandColors.backgroundPrimary)
        .frame(width: bubbleWidth)
        .padding(.vertical, BrandMetrics.Spacing.xs)
        .background(
          Capsule(style: .continuous)
            .fill(BrandColors.accent)
        )
        .offset(x: clampedX)
        .opacity(showsBubble ? 1 : 0)
        .scaleEffect(showsBubble ? 1 : 0.9, anchor: .bottom)
    }
    .frame(height: bubbleZoneHeight)
  }

  private func band(handleCenterX: CGFloat) -> some View {
    ZStack(alignment: .leading) {
      RoundedRectangle(cornerRadius: bandRadius, style: .continuous)
        .fill(BrandColors.backgroundPrimary)

      Rectangle()
        .fill(
          LinearGradient(
            colors: [BrandColors.accentSecondary, BrandColors.accent],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .frame(width: handleCenterX)

      // Muted text for the un-filled groove, then dark text masked to the
      // filled region so each label stays legible against its background.
      labelRow
        .foregroundStyle(BrandColors.textSecondary)

      labelRow
        .foregroundStyle(BrandColors.backgroundPrimary)
        .mask(alignment: .leading) {
          Rectangle().frame(width: handleCenterX)
        }

      handle
        .position(x: handleCenterX, y: bandHeight / 2)
    }
    .frame(height: bandHeight)
    .clipShape(RoundedRectangle(cornerRadius: bandRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: bandRadius, style: .continuous)
        .strokeBorder(BrandColors.accent.opacity(0.22))
    )
  }

  private var labelRow: some View {
    HStack {
      Text(leadingLabel)
      Spacer(minLength: BrandMetrics.Spacing.sm)
      Text(trailingLabel)
    }
    .font(BrandTypography.caption.weight(.semibold))
    .padding(.horizontal, BrandMetrics.Spacing.md)
    .frame(maxWidth: .infinity)
  }

  private var handle: some View {
    RoundedRectangle(cornerRadius: handleWidth / 2, style: .continuous)
      .fill(
        LinearGradient(
          colors: [BrandColors.Mark.gradientTop, BrandColors.accent],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .overlay(
        RoundedRectangle(cornerRadius: handleWidth / 2, style: .continuous)
          .strokeBorder(BrandColors.backgroundPrimary.opacity(0.35))
      )
      .frame(width: handleWidth, height: bandHeight - 8)
      .scaleEffect(isDragging ? 1.08 : 1, anchor: .center)
      .shadow(color: BrandColors.scrim.opacity(0.35), radius: 3, y: 1)
  }

  private func dragGesture(width: CGFloat, travel: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { drag in
        if !isDragging {
          isDragging = true
          onEditingChanged(true)
        }
        updateValue(locationX: drag.location.x, travel: travel)
      }
      .onEnded { drag in
        updateValue(locationX: drag.location.x, travel: travel)
        isDragging = false
        onEditingChanged(false)
      }
  }

  private func updateValue(locationX: CGFloat, travel: CGFloat) {
    let rawFraction = (locationX - handleWidth / 2) / travel
    let clamped = min(max(Double(rawFraction), 0), 1)
    let span = range.upperBound - range.lowerBound
    let stepped = (clamped * span / step).rounded() * step + range.lowerBound
    value = min(max(stepped, range.lowerBound), range.upperBound)
  }
}
