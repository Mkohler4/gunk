import SwiftUI

/// The toolbox-v2 provenance corner badge, reimagined as a "provider token":
/// a small graphite-glass squircle that carries the model provider's brand
/// glyph. The provider color is reserved for *meaning* (the brand) — it shows
/// up as a tinted glyph, a hairline ring, and a soft outer glow rather than a
/// flat saturated block. Providers we ship artwork for (OpenAI, Anthropic,
/// Ollama) show their mark; everything else falls back to its initial. Quiet
/// and scannable — never a state signal.
struct ProviderBadge: View {
  let provider: String

  /// Bumped up from the old 19pt block so the mark actually reads. The token
  /// stays compact enough to ride the briefing-card corner.
  private static let size: CGFloat = 26
  /// Continuous-corner squircle, ~⅓ of the box — an app-icon silhouette.
  private static let cornerRadius: CGFloat = 8.5
  /// The brand glyph sits inside the token with breathing room from the ring.
  private static let glyphInset: CGFloat = 6
  /// Hairline ring + crisp inner highlight widths.
  private static let ringWidth: CGFloat = 1
  /// Soft colored halo that lifts the token off the card.
  private static let glowRadius: CGFloat = 4

  private var accent: Color {
    BrandColors.providerAccent(for: provider)
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
  }

  var body: some View {
    glyphContent
      .foregroundStyle(accent)
      .shadow(color: .black.opacity(0.45), radius: 0.5, y: 0.5)
      .frame(width: Self.size, height: Self.size)
      .background(tokenSurface)
      .overlay(sheen)
      .overlay(ring)
      .shadow(color: accent.opacity(0.45), radius: Self.glowRadius)
      .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
      .accessibilityLabel("Extracted by \(provider)")
      .help("Extracted by \(provider)")
  }

  // MARK: Glyph

  @ViewBuilder
  private var glyphContent: some View {
    if let icon = ProviderIcon.resolve(for: provider),
       let image = ProviderIconLoader.image(for: icon) {
      Image(nsImage: image)
        .resizable()
        .renderingMode(.template)
        .aspectRatio(contentMode: .fit)
        .frame(
          width: Self.size - Self.glyphInset * 2,
          height: Self.size - Self.glyphInset * 2
        )
    } else {
      Text(letterGlyph)
        .font(BrandTypography.callout.weight(.bold))
    }
  }

  private var letterGlyph: String {
    guard let first = provider.trimmingCharacters(in: .whitespaces).first else {
      return "·"
    }

    return String(first).uppercased()
  }

  // MARK: Token chrome

  /// A dark graphite base with a faint top-down brand wash — appearance-
  /// invariant art (like the brand marks), so the token reads as an icon on
  /// both light and dark cards.
  private var tokenSurface: some View {
    shape
      .fill(
        LinearGradient(
          colors: [Color(hex: 0x26262B), Color(hex: 0x141416)],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .overlay(
        shape.fill(
          RadialGradient(
            colors: [accent.opacity(0.30), .clear],
            center: .top,
            startRadius: 0,
            endRadius: Self.size * 0.9
          )
        )
      )
  }

  /// Glossy liquid-glass highlight: a top sheen plus a 1pt inner top hairline,
  /// both clipped to the squircle so they fade through the corners.
  private var sheen: some View {
    shape
      .fill(
        LinearGradient(
          colors: [.white.opacity(0.18), .clear],
          startPoint: .top,
          endPoint: UnitPoint(x: 0.5, y: 0.55)
        )
      )
      .overlay(alignment: .top) {
        Rectangle()
          .fill(.white.opacity(0.16))
          .frame(height: 1)
      }
      .clipShape(shape)
      .allowsHitTesting(false)
  }

  /// The provider-colored hairline ring carries the brand identity on the
  /// edge, over a faint white edge so the token never melts into the card.
  private var ring: some View {
    shape
      .strokeBorder(
        LinearGradient(
          colors: [accent.opacity(0.85), accent.opacity(0.45)],
          startPoint: .top,
          endPoint: .bottom
        ),
        lineWidth: Self.ringWidth
      )
      .allowsHitTesting(false)
  }
}

// MARK: - Previews

#Preview("ProviderBadge") {
  VStack(spacing: BrandMetrics.Spacing.xl) {
    HStack(spacing: BrandMetrics.Spacing.lg) {
      ProviderBadge(provider: "anthropic")
      ProviderBadge(provider: "openai")
      ProviderBadge(provider: "ollama")
      // No shipped artwork — falls back to the initial-letter glyph.
      ProviderBadge(provider: "google")
    }
    .padding(BrandMetrics.Spacing.xl)
    .background(BrandColors.backgroundElevated)

    HStack(spacing: BrandMetrics.Spacing.lg) {
      ProviderBadge(provider: "anthropic")
      ProviderBadge(provider: "openai")
      ProviderBadge(provider: "ollama")
      ProviderBadge(provider: "google")
    }
    .padding(BrandMetrics.Spacing.xl)
    .background(BrandColors.backgroundElevated)
    .environment(\.colorScheme, .light)
  }
  .padding(BrandMetrics.Spacing.xl)
  .background(BrandColors.backgroundPrimary)
  .preferredColorScheme(.dark)
}
