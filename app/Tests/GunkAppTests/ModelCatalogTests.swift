import XCTest
@testable import GunkApp

final class ModelCatalogTests: XCTestCase {
  func testHostedProvidersOfferModels() {
    for provider in ModelCatalog.hostedProviders {
      XCTAssertFalse(ModelCatalog.options(for: provider).isEmpty)
    }
  }

  func testLocalProviderHasNoCuratedCatalog() {
    // Ollama's model is user-pulled and typed into Settings, so it has no
    // curated catalog — its single switcher row is derived from the saved
    // model by `menuOptions`, not `options`.
    XCTAssertTrue(ModelCatalog.options(for: .ollama).isEmpty)
  }

  func testSwitcherProvidersAlwaysAppendLocalAfterKeyedHosted() {
    // Ollama is always offered (no key, runs locally) and sits after the
    // keyed hosted providers — this is what lets it be picked from the
    // dropdown without the Settings toggle.
    XCTAssertEqual(
      ModelCatalog.switcherProviders { _ in true },
      ModelCatalog.hostedProviders + [.ollama]
    )
    XCTAssertEqual(ModelCatalog.switcherProviders { _ in false }, [.ollama])
    XCTAssertEqual(ModelCatalog.switcherProviders { $0 == .anthropic }, [.anthropic, .ollama])
  }

  func testLocalMenuOptionIsTheSavedModelWithLocalSubtitle() {
    let options = ModelCatalog.menuOptions(
      for: .ollama,
      selectedProvider: .ollama,
      selectedModelId: "llama3.1:8b"
    )
    XCTAssertEqual(options.count, 1)
    XCTAssertEqual(options.first?.modelId, "llama3.1:8b")
    XCTAssertEqual(options.first?.subtitle, ModelCatalog.localOptionSubtitle)
  }

  func testCatalogDefaultsMatchProviderDefaults() {
    // The switcher's "default" rows must be the same models Settings falls
    // back to, so switching provider through either surface agrees.
    for provider in ModelCatalog.hostedProviders {
      XCTAssertTrue(
        ModelCatalog.options(for: provider).contains { $0.modelId == provider.defaultModel },
        "\(provider.rawValue) catalog is missing its default model"
      )
    }
  }

  func testDisplayNamePrefersCatalogThenPrettifies() {
    XCTAssertEqual(ModelCatalog.displayName(for: "claude-sonnet-4-20250514"), "Claude Sonnet 4")
    XCTAssertEqual(ModelCatalog.displayName(for: "gpt-4.1-mini"), "GPT-4.1 Mini")
    // Off-catalog ids fall back to the prettifier.
    XCTAssertEqual(ModelCatalog.displayName(for: "claude-haiku-3-20240307"), "Claude Haiku 3")
    XCTAssertEqual(ModelCatalog.displayName(for: "gpt-4o"), "GPT 4O")
  }

  // MARK: Menu derivation (T-8.8 close-out)

  func testKeyedProvidersFiltersToKeyedHostedOnly() {
    XCTAssertEqual(ModelCatalog.keyedProviders { _ in true }, ModelCatalog.hostedProviders)
    XCTAssertEqual(ModelCatalog.keyedProviders { _ in false }, [])
    XCTAssertEqual(ModelCatalog.keyedProviders { $0 == .anthropic }, [.anthropic])
    // Ollama can never sneak in through the key probe — it's not hosted.
    XCTAssertEqual(ModelCatalog.keyedProviders { $0 == .ollama }, [])
  }

  func testMenuOptionsAreTheCatalogWhenSavedModelIsOnCatalog() {
    let options = ModelCatalog.menuOptions(
      for: .openAI,
      selectedProvider: .openAI,
      selectedModelId: "gpt-4.1-mini"
    )
    XCTAssertEqual(options, ModelCatalog.options(for: .openAI))
  }

  func testCustomRowAppearsForOffCatalogSavedModel() {
    let options = ModelCatalog.menuOptions(
      for: .anthropic,
      selectedProvider: .anthropic,
      selectedModelId: "claude-haiku-3-20240307"
    )
    XCTAssertEqual(options.count, ModelCatalog.options(for: .anthropic).count + 1)
    let custom = options.last
    XCTAssertEqual(custom?.modelId, "claude-haiku-3-20240307")
    XCTAssertEqual(custom?.displayName, "Claude Haiku 3")
    XCTAssertEqual(custom?.subtitle, ModelCatalog.customOptionSubtitle)
  }

  func testCustomRowOnlyJoinsTheSelectedProvidersSection() {
    // The off-catalog model is saved under Anthropic, so OpenAI's section
    // stays pure catalog.
    let options = ModelCatalog.menuOptions(
      for: .openAI,
      selectedProvider: .anthropic,
      selectedModelId: "claude-haiku-3-20240307"
    )
    XCTAssertEqual(options, ModelCatalog.options(for: .openAI))
  }

  func testRememberedModelCanAddCustomRowForInactiveProvider() {
    let options = ModelCatalog.menuOptions(
      for: .anthropic,
      selectedProvider: .openAI,
      selectedModelId: "gpt-4.1-mini",
      rememberedModelId: "claude-haiku-3-20240307"
    )

    XCTAssertEqual(options.count, ModelCatalog.options(for: .anthropic).count + 1)
    XCTAssertEqual(options.last?.modelId, "claude-haiku-3-20240307")
    XCTAssertEqual(options.last?.subtitle, ModelCatalog.customOptionSubtitle)
  }

  func testNoCustomRowForEmptyOrWhitespaceSavedModel() {
    for savedModel in ["", "   ", "\n"] {
      let options = ModelCatalog.menuOptions(
        for: .openAI,
        selectedProvider: .openAI,
        selectedModelId: savedModel
      )
      XCTAssertEqual(options, ModelCatalog.options(for: .openAI))
    }
  }

  func testSelectionIdentityNeedsBothProviderAndModelId() {
    let option = ModelOption(
      provider: .anthropic,
      modelId: "claude-sonnet-4-20250514",
      displayName: "Claude Sonnet 4",
      subtitle: "Balanced · default"
    )
    XCTAssertTrue(option.matches(provider: .anthropic, modelId: "claude-sonnet-4-20250514"))
    // Same model id under another provider is a different option.
    XCTAssertFalse(option.matches(provider: .openAI, modelId: "claude-sonnet-4-20250514"))
    XCTAssertFalse(option.matches(provider: .anthropic, modelId: "claude-opus-4-20250514"))
  }
}
