import GRDB
import XCTest
@testable import GunkApp

final class SpendModelTests: XCTestCase {
  func testUnknownPriceContributesTokensButNotUSD() {
    let model = SpendModel(
      aggregates: [
        LLMRunAggregate(
          provider: "openai",
          model: "known-model",
          inputTokens: 1_000_000,
          outputTokens: 500_000,
          runCount: 2,
          hasUnknownTokens: false
        ),
        LLMRunAggregate(
          provider: "openai",
          model: "custom-fine-tune",
          inputTokens: 2_000_000,
          outputTokens: 1_000_000,
          runCount: 1,
          hasUnknownTokens: false
        )
      ],
      priceTable: Self.testPriceTable
    )

    XCTAssertEqual(model.totalInputTokens, 3_000_000)
    XCTAssertEqual(model.totalOutputTokens, 1_500_000)
    XCTAssertEqual(model.totalRunCount, 3)
    XCTAssertEqual(model.totalUSD, 4.0, accuracy: 0.000_001)
    XCTAssertEqual(model.unknownPriceRowCount, 1)
    XCTAssertEqual(model.rows.first?.model, "known-model")
    XCTAssertNil(model.rows.last?.costEstimate.usd)
    XCTAssertTrue(model.rows.last?.costEstimate.unknownPrice == true)
  }

  func testRowsCarryUnknownTokenFlagAndEstimate() {
    let model = SpendModel(
      aggregates: [
        LLMRunAggregate(
          provider: "openai",
          model: "known-model",
          inputTokens: 0,
          outputTokens: 0,
          runCount: 1,
          hasUnknownTokens: true
        )
      ],
      priceTable: Self.testPriceTable
    )

    XCTAssertEqual(model.rows.count, 1)
    XCTAssertTrue(model.rows[0].hasUnknownTokens)
    XCTAssertEqual(model.rows[0].costEstimate.usd, 0)
    XCTAssertFalse(model.rows[0].costEstimate.unknownPrice)
  }

  func testEmptyStoreProducesEmptyModel() throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })

    let model = try SpendModel.load(store: store, priceTable: Self.testPriceTable)

    XCTAssertEqual(model.rows, [])
    XCTAssertEqual(model.totalInputTokens, 0)
    XCTAssertEqual(model.totalOutputTokens, 0)
    XCTAssertEqual(model.totalRunCount, 0)
    XCTAssertEqual(model.totalUSD, 0)
    XCTAssertEqual(model.unknownPriceRowCount, 0)
  }

  func testPriceTableStampIsExposedForUI() {
    let model = SpendModel(aggregates: [], priceTable: Self.testPriceTable)

    XCTAssertEqual(model.priceTableVersion, "test-v1")
    XCTAssertEqual(model.effectiveDate, "2099-01-01")
  }

  func testRowsAreBounded() {
    let model = SpendModel(
      aggregates: [
        LLMRunAggregate(
          provider: "openai",
          model: "known-model",
          inputTokens: 1_000_000,
          outputTokens: 0,
          runCount: 1,
          hasUnknownTokens: false
        ),
        LLMRunAggregate(
          provider: "openai",
          model: "other-known-model",
          inputTokens: 1_000_000,
          outputTokens: 0,
          runCount: 1,
          hasUnknownTokens: false
        )
      ],
      priceTable: Self.testPriceTable,
      limit: 1
    )

    XCTAssertEqual(model.rows.count, 1)
    XCTAssertEqual(model.totalRunCount, 2)
  }

  func testProjectionUsesEstimatedTotalAndReportsUnknownPriceGaps() {
    let model = SpendModel(
      aggregates: [
        LLMRunAggregate(
          provider: "openai",
          model: "known-model",
          inputTokens: 1_000_000,
          outputTokens: 500_000,
          runCount: 1,
          hasUnknownTokens: false
        ),
        LLMRunAggregate(
          provider: "openai",
          model: "custom-fine-tune",
          inputTokens: 4_000_000,
          outputTokens: 2_000_000,
          runCount: 1,
          hasUnknownTokens: false
        )
      ],
      priceTable: Self.testPriceTable
    )

    XCTAssertEqual(model.projectedMonthlySpend.estimatedUSD, 4.0, accuracy: 0.000_001)
    XCTAssertEqual(model.projectedMonthlySpend.unknownPriceRowCount, 1)
    XCTAssertTrue(model.projectedMonthlySpend.hasUnknownPriceGaps)
  }

  func testProjectionTreatsLocalRowsAsKnownFreeRows() {
    let model = SpendModel(
      aggregates: [
        LLMRunAggregate(
          provider: "ollama",
          model: "local-model",
          inputTokens: 4_000_000,
          outputTokens: 2_000_000,
          runCount: 3,
          hasUnknownTokens: false
        )
      ],
      priceTable: Self.testPriceTable
    )

    XCTAssertEqual(model.projectedMonthlySpend.estimatedUSD, 0, accuracy: 0.000_001)
    XCTAssertEqual(model.projectedMonthlySpend.unknownPriceRowCount, 0)
    XCTAssertFalse(model.projectedMonthlySpend.hasUnknownPriceGaps)
  }

  private static let testPriceTable = PriceTable(
    priceTableVersion: "test-v1",
    effectiveDate: "2099-01-01",
    sourceURLString: "https://example.test/prices",
    prices: [
      PriceKey(provider: "openai", model: "known-model"): ModelPrice(
        inputPricePerMTok: 2,
        outputPricePerMTok: 4,
        isLocal: false
      ),
      PriceKey(provider: "openai", model: "other-known-model"): ModelPrice(
        inputPricePerMTok: 1,
        outputPricePerMTok: 1,
        isLocal: false
      )
    ]
  )
}
