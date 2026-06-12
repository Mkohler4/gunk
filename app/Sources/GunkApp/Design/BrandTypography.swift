import AppKit
import SwiftUI

/// Named type scale for the gunk brand. Views must use these tokens — never
/// ad-hoc `Font` values.
///
/// The brand faces from the concept boards are **Space Grotesk** (display/UI)
/// and **JetBrains Mono** (code/metadata). The font files are not bundled
/// yet, so each token resolves the brand face when it is installed and falls
/// back to the system font otherwise.
/// // BRAND-PLACEHOLDER: bundle Space Grotesk + JetBrains Mono and register
/// // them at launch so the fallback never ships.
enum BrandTypography {
  static let sansFamily = "Space Grotesk"
  static let monoFamily = "JetBrains Mono"

  /// Hero numerals / launch wordmark.
  static let display = sans(size: 34, weight: .semibold)
  /// Window and section titles.
  static let title = sans(size: 22, weight: .semibold)
  /// Card titles, emphasized rows.
  static let headline = sans(size: 15, weight: .semibold)
  /// Briefing-card module names (toolbox-v2 cell: 16/600).
  static let cardTitle = sans(size: 16, weight: .semibold)
  /// Hero-cell module names (toolbox-v2 hero: 19/600).
  static let cardTitleHero = sans(size: 19, weight: .semibold)
  /// Default reading size.
  static let body = sans(size: 13, weight: .regular)
  /// Secondary labels, list metadata.
  static let callout = sans(size: 12, weight: .medium)
  /// Footnotes, timestamps, hints.
  static let caption = sans(size: 11, weight: .regular)
  /// Code, paths, identifiers.
  static let mono = monospaced(size: 12, weight: .regular)

  static func sans(size: CGFloat, weight: Font.Weight) -> Font {
    if NSFont(name: sansFamily, size: size) != nil {
      return .custom(sansFamily, size: size).weight(weight)
    }
    return .system(size: size, weight: weight)
  }

  static func monospaced(size: CGFloat, weight: Font.Weight) -> Font {
    if NSFont(name: monoFamily, size: size) != nil {
      return .custom(monoFamily, size: size).weight(weight)
    }
    return .system(size: size, weight: weight, design: .monospaced)
  }
}

#Preview("Type scale") {
  BrandTypeScale()
    .preferredColorScheme(.dark)
}

struct BrandTypeScale: View {
  private let steps: [(String, Font)] = [
    ("display", BrandTypography.display),
    ("title", BrandTypography.title),
    ("headline", BrandTypography.headline),
    ("body", BrandTypography.body),
    ("callout", BrandTypography.callout),
    ("caption", BrandTypography.caption),
    ("mono", BrandTypography.mono),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
      ForEach(steps, id: \.0) { name, font in
        HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.lg) {
          Text(name)
            .font(BrandTypography.mono)
            .foregroundStyle(BrandColors.textTertiary)
            .frame(width: 72, alignment: .trailing)
          Text("Born from the goo.")
            .font(font)
            .foregroundStyle(BrandColors.textPrimary)
        }
      }
    }
    .padding(BrandMetrics.Spacing.xl)
    .background(BrandColors.backgroundPrimary)
  }
}
