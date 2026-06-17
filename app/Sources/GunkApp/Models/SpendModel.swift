import Foundation

struct SpendModel: Equatable, Sendable {
  struct Row: Equatable, Identifiable, Sendable {
    var id: String { "\(provider)::\(model)" }

    let provider: String
    let model: String
    let inputTokens: Int64
    let outputTokens: Int64
    let runCount: Int
    let hasUnknownTokens: Bool
    let costEstimate: CostEstimate
  }

  let rows: [Row]
  let totalInputTokens: Int64
  let totalOutputTokens: Int64
  let totalRunCount: Int
  let totalUSD: Double
  let unknownPriceRowCount: Int
  let priceTableVersion: String
  let effectiveDate: String

  init(
    aggregates: [LLMRunAggregate],
    priceTable: PriceTable = .current,
    limit: Int = 50
  ) {
    let allRows = aggregates.map { aggregate in
      Row(
        provider: aggregate.provider,
        model: aggregate.model,
        inputTokens: aggregate.inputTokens,
        outputTokens: aggregate.outputTokens,
        runCount: aggregate.runCount,
        hasUnknownTokens: aggregate.hasUnknownTokens,
        costEstimate: estimate(
          inputTokens: Self.intTokenCount(aggregate.inputTokens),
          outputTokens: Self.intTokenCount(aggregate.outputTokens),
          provider: aggregate.provider,
          model: aggregate.model,
          priceTable: priceTable
        )
      )
    }

    totalInputTokens = allRows.reduce(0) { $0 + $1.inputTokens }
    totalOutputTokens = allRows.reduce(0) { $0 + $1.outputTokens }
    totalRunCount = allRows.reduce(0) { $0 + $1.runCount }
    totalUSD = allRows.reduce(0) { total, row in
      total + (row.costEstimate.usd ?? 0)
    }
    unknownPriceRowCount = allRows.filter(\.costEstimate.unknownPrice).count
    priceTableVersion = priceTable.priceTableVersion
    effectiveDate = priceTable.effectiveDate

    rows = Array(
      allRows
        .sorted(by: Self.rowSort)
        .prefix(max(0, limit))
    )
  }

  static func load(
    store: Store,
    priceTable: PriceTable = .current,
    limit: Int = 50
  ) throws -> SpendModel {
    SpendModel(
      aggregates: try store.llmRunAggregatesByModel(),
      priceTable: priceTable,
      limit: limit
    )
  }

  private static func intTokenCount(_ value: Int64) -> Int {
    Int(min(max(0, value), Int64(Int.max)))
  }

  private static func rowSort(_ lhs: Row, _ rhs: Row) -> Bool {
    switch (lhs.costEstimate.usd, rhs.costEstimate.usd) {
    case let (left?, right?) where left != right:
      return left > right
    case (_?, nil):
      return true
    case (nil, _?):
      return false
    default:
      if lhs.inputTokens + lhs.outputTokens != rhs.inputTokens + rhs.outputTokens {
        return lhs.inputTokens + lhs.outputTokens > rhs.inputTokens + rhs.outputTokens
      }
      if lhs.provider.localizedCaseInsensitiveCompare(rhs.provider) != .orderedSame {
        return lhs.provider.localizedCaseInsensitiveCompare(rhs.provider) == .orderedAscending
      }
      return lhs.model.localizedCaseInsensitiveCompare(rhs.model) == .orderedAscending
    }
  }
}
