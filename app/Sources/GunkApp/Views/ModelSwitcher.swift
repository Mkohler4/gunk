import SwiftUI

/// One selectable model in the switcher menu.
struct ModelOption: Equatable, Identifiable {
  let provider: LLMProvider
  let modelId: String
  let displayName: String
  let subtitle: String

  var id: String {
    "\(provider.rawValue)/\(modelId)"
  }

  /// Selection identity (T-8.8): an option is the selected one only when
  /// *both* halves of the storage contract agree — `llm.provider` and
  /// `llm.model`. The same model id under another provider is a different
  /// option.
  func matches(provider: LLMProvider, modelId: String) -> Bool {
    self.provider == provider && self.modelId == modelId
  }
}

/// The model catalog behind the shell's model switcher (toolbox-v2
/// `.model-menu`). Hosted providers offer a curated catalog once their API
/// key is saved; the local provider (Ollama) is always available and offers
/// whatever model Settings has configured. Selecting any of them from the
/// switcher activates that engine directly — no separate Settings toggle.
enum ModelCatalog {
  /// Hosted providers the switcher can offer, in mockup order. A provider's
  /// models only appear once its key exists in the Keychain.
  static let hostedProviders: [LLMProvider] = [.anthropic, .openAI]

  /// Local providers the switcher always offers — they need no key and run
  /// on the user's machine, so they're listed unconditionally (after the
  /// keyed hosted providers). Ollama appears with whatever model Settings
  /// has saved, which is what lets it be picked straight from the dropdown.
  static let localProviders: [LLMProvider] = [.ollama]

  static func options(for provider: LLMProvider) -> [ModelOption] {
    switch provider {
    case .anthropic:
      return [
        ModelOption(
          provider: .anthropic,
          modelId: "claude-sonnet-4-20250514",
          displayName: "Claude Sonnet 4",
          subtitle: "Balanced · default"
        ),
        ModelOption(
          provider: .anthropic,
          modelId: "claude-opus-4-20250514",
          displayName: "Claude Opus 4",
          subtitle: "Deepest reasoning"
        ),
      ]
    case .openAI:
      return [
        ModelOption(
          provider: .openAI,
          modelId: "gpt-4.1-mini",
          displayName: "GPT-4.1 Mini",
          subtitle: "Balanced · default"
        ),
        ModelOption(
          provider: .openAI,
          modelId: "gpt-4.1",
          displayName: "GPT-4.1",
          subtitle: "Most capable"
        ),
        ModelOption(
          provider: .openAI,
          modelId: "gpt-4.1-nano",
          displayName: "GPT-4.1 Nano",
          subtitle: "Fastest & cheapest"
        ),
      ]
    case .ollama:
      // Ollama has no curated catalog — the model is whatever the user
      // pulled and typed into Settings' Local model section. Its single
      // switcher row is derived from the saved model in `menuOptions`.
      return []
    }
  }

  /// Display form of a raw model id for models outside the catalog, e.g.
  /// `claude-sonnet-4-20250514` → "Claude Sonnet 4", `gpt-4.1-mini` →
  /// "GPT 4.1 Mini".
  static func displayName(for modelId: String) -> String {
    if let option = (hostedProviders + [.ollama])
      .flatMap(options(for:))
      .first(where: { $0.modelId == modelId }) {
      return option.displayName
    }

    var name = modelId
    if let snapshotSuffix = name.range(of: #"-\d{8}$"#, options: .regularExpression) {
      name.removeSubrange(snapshotSuffix)
    }
    return name.split(separator: "-")
      .map { $0.lowercased() == "gpt" ? "GPT" : String($0).capitalized }
      .joined(separator: " ")
  }

  // MARK: Menu derivation (T-8.8 close-out: pure, so it's testable)

  /// Subtitle on the off-catalog row — the switcher never hides what
  /// Settings actually has configured.
  static let customOptionSubtitle = "Custom · from Settings"

  /// Subtitle on the local-provider row: no key, runs on your machine.
  static let localOptionSubtitle = "Local · runs on your machine"

  /// The hosted providers whose key probe succeeds, in mockup order.
  /// Unkeyed hosted providers are absent — they only appear once a key is
  /// saved in Settings.
  static func keyedProviders(hasKey: (LLMProvider) -> Bool) -> [LLMProvider] {
    hostedProviders.filter(hasKey)
  }

  /// Every provider the open switcher sections by: keyed hosted providers
  /// (mockup order) followed by the always-available local providers. This
  /// is what lets Ollama be picked straight from the dropdown — selecting it
  /// activates the local engine, no Settings toggle required, so the user
  /// can switch seamlessly between every configured model.
  static func switcherProviders(hasKey: (LLMProvider) -> Bool) -> [LLMProvider] {
    keyedProviders(hasKey: hasKey) + localProviders
  }

  /// One provider section's rows: the curated catalog, plus the saved
  /// model as an extra row exactly when that model is off-catalog, non-empty,
  /// and saved under this provider. For local providers (Ollama) the catalog
  /// is empty, so this saved-model row is the section's only entry and it
  /// carries the "Local · runs on your machine" subtitle instead of the
  /// hosted "Custom · from Settings" one.
  static func menuOptions(
    for provider: LLMProvider,
    selectedProvider: LLMProvider,
    selectedModelId: String,
    rememberedModelId: String? = nil
  ) -> [ModelOption] {
    var options = options(for: provider)
    let providerModelId = rememberedModelId ?? (provider == selectedProvider ? selectedModelId : "")

    if !options.contains(where: { $0.modelId == providerModelId }),
       !providerModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      options.append(
        ModelOption(
          provider: provider,
          modelId: providerModelId,
          displayName: displayName(for: providerModelId),
          subtitle: localProviders.contains(provider) ? localOptionSubtitle : customOptionSubtitle
        )
      )
    }

    return options
  }
}

/// The shell-chrome model switcher (T-8.8, brought forward): the trailing
/// `provider · model ⌄` readout is now a working menu. It reads and writes
/// the exact same storage as Settings (`llm.provider` / `llm.model`) and
/// never duplicates key entry — only providers whose API key is already
/// saved in the Keychain offer their models; "Model settings…" routes to
/// Settings for everything else.
struct ModelSwitcher: View {
  /// Same storage Settings writes — the readout and the configured
  /// extraction model can never disagree.
  @AppStorage("llm.provider") private var providerRawValue = LLMProvider.openAI.rawValue
  @AppStorage("llm.model") private var model = LLMProvider.openAI.defaultModel
  @AppStorage(LLMProvider.openAI.modelStorageKey) private var openAIModel = LLMProvider.openAI.defaultModel
  @AppStorage(LLMProvider.anthropic.modelStorageKey) private var anthropicModel = LLMProvider.anthropic.defaultModel
  @AppStorage(LLMProvider.ollama.modelStorageKey) private var ollamaModel = LLMProvider.ollama.defaultModel

  var secretStore: SecretStore = KeychainStore()
  var onShowSettings: () -> Void = {}

  @State private var isMenuPresented = false
  /// Providers the menu sections by — keyed hosted providers plus the
  /// always-available local provider (Ollama). Refreshed every time the
  /// menu opens so a key saved in Settings shows up without relaunching.
  @State private var menuProviders: [LLMProvider] = []

  /// Mockup `.model-menu { width: 248px }`.
  private static let menuWidth: CGFloat = 248

  var body: some View {
    Button {
      refreshMenuProviders()
      isMenuPresented.toggle()
    } label: {
      switcherLabel
    }
    .buttonStyle(.plain)
    .help(switcherHelp)
    .accessibilityLabel("Extraction model: \(providerRawValue), \(modelDisplayName)")
    .onAppear {
      refreshMenuProviders()
      // Dev-only screenshot hook, like GUNK_DESIGN_GALLERY: opens the menu
      // at launch so the open state can be captured scripted.
      if ProcessInfo.processInfo.environment["GUNK_DEBUG_MODEL_MENU"] == "1" {
        isMenuPresented = true
      }
    }
    .popover(isPresented: $isMenuPresented, arrowEdge: .bottom) {
      menu
    }
  }

  // MARK: Trailing label (mockup `.model`)

  private var switcherLabel: some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      Text(providerRawValue)
        .foregroundStyle(BrandColors.textSecondary)
        // Incompressible like the model-name slot below: under width
        // pressure the appbar must fall back to its two-row stack, not
        // quietly eat the provider name.
        .fixedSize()
      Text("·")
        .foregroundStyle(BrandColors.textTertiary)
        .fixedSize()
      Text(modelDisplayName)
        .foregroundStyle(BrandColors.textPrimary)
        // T-8.8 close-out: the name lives in a fixed-width slot and
        // middle-truncates past it (an id's head and tail are its
        // distinguishing parts) — switching models can never resize the
        // appbar or push the search field around, and the slot stays
        // incompressible so the 960pt fallback to the two-row stack
        // triggers instead of squeezing the name.
        .truncationMode(.middle)
        .frame(width: BrandMetrics.Control.modelLabelWidth, alignment: .leading)

      // T-8.8: the selected provider is missing its key — the switcher
      // carries a quiet warning dot and Settings is the way out.
      if selectedProviderNeedsKey {
        Circle()
          .fill(BrandColors.warning)
          .frame(width: BrandMetrics.Spacing.xs + 2, height: BrandMetrics.Spacing.xs + 2)
          .accessibilityLabel("API key missing for \(providerRawValue)")
      }

      Image(systemName: "chevron.down")
        .font(BrandTypography.caption.weight(.semibold))
        .foregroundStyle(BrandColors.textSecondary)
    }
    .font(BrandTypography.callout.weight(.medium))
    .lineLimit(1)
    .padding(.horizontal, BrandMetrics.Spacing.md)
    .padding(.vertical, BrandMetrics.Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(BrandColors.textPrimary.opacity(BrandMetrics.Control.hoverHighlightOpacity / 2))
    )
    .overlay(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .strokeBorder(BrandColors.separator)
    )
    .contentShape(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
    )
  }

  private var switcherHelp: String {
    selectedProviderNeedsKey
      ? "No \(providerRawValue) API key saved — add one in Settings"
      : "Switch the extraction model"
  }

  // MARK: Menu (mockup `.model-menu`)

  private var menu: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs / 2) {
      ForEach(menuProviders) { provider in
        providerSection(provider)
      }

      Divider()
        .padding(.vertical, BrandMetrics.Spacing.xs)

      settingsRow
    }
    .padding(BrandMetrics.Spacing.sm - 2)
    .frame(width: Self.menuWidth)
  }

  @ViewBuilder
  private func providerSection(_ provider: LLMProvider) -> some View {
    // Mockup `.mm-group`: small uppercase faint section header.
    Text(provider.rawValue.uppercased())
      .font(BrandTypography.caption.weight(.semibold))
      .kerning(0.5)
      .foregroundStyle(BrandColors.textTertiary)
      .padding(.horizontal, BrandMetrics.Spacing.sm + 2)
      .padding(.top, BrandMetrics.Spacing.sm)
      .padding(.bottom, BrandMetrics.Spacing.xs / 2)

    ForEach(menuOptions(for: provider)) { option in
      ModelMenuRow(
        title: option.displayName,
        subtitle: option.subtitle,
        isSelected: isSelected(option)
      ) {
        select(option)
      }
    }
  }

  private var settingsRow: some View {
    ModelMenuRow(
      title: "Model settings…",
      subtitle: nil,
      isSelected: false
    ) {
      isMenuPresented = false
      onShowSettings()
    }
    .accessibilityLabel("Open model settings")
  }

  /// The provider's curated catalog plus the off-catalog custom row —
  /// derivation lives in `ModelCatalog.menuOptions` (pure, under test).
  private func menuOptions(for provider: LLMProvider) -> [ModelOption] {
    ModelCatalog.menuOptions(
      for: provider,
      selectedProvider: selectedProvider,
      selectedModelId: model,
      rememberedModelId: rememberedModel(for: provider)
    )
  }

  private func isSelected(_ option: ModelOption) -> Bool {
    option.matches(provider: selectedProvider, modelId: model)
  }

  /// Selecting only selects (T-8.8): write the same two storage keys
  /// Settings owns and get out of the way. Key entry stays in Settings.
  private func select(_ option: ModelOption) {
    rememberModel(option.modelId, for: option.provider)
    providerRawValue = option.provider.rawValue
    model = option.modelId
    isMenuPresented = false
  }

  private var selectedProvider: LLMProvider {
    LLMProvider(rawValue: providerRawValue) ?? .openAI
  }

  private var modelDisplayName: String {
    ModelCatalog.displayName(for: model)
  }

  private var selectedProviderNeedsKey: Bool {
    guard selectedProvider != .ollama else {
      return false
    }
    return !hasKey(selectedProvider)
  }

  private func refreshMenuProviders() {
    menuProviders = ModelCatalog.switcherProviders(hasKey: hasKey)
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

  private func normalizedModel(_ value: String, provider: LLMProvider) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? provider.defaultModel : trimmed
  }

  private func hasKey(_ provider: LLMProvider) -> Bool {
    // Dev-only screenshot hooks (same family as GUNK_DEBUG_MODEL_MENU):
    // both short-circuit the Keychain probe entirely. An unsigned debug
    // binary changes identity on every rebuild, so this synchronous
    // `SecItemCopyMatching` (reached from `body` via
    // `selectedProviderNeedsKey` and from `refreshMenuProviders`) raises
    // a blocking Keychain consent dialog *before the first window exists*
    // — scripted runs hang with zero windows until a human clicks.
    //
    // GUNK_DEBUG_KEYED_PROVIDERS=anthropic,openai stages the *keyed* menu
    // states the same way GUNK_DEBUG_NO_KEYCHAIN stages the unkeyed one:
    // only the listed providers (case-insensitive raw values) probe as
    // keyed. It wins when both hooks are set; no-op in normal launches.
    if let staged = ProcessInfo.processInfo.environment["GUNK_DEBUG_KEYED_PROVIDERS"] {
      return staged.split(separator: ",").contains {
        $0.trimmingCharacters(in: .whitespaces)
          .caseInsensitiveCompare(provider.rawValue) == .orderedSame
      }
    }
    if ProcessInfo.processInfo.environment["GUNK_DEBUG_NO_KEYCHAIN"] == "1" {
      return false
    }
    let secret = (try? secretStore.secret(for: provider.secretAccount)) ?? ""
    return !secret.isEmpty
  }
}

// MARK: - Menu row (mockup `.mm-item`)

/// A two-line menu row: model name over a muted subtitle, with the accent
/// check pinned trailing on the selected model.
private struct ModelMenuRow: View {
  let title: String
  let subtitle: String?
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs / 2) {
          Text(title)
            .font(BrandTypography.body.weight(.medium))
            .foregroundStyle(BrandColors.textPrimary)
            .lineLimit(1)

          if let subtitle {
            Text(subtitle)
              .font(BrandTypography.caption)
              .foregroundStyle(BrandColors.textSecondary)
              .lineLimit(1)
          }
        }

        Spacer(minLength: BrandMetrics.Spacing.sm)

        if isSelected {
          Image(systemName: "checkmark")
            .font(BrandTypography.callout.weight(.semibold))
            .foregroundStyle(BrandColors.accent)
        }
      }
      .padding(.horizontal, BrandMetrics.Spacing.sm + 2)
      .padding(.vertical, BrandMetrics.Spacing.sm)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium - 2, style: .continuous)
          .fill(
            isHovering
              ? BrandColors.textPrimary.opacity(BrandMetrics.Control.hoverHighlightOpacity)
              : .clear
          )
      )
      .contentShape(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium - 2, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(BrandMotion.quick) {
        isHovering = hovering
      }
    }
    .accessibilityLabel(subtitle.map { "\(title). \($0)" } ?? title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

// MARK: - Previews

#Preview("Model switcher — keys saved") {
  let secrets = InMemorySecretStore()
  try? secrets.setSecret("sk-test", for: LLMProvider.openAI.secretAccount)
  try? secrets.setSecret("sk-ant-test", for: LLMProvider.anthropic.secretAccount)
  return ModelSwitcher(secretStore: secrets)
    .padding(BrandMetrics.Spacing.xl)
    .background(BrandColors.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Model switcher — no keys") {
  ModelSwitcher(secretStore: InMemorySecretStore())
    .padding(BrandMetrics.Spacing.xl)
    .background(BrandColors.backgroundPrimary)
    .preferredColorScheme(.dark)
}
