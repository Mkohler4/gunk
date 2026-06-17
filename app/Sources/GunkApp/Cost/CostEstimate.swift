import Foundation

struct CostEstimate: Equatable {
  let usd: Double?
  let isEstimated: Bool
  let priceTableVersion: String
  let unknownPrice: Bool
  let isLocal: Bool
}

func estimate(
  inputTokens: Int?,
  outputTokens: Int?,
  provider: String,
  model: String,
  priceTable: PriceTable = .current
) -> CostEstimate {
  guard let price = priceTable.price(provider: provider, model: model) else {
    return CostEstimate(
      usd: nil,
      isEstimated: true,
      priceTableVersion: priceTable.priceTableVersion,
      unknownPrice: true,
      isLocal: false
    )
  }

  let inputTokenCount = max(0, inputTokens ?? 0)
  let outputTokenCount = max(0, outputTokens ?? 0)
  let inputCost = Double(inputTokenCount) / 1_000_000 * price.inputPricePerMTok
  let outputCost = Double(outputTokenCount) / 1_000_000 * price.outputPricePerMTok

  return CostEstimate(
    usd: inputCost + outputCost,
    isEstimated: true,
    priceTableVersion: priceTable.priceTableVersion,
    unknownPrice: false,
    isLocal: price.isLocal
  )
}
