import SwiftUI

/// The provider-provenance treatment as a large, faint brand watermark that
/// bleeds off a briefing card's bottom-trailing corner. Quiet enough to live
/// behind the content (never a state signal), but unmistakable at a glance —
/// the card "feels" like the model that made it. Providers we ship artwork for
/// (OpenAI, Anthropic, Ollama) render their mark; everything else shows
/// nothing, so the card simply reads as un-watermarked.
struct ProviderWatermark: View {
  let provider: String
  /// Glyph box edge. The mark is sized to the card and bled off the corner by
  /// the caller's clip, so this is roughly card-height.
  var size: CGFloat
  /// How faint the mark sits over the card surface.
  var opacity: Double = 0.06

  var body: some View {
    if let icon = ProviderIcon.resolve(for: provider),
       let image = ProviderIconLoader.image(for: icon) {
      Image(nsImage: image)
        .resizable()
        .renderingMode(.template)
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .foregroundStyle(BrandColors.textPrimary.opacity(opacity))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
  }
}

// MARK: - Previews

#Preview("ProviderWatermark") {
  let providers = ["openai", "anthropic", "ollama", "google"]
  return HStack(spacing: BrandMetrics.Spacing.lg) {
    ForEach(providers, id: \.self) { provider in
      ZStack(alignment: .bottomTrailing) {
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous)
          .fill(BrandColors.backgroundElevated)
        ProviderWatermark(provider: provider, size: 150)
          .offset(x: 26, y: 26)
      }
      .clipShape(RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous))
      .frame(width: 200, height: 168)
    }
  }
  .padding(BrandMetrics.Spacing.xl)
  .background(BrandColors.backgroundPrimary)
  .preferredColorScheme(.dark)
}
