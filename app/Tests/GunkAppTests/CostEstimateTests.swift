import XCTest
@testable import GunkApp

final class CostEstimateTests: XCTestCase {
  func testKnownModelReturnsStampedEstimate() {
    let result = estimate(
      inputTokens: 1_500_000,
      outputTokens: 250_000,
      provider: "OpenAI",
      model: "gpt-4.1-mini"
    )

    XCTAssertNotNil(result.usd)
    XCTAssertEqual(result.usd ?? -1, 1.0, accuracy: 0.000_001)
    XCTAssertTrue(result.isEstimated)
    XCTAssertEqual(result.priceTableVersion, PriceTable.current.priceTableVersion)
    XCTAssertFalse(result.unknownPrice)
    XCTAssertFalse(result.isLocal)
  }

  func testUnknownHostedModelReturnsNilUSDAndUnknownPrice() {
    let result = estimate(
      inputTokens: 1_000_000,
      outputTokens: 1_000_000,
      provider: "OpenAI",
      model: "custom-fine-tune"
    )

    XCTAssertNil(result.usd)
    XCTAssertTrue(result.isEstimated)
    XCTAssertEqual(result.priceTableVersion, PriceTable.current.priceTableVersion)
    XCTAssertTrue(result.unknownPrice)
    XCTAssertFalse(result.isLocal)
  }

  func testLocalOllamaModelReturnsZeroButIsKnownLocal() {
    let result = estimate(
      inputTokens: 5_000_000,
      outputTokens: 2_000_000,
      provider: "Ollama",
      model: "llama3.2"
    )

    XCTAssertEqual(result.usd, 0)
    XCTAssertTrue(result.isEstimated)
    XCTAssertFalse(result.unknownPrice)
    XCTAssertTrue(result.isLocal)
  }

  func testAnyOllamaModelIsFreeButKnownLocal() {
    let result = estimate(
      inputTokens: 10_000,
      outputTokens: 10_000,
      provider: "ollama",
      model: "qwen2.5-coder:32b"
    )

    XCTAssertEqual(result.usd, 0)
    XCTAssertFalse(result.unknownPrice)
    XCTAssertTrue(result.isLocal)
  }

  func testZeroAndAbsentTokensAreHandledAsZeroUsage() {
    let zero = estimate(
      inputTokens: 0,
      outputTokens: 0,
      provider: "Anthropic",
      model: "claude-sonnet-4-20250514"
    )
    let absent = estimate(
      inputTokens: nil,
      outputTokens: nil,
      provider: "Anthropic",
      model: "claude-sonnet-4-20250514"
    )

    XCTAssertEqual(zero.usd, 0)
    XCTAssertEqual(absent.usd, 0)
    XCTAssertFalse(zero.unknownPrice)
    XCTAssertFalse(absent.unknownPrice)
  }

  func testVersionStampCarriesThroughFromInjectedTable() {
    let table = PriceTable(
      priceTableVersion: "test-v9",
      effectiveDate: "2099-01-01",
      sourceURLString: "https://example.test/prices",
      prices: [
        PriceKey(provider: "openai", model: "test-model"): ModelPrice(
          inputPricePerMTok: 2,
          outputPricePerMTok: 4,
          isLocal: false
        )
      ]
    )

    let result = estimate(
      inputTokens: 500_000,
      outputTokens: 250_000,
      provider: "OpenAI",
      model: "test-model",
      priceTable: table
    )

    XCTAssertNotNil(result.usd)
    XCTAssertEqual(result.usd ?? -1, 2.0, accuracy: 0.000_001)
    XCTAssertEqual(result.priceTableVersion, "test-v9")
    XCTAssertTrue(result.isEstimated)
  }

  func testModelSuffixVariantsPreferUnknownOverWrongMatch() {
    let result = estimate(
      inputTokens: 1_000_000,
      outputTokens: 1_000_000,
      provider: "OpenAI",
      model: "gpt-4.1-mini-custom-suffix"
    )

    XCTAssertNil(result.usd)
    XCTAssertTrue(result.unknownPrice)
  }

  func testNormalizationTrimsAndLowercasesExactKnownKeysOnly() {
    let result = estimate(
      inputTokens: 1_000_000,
      outputTokens: 1_000_000,
      provider: "  anthropic ",
      model: " CLAUDE-SONNET-4-20250514\n"
    )

    XCTAssertNotNil(result.usd)
    XCTAssertEqual(result.usd ?? -1, 18.0, accuracy: 0.000_001)
    XCTAssertFalse(result.unknownPrice)
  }
}
