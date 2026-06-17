import Foundation

struct ModelPrice: Equatable {
  let inputPricePerMTok: Double
  let outputPricePerMTok: Double
  let isLocal: Bool
}

struct PriceTable: Equatable {
  let priceTableVersion: String
  let effectiveDate: String
  let sourceURLString: String
  private let prices: [PriceKey: ModelPrice]

  init(
    priceTableVersion: String,
    effectiveDate: String,
    sourceURLString: String,
    prices: [PriceKey: ModelPrice]
  ) {
    self.priceTableVersion = priceTableVersion
    self.effectiveDate = effectiveDate
    self.sourceURLString = sourceURLString
    self.prices = prices
  }

  func price(provider: String, model: String) -> ModelPrice? {
    let key = PriceKey(provider: provider, model: model)
    if key.provider == "ollama" || key.provider == "local" {
      return Self.localModelPrice
    }

    return prices[key]
  }

  // PRICES: v1, effective 2026-06-17. These prices are hand-captured from
  // official provider pricing/model pages and are used only to estimate spend
  // from stored token counts. They are static in-repo data, not a DB table.
  // Staleness is signalled by effectiveDate + priceTableVersion; it never
  // blocks estimation. Unknown hosted models return nil USD so the UI renders
  // "-", never "$0". Ollama/local models are free-but-known and return $0
  // with isLocal = true.
  //
  // Sources captured 2026-06-17:
  // - https://developers.openai.com/api/docs/models/gpt-4.1
  // - https://developers.openai.com/api/docs/models/gpt-4.1-mini
  // - https://developers.openai.com/api/docs/models/gpt-4.1-nano
  // - https://platform.claude.com/docs/en/about-claude/pricing
  // - https://ollama.com/pricing
  static let current = PriceTable(
    priceTableVersion: "v1",
    effectiveDate: "2026-06-17",
    sourceURLString: "https://platform.claude.com/docs/en/about-claude/pricing",
    prices: [
      PriceKey(provider: "openai", model: "gpt-4.1"): hosted(input: 2.00, output: 8.00),
      PriceKey(provider: "openai", model: "gpt-4.1-2025-04-14"): hosted(input: 2.00, output: 8.00),
      PriceKey(provider: "openai", model: "gpt-4.1-mini"): hosted(input: 0.40, output: 1.60),
      PriceKey(provider: "openai", model: "gpt-4.1-mini-2025-04-14"): hosted(input: 0.40, output: 1.60),
      PriceKey(provider: "openai", model: "gpt-4.1-nano"): hosted(input: 0.10, output: 0.40),
      PriceKey(provider: "openai", model: "gpt-4.1-nano-2025-04-14"): hosted(input: 0.10, output: 0.40),

      PriceKey(provider: "anthropic", model: "claude-sonnet-4-20250514"): hosted(input: 3.00, output: 15.00),
      PriceKey(provider: "anthropic", model: "claude-sonnet-4"): hosted(input: 3.00, output: 15.00),
      PriceKey(provider: "anthropic", model: "claude-sonnet-4-5"): hosted(input: 3.00, output: 15.00),
      PriceKey(provider: "anthropic", model: "claude-sonnet-4-6"): hosted(input: 3.00, output: 15.00),
      PriceKey(provider: "anthropic", model: "claude-opus-4-20250514"): hosted(input: 15.00, output: 75.00),
      PriceKey(provider: "anthropic", model: "claude-opus-4"): hosted(input: 15.00, output: 75.00),
      PriceKey(provider: "anthropic", model: "claude-opus-4-1"): hosted(input: 15.00, output: 75.00),
      PriceKey(provider: "anthropic", model: "claude-opus-4-5"): hosted(input: 5.00, output: 25.00),
      PriceKey(provider: "anthropic", model: "claude-opus-4-6"): hosted(input: 5.00, output: 25.00),
      PriceKey(provider: "anthropic", model: "claude-haiku-4-5"): hosted(input: 1.00, output: 5.00),
      PriceKey(provider: "anthropic", model: "claude-haiku-4-5-20251001"): hosted(input: 1.00, output: 5.00),

      PriceKey(provider: "ollama", model: "llama3.2"): localModelPrice,
    ]
  )

  private static let localModelPrice = ModelPrice(
    inputPricePerMTok: 0,
    outputPricePerMTok: 0,
    isLocal: true
  )

  private static func hosted(input: Double, output: Double) -> ModelPrice {
    ModelPrice(inputPricePerMTok: input, outputPricePerMTok: output, isLocal: false)
  }
}

struct PriceKey: Hashable {
  let provider: String
  let model: String

  init(provider: String, model: String) {
    self.provider = Self.normalize(provider)
    self.model = Self.normalize(model)
  }

  private static func normalize(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}
