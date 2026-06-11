import SwiftUI

/// A Liquid Glass content container — the standard surface for rows, detail
/// sections, and panels. Wraps its content in `brandGlass` with configurable
/// padding and elevation so screens never re-derive the glass treatment.
struct GlassCard<Content: View>: View {
  var padding: CGFloat = BrandMetrics.Spacing.lg
  var cornerRadius: CGFloat = BrandMetrics.Radius.large
  var elevated: Bool = true
  @ViewBuilder var content: Content

  var body: some View {
    content
      .padding(padding)
      .brandGlass(cornerRadius: cornerRadius, elevated: elevated)
  }
}

// MARK: - Previews

private struct GlassCardPreview: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [BrandColors.accent.opacity(0.5), BrandColors.backgroundPrimary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      VStack(spacing: BrandMetrics.Spacing.lg) {
        GlassCard {
          VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
            Text("Elevated card")
              .font(BrandTypography.headline)
              .foregroundStyle(BrandColors.textPrimary)
            Text("Default padding, large radius, floating shadow.")
              .font(BrandTypography.callout)
              .foregroundStyle(BrandColors.textSecondary)
          }
        }

        GlassCard(
          padding: BrandMetrics.Spacing.md,
          cornerRadius: BrandMetrics.Radius.medium,
          elevated: false
        ) {
          Text("Flat card, tight padding, medium radius.")
            .font(BrandTypography.callout)
            .foregroundStyle(BrandColors.textSecondary)
        }
      }
      .padding(BrandMetrics.Spacing.xl)
    }
    .frame(width: 420, height: 320)
  }
}

#Preview("GlassCard — dark") {
  GlassCardPreview()
    .preferredColorScheme(.dark)
}

#Preview("GlassCard — light") {
  GlassCardPreview()
    .preferredColorScheme(.light)
}
