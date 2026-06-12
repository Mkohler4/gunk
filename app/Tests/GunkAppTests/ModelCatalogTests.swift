import XCTest
@testable import GunkApp

final class ModelCatalogTests: XCTestCase {
  func testHostedProvidersOfferModels() {
    for provider in ModelCatalog.hostedProviders {
      XCTAssertFalse(ModelCatalog.options(for: provider).isEmpty)
    }
  }

  func testLocalProviderIsIgnoredForNow() {
    XCTAssertTrue(ModelCatalog.options(for: .ollama).isEmpty)
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
}
