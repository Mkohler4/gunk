import Foundation
import SwiftUI

struct SpendView: View {
  let model: SpendModel

  private enum Layout {
    static let tokenColumnWidth: CGFloat = 118
    static let usdColumnWidth: CGFloat = 212
  }

  var body: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
      if model.rows.isEmpty {
        emptyPanel
      } else {
        spendTable
      }

      if model.unknownPriceRowCount > 0 {
        unknownPriceNote
      }

      honestyFooter
    }
  }

  private var spendTable: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .center) {
        Text("By key & model")
          .font(BrandTypography.callout.weight(.semibold))
          .foregroundStyle(BrandColors.textSecondary)

        Spacer(minLength: BrandMetrics.Spacing.md)

        Text("Since first run")
          .font(BrandTypography.callout.weight(.semibold))
          .foregroundStyle(BrandColors.textSecondary)
          .padding(.horizontal, BrandMetrics.Spacing.sm)
          .padding(.vertical, BrandMetrics.Spacing.xs)
          .background(
            RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
              .fill(BrandColors.backgroundSecondary)
          )
          .overlay(
            RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
              .strokeBorder(BrandColors.separator)
          )
      }
      .padding(.horizontal, BrandMetrics.Spacing.md)
      .padding(.vertical, BrandMetrics.Spacing.md)

      Divider().background(BrandColors.separator)

      tableHeader

      Divider().background(BrandColors.separator)

      VStack(spacing: 0) {
        ForEach(model.rows) { row in
          spendRow(row)

          if row.id != model.rows.last?.id {
            Divider()
              .background(BrandColors.separator)
              .padding(.leading, BrandMetrics.Spacing.md)
          }
        }
      }

      Divider().background(BrandColors.separator)

      totalRow
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(BrandColors.backgroundElevated)
    )
    .overlay(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .strokeBorder(BrandColors.separator)
    )
  }

  private var tableHeader: some View {
    HStack(alignment: .top, spacing: BrandMetrics.Spacing.md) {
      Text("MODEL")
        .frame(maxWidth: .infinity, alignment: .leading)

      Text("TOKENS")
        .frame(width: Layout.tokenColumnWidth, alignment: .trailing)

      VStack(alignment: .trailing, spacing: 2) {
        Text("ESTIMATED USD")
        Text(priceStamp)
          .font(BrandTypography.mono)
          .foregroundStyle(BrandColors.textTertiary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .frame(width: Layout.usdColumnWidth, alignment: .trailing)
    }
    .font(BrandTypography.caption.weight(.semibold))
    .foregroundStyle(BrandColors.textTertiary)
    .padding(.horizontal, BrandMetrics.Spacing.md)
    .padding(.vertical, BrandMetrics.Spacing.sm)
  }

  private func spendRow(_ row: SpendModel.Row) -> some View {
    HStack(alignment: .center, spacing: BrandMetrics.Spacing.md) {
      HStack(alignment: .top, spacing: BrandMetrics.Spacing.sm) {
        ProviderMark(provider: row.provider, size: 22)

        VStack(alignment: .leading, spacing: 3) {
          Text(row.model)
            .font(BrandTypography.headline)
            .foregroundStyle(BrandColors.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)

          HStack(spacing: BrandMetrics.Spacing.xs) {
            Text(displayProvider(row.provider))
              .font(BrandTypography.caption)
              .foregroundStyle(BrandColors.textSecondary)

            if row.costEstimate.isLocal {
              Text("local")
                .font(BrandTypography.caption.weight(.semibold))
                .foregroundStyle(BrandColors.textTertiary)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      VStack(alignment: .trailing, spacing: 3) {
        Text("\(Self.formatTokens(row.inputTokens)) in")
        Text("\(Self.formatTokens(row.outputTokens)) out")
        if row.hasUnknownTokens {
          Text("partial")
            .font(BrandTypography.caption)
            .foregroundStyle(BrandColors.warning)
        }
      }
      .font(BrandTypography.mono)
      .foregroundStyle(BrandColors.textSecondary)
      .frame(width: Layout.tokenColumnWidth, alignment: .trailing)

      usdCell(for: row)
        .frame(width: Layout.usdColumnWidth, alignment: .trailing)
    }
    .padding(.horizontal, BrandMetrics.Spacing.md)
    .padding(.vertical, BrandMetrics.Spacing.md)
    .background(row.costEstimate.unknownPrice ? BrandColors.warning.opacity(0.05) : .clear)
  }

  @ViewBuilder
  private func usdCell(for row: SpendModel.Row) -> some View {
    if row.costEstimate.unknownPrice {
      Text("—")
        .font(BrandTypography.headline)
        .foregroundStyle(BrandColors.textSecondary)
    } else if row.costEstimate.isLocal {
      VStack(alignment: .trailing, spacing: 2) {
        Text("free")
          .font(BrandTypography.headline)
          .foregroundStyle(BrandColors.textSecondary)
        Text("local")
          .font(BrandTypography.caption.weight(.semibold))
          .foregroundStyle(BrandColors.textTertiary)
      }
    } else if let usd = row.costEstimate.usd {
      HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.xs) {
        Text("EST")
          .font(BrandTypography.caption.weight(.semibold))
          .foregroundStyle(BrandColors.textTertiary)
        Text(Self.formatUSD(usd))
          .font(BrandTypography.headline)
          .foregroundStyle(BrandColors.textPrimary)
      }
    }
  }

  private var totalRow: some View {
    HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.md) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Estimated total")
          .font(BrandTypography.headline)
          .foregroundStyle(BrandColors.textPrimary)

        Text(totalSubtitle)
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
      }

      Spacer(minLength: BrandMetrics.Spacing.md)

      HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.xs) {
        Text("EST")
          .font(BrandTypography.caption.weight(.semibold))
          .foregroundStyle(BrandColors.textTertiary)
        Text(Self.formatUSD(model.totalUSD))
          .font(BrandTypography.title)
          .foregroundStyle(BrandColors.success)
      }
    }
    .padding(.horizontal, BrandMetrics.Spacing.md)
    .padding(.vertical, BrandMetrics.Spacing.md)
  }

  private var emptyPanel: some View {
    VStack(spacing: BrandMetrics.Spacing.md) {
      Image(systemName: "circle.dashed")
        .font(.system(size: 30, weight: .medium))
        .foregroundStyle(BrandColors.textTertiary)
        .frame(width: 54, height: 54)
        .background(
          Circle().fill(BrandColors.backgroundSecondary)
        )

      VStack(spacing: BrandMetrics.Spacing.sm) {
        Text("No spend yet")
          .font(BrandTypography.headline)
          .foregroundStyle(BrandColors.textPrimary)

        Text("Run a decomposition and the tokens it uses will show up here, grouped by key and model — with an estimated cost beside each.")
          .font(BrandTypography.body)
          .foregroundStyle(BrandColors.textSecondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 420)
      }
    }
    .padding(.horizontal, BrandMetrics.Spacing.xl)
    .padding(.vertical, 52)
    .frame(maxWidth: .infinity, alignment: .center)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(BrandColors.backgroundElevated)
    )
    .overlay(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .strokeBorder(BrandColors.separator)
    )
  }

  private var unknownPriceNote: some View {
    HStack(alignment: .top, spacing: BrandMetrics.Spacing.sm) {
      Image(systemName: "exclamationmark.triangle")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.warning)
        .frame(width: 16)

      Text(unknownPriceCopy)
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(BrandMetrics.Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(BrandColors.warning.opacity(BrandMetrics.Control.tintedFillOpacity))
    )
    .overlay(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .strokeBorder(BrandColors.warning.opacity(0.35))
    )
  }

  private var honestyFooter: some View {
    HStack(alignment: .top, spacing: BrandMetrics.Spacing.sm) {
      Image(systemName: "info.circle")
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textTertiary)
        .frame(width: 14)

      Text("Reflects decomposition survey + refine calls only — not anything your agent runs later. Cost is computed from real token counts; the dollar figure is never stored.")
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(BrandMetrics.Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(BrandColors.backgroundElevated)
    )
    .overlay(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .strokeBorder(BrandColors.separator)
    )
  }

  private var priceStamp: String {
    "Prices as of \(Self.formatPriceDate(model.effectiveDate)) · \(model.priceTableVersion)"
  }

  private var totalSubtitle: String {
    if model.unknownPriceRowCount == 0 {
      return "since first run"
    }

    return "excludes \(model.unknownPriceRowCount) \(model.unknownPriceRowCount == 1 ? "model" : "models") with no price on file"
  }

  private var unknownPriceCopy: String {
    if model.unknownPriceRowCount == 1 {
      return "One model isn't in the price table (a custom fine-tune). Its tokens are exact, but gunk shows — instead of guessing a dollar figure — it never invents a price or shows $0."
    }

    return "\(model.unknownPriceRowCount) models aren't in the price table. Their tokens are exact, but gunk shows — instead of guessing a dollar figure — it never invents a price or shows $0."
  }

  private static func formatTokens(_ tokens: Int64) -> String {
    let value = Double(max(0, tokens))
    switch value {
    case 1_000_000...:
      return String(format: "%.2fM", value / 1_000_000)
    case 1_000...:
      let thousands = value / 1_000
      if thousands >= 100 {
        return String(format: "%.0fK", thousands)
      }
      return String(format: "%.1fK", thousands)
    default:
      return NumberFormatter.integer.string(from: NSNumber(value: Int64(value))) ?? "\(Int64(value))"
    }
  }

  private static func formatUSD(_ value: Double) -> String {
    NumberFormatter.usd.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
  }

  private static func formatPriceDate(_ value: String) -> String {
    let input = DateFormatter()
    input.calendar = Calendar(identifier: .gregorian)
    input.locale = Locale(identifier: "en_US_POSIX")
    input.dateFormat = "yyyy-MM-dd"

    guard let date = input.date(from: value) else {
      return value
    }

    let output = DateFormatter()
    output.calendar = Calendar(identifier: .gregorian)
    output.locale = Locale(identifier: "en_US_POSIX")
    output.dateFormat = "MMM d yyyy"
    return output.string(from: date)
  }

  private func displayProvider(_ provider: String) -> String {
    switch provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "openai":
      return "OpenAI"
    case "anthropic":
      return "Anthropic"
    case "ollama", "local":
      return "Ollama"
    default:
      return provider
    }
  }
}

private extension NumberFormatter {
  static let integer: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    return formatter
  }()

  static let usd: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter
  }()
}

extension SpendModel {
  static let fixtureEmpty = SpendModel(aggregates: [])

  static let fixturePopulated = SpendModel(
    aggregates: [
      LLMRunAggregate(
        provider: "anthropic",
        model: "claude-sonnet-4",
        inputTokens: 2_410_000,
        outputTokens: 384_000,
        runCount: 18,
        hasUnknownTokens: false
      ),
      LLMRunAggregate(
        provider: "openai",
        model: "gpt-4.1",
        inputTokens: 1_100_000,
        outputTokens: 220_000,
        runCount: 12,
        hasUnknownTokens: false
      )
    ]
  )

  static let fixtureUnknownPrice = SpendModel(
    aggregates: [
      LLMRunAggregate(
        provider: "anthropic",
        model: "claude-sonnet-4",
        inputTokens: 2_410_000,
        outputTokens: 384_000,
        runCount: 18,
        hasUnknownTokens: false
      ),
      LLMRunAggregate(
        provider: "openai",
        model: "ft:custom-decomp-x",
        inputTokens: 612_000,
        outputTokens: 88_000,
        runCount: 5,
        hasUnknownTokens: false
      ),
      LLMRunAggregate(
        provider: "openai",
        model: "gpt-4.1",
        inputTokens: 1_100_000,
        outputTokens: 220_000,
        runCount: 12,
        hasUnknownTokens: false
      )
    ]
  )

  static let fixtureLocal = SpendModel(
    aggregates: [
      LLMRunAggregate(
        provider: "ollama",
        model: "llama3.2",
        inputTokens: 742_000,
        outputTokens: 126_000,
        runCount: 7,
        hasUnknownTokens: false
      ),
      LLMRunAggregate(
        provider: "anthropic",
        model: "claude-sonnet-4",
        inputTokens: 940_000,
        outputTokens: 118_000,
        runCount: 4,
        hasUnknownTokens: false
      )
    ]
  )
}

#Preview("Spend — populated") {
  SpendView(model: .fixturePopulated)
    .padding(BrandMetrics.Spacing.xl)
    .background(BrandColors.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Spend — empty") {
  SpendView(model: .fixtureEmpty)
    .padding(BrandMetrics.Spacing.xl)
    .background(BrandColors.backgroundPrimary)
    .preferredColorScheme(.dark)
}
