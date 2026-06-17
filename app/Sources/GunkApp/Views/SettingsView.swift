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

@MainActor
struct SettingsView: View {
  @AppStorage("llm.provider") private var providerRawValue = LLMProvider.openAI.rawValue
  @AppStorage("llm.model") private var model = LLMProvider.openAI.defaultModel
  @AppStorage("llm.confidenceThreshold") private var confidenceThreshold = 0.7

  @State private var selectedSection: SettingsSection
  @State private var apiKey: String
  @State private var statusSnapshot: SettingsStatusSnapshot?
  @State private var statusMessage: String?
  @State private var isTestingConnection = false
  @State private var arrivedFromMCP = false

  /// Shared with the shell's chip and the setup sheet (T-8.10): one
  /// `MCPClientConfigurator` source, so a toggle here re-checks everywhere.
  @ObservedObject private var mcpSetup: MCPSetupModel

  private let mcpDeepLinkNonce: Int
  private let mcpDeepLinkOnAppear: Bool
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
    initialSection: SettingsSection = .providerKeys,
    mcpDeepLinkNonce: Int = 0,
    mcpDeepLinkOnAppear: Bool = false,
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
    self._selectedSection = State(initialValue: initialSection)
    self._apiKey = State(initialValue: apiKey)
    self.mcpDeepLinkNonce = mcpDeepLinkNonce
    self.mcpDeepLinkOnAppear = mcpDeepLinkOnAppear
    self.secretStore = secretStore
    self.testConnection = testConnection
    self.storePath = storePath
    self.resolveEngine = resolveEngine
    self.mcpSetup = mcpSetup ?? MCPSetupModel()
    self.openConfig = openConfig
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
      loadSecret(for: selectedProvider)
      refreshStatus()
      applySettingsDebugOverride()
      if mcpDeepLinkOnAppear {
        activateMCPDeepLink()
      }
    }
    .onChange(of: model) {
      refreshStatus()
    }
    .onChange(of: mcpDeepLinkNonce) {
      activateMCPDeepLink()
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

      settingsPanel {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
          HStack(spacing: BrandMetrics.Spacing.sm) {
            Image(systemName: "arrow.right")
              .font(BrandTypography.callout)
              .foregroundStyle(BrandColors.textSecondary)
            Text("Active provider for new decompositions")
              .font(BrandTypography.headline)
              .foregroundStyle(BrandColors.textPrimary)
          }

          Picker("Provider", selection: providerBinding) {
            ForEach(LLMProvider.allCases) { provider in
              Text(provider.rawValue).tag(provider)
            }
          }
          .pickerStyle(.segmented)

          Text("Decompositions will run on \(selectedProvider.rawValue) `\(modelForDisplay)`.")
            .font(BrandTypography.caption)
            .foregroundStyle(BrandColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      settingsPanel {
        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .center, spacing: BrandMetrics.Spacing.sm) {
            Text("Saved provider")
              .font(BrandTypography.callout)
              .foregroundStyle(BrandColors.textSecondary)

            Spacer(minLength: BrandMetrics.Spacing.md)

            StatusBadge("Active", variant: .success)
          }
          .padding(.bottom, BrandMetrics.Spacing.md)

          Divider()
            .background(BrandColors.separator)
            .padding(.horizontal, -BrandMetrics.Spacing.lg)

          VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
            HStack(alignment: .top, spacing: BrandMetrics.Spacing.md) {
              ProviderMark(provider: selectedProvider.rawValue, size: 22)

              VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
                HStack(spacing: BrandMetrics.Spacing.sm) {
                  Text(selectedProvider.rawValue)
                    .font(BrandTypography.headline)
                    .foregroundStyle(BrandColors.textPrimary)

                  keyStateBadge
                }

                HStack(spacing: BrandMetrics.Spacing.md) {
                  Text("MODEL \(modelForDisplay)")
                  if selectedProvider != .ollama {
                    Text("KEY \(maskedAPIKey)")
                  }
                }
                .font(BrandTypography.mono)
                .foregroundStyle(BrandColors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
              }

              Spacer(minLength: BrandMetrics.Spacing.md)

              Button(isTestingConnection ? "Testing..." : "Test connection") {
                Task {
                  await runConnectionTest()
                }
            }
            .buttonStyle(.brandSecondary)
            .disabled(isTestingConnection)
          }

            VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
              Text("Model")
                .font(BrandTypography.callout)
                .foregroundStyle(BrandColors.textSecondary)
              TextField("Model", text: $model)
                .textFieldStyle(.roundedBorder)
            }

            if selectedProvider != .ollama {
              VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
                Text("API key")
                  .font(BrandTypography.callout)
                  .foregroundStyle(BrandColors.textSecondary)
                SecureField("API key", text: $apiKey)
                  .textFieldStyle(.roundedBorder)
              }
            } else {
              StatusBadge("Runs locally · no key", variant: .neutral, systemImage: "desktopcomputer")
            }

            HStack(spacing: BrandMetrics.Spacing.sm) {
              Image(systemName: "lock")
                .font(BrandTypography.caption)
                .foregroundStyle(BrandColors.textTertiary)
              Text("Saved to your system Keychain, never to gunk's database.")
                .font(BrandTypography.caption)
                .foregroundStyle(BrandColors.textSecondary)

              Spacer(minLength: BrandMetrics.Spacing.md)

              Button("Save") {
                save()
              }
              .buttonStyle(.brandPrimary)

              if let statusMessage {
                Text(statusMessage)
                  .font(BrandTypography.caption)
                  .foregroundStyle(BrandColors.textSecondary)
              }
            }
          }
          .padding(.top, BrandMetrics.Spacing.md)
        }
      }

      Text("Keys are read from your macOS Keychain at call time. gunk's database stores only which provider is active and the chosen model.")
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var localModelSection: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
      sectionHeader(
        "Run decompositions on a model you host with Ollama.",
        description: "No hosted call, no key, nothing leaves your machine."
      )

      settingsPanel {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
          HStack(spacing: BrandMetrics.Spacing.sm) {
            StatusBadge("Runs locally · no key", variant: .neutral, systemImage: "desktopcomputer")
            if selectedProvider == .ollama {
              StatusBadge("Active", variant: .success, systemImage: "checkmark.circle")
            }
          }

          Text("Ollama currently uses the provider picker and model field in Provider & keys. Host, reachability, and loaded-model controls land in the Local model task.")
            .font(BrandTypography.body)
            .foregroundStyle(BrandColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

          Button("Open Provider & keys") {
            withAnimation(BrandMotion.standard) {
              selectedSection = .providerKeys
            }
          }
          .buttonStyle(.brandSecondary)
        }
      }
    }
  }

  private var spendSection: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
      sectionHeader(
        "What decompositions have cost you.",
        description: "Estimated from real token usage."
      )

      settingsPanel {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
          Text("Spend")
            .font(BrandTypography.headline)
            .foregroundStyle(BrandColors.textPrimary)

          Text("The token and estimated-cost readout will appear here after the spend UI task. No dollar figure is shown until it can be estimated from real stored tokens.")
            .font(BrandTypography.body)
            .foregroundStyle(BrandColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var processingSection: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
      sectionHeader(
        "How extracted capabilities move into your toolbox.",
        description: "This keeps the existing confidence setting in the new Processing section."
      )

      settingsPanel {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
          HStack(alignment: .firstTextBaseline) {
            Text("Confidence threshold")
              .font(BrandTypography.headline)
              .foregroundStyle(BrandColors.textPrimary)
            Spacer(minLength: BrandMetrics.Spacing.md)
            Text(confidenceThreshold.formatted(.number.precision(.fractionLength(2))))
              .font(BrandTypography.mono)
              .foregroundStyle(BrandColors.textSecondary)
          }

          Slider(value: $confidenceThreshold, in: 0...1, step: 0.05)

          HStack {
            Text("Approval")
            Spacer()
            Text("Auto-accept")
          }
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
        }
      }
    }
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
      Toggle(isOn: mcpToggleBinding(for: row)) {
        VStack(alignment: .leading, spacing: 3) {
          HStack(alignment: .firstTextBaseline) {
            Text(row.client.displayName)
              .font(BrandTypography.callout)
              .foregroundStyle(BrandColors.textPrimary)
            Spacer(minLength: 8)
            Text(row.displayStatus.label)
              .font(BrandTypography.caption.weight(.semibold))
              .foregroundStyle(mcpStatusColor(row.displayStatus))
          }

          Text(row.configURL.path)
            .font(BrandTypography.mono)
            .foregroundStyle(BrandColors.textSecondary)
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
      return BrandColors.success
    case .notSetUp:
      return BrandColors.warning
    case .notDetected:
      return BrandColors.textTertiary
    case .problem:
      return BrandColors.danger
    }
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

  private var modelForDisplay: String {
    let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? selectedProvider.defaultModel : trimmed
  }

  private var maskedAPIKey: String {
    if selectedProvider == .ollama {
      return "not required"
    }

    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return "not saved"
    }

    let suffix = String(trimmed.suffix(4))
    return "••••••\(suffix)"
  }

  @ViewBuilder
  private var keyStateBadge: some View {
    if selectedProvider == .ollama {
      StatusBadge("No key", variant: .neutral)
    } else if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      StatusBadge("No key", variant: .warning)
    } else {
      StatusBadge("Key saved", variant: .success)
    }
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

  private func activateMCPDeepLink() {
    withAnimation(BrandMotion.standard) {
      selectedSection = .pipelineHealth
      arrivedFromMCP = true
    }
  }

  private func applySettingsDebugOverride() {
    if let rawSection = ProcessInfo.processInfo.environment["GUNK_DEBUG_SETTINGS_SECTION"],
       let section = SettingsSection(rawValue: rawSection) {
      selectedSection = section
    }

    if ProcessInfo.processInfo.environment["GUNK_DEBUG_SETTINGS_MCP_DEEPLINK"] == "1" {
      activateMCPDeepLink()
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
