import SwiftUI

/// A compact provider provenance mark for dense surfaces (the Library list
/// row, library-v2 §1 `pmark`): a small provider-accent squircle carrying the
/// provider's brand glyph, or its initial when no artwork ships. Quiet
/// provenance, never a state signal — the louder `ProviderBadge` is for the
/// briefing card's corner; this is the 20pt inline mark for a row.
///
/// The provider→color/glyph resolution is shared with `ProviderBadge`
/// (`BrandColors.providerAccent` + `ProviderIcon`), so a real provider logo
/// (T-9.2) drops into this same slot without a relayout.
struct ProviderMark: View {
  let provider: String
  /// library-v2 §1 locks the list `pmark` at 20×20.
  var size: CGFloat = 20

  /// Inset of the glyph inside the squircle so it never touches the ring.
  private static let glyphInset: CGFloat = 4

  private var accent: Color {
    BrandColors.providerAccent(for: provider)
  }

  private var shape: RoundedRectangle {
    // ~radius 5 on the 20pt mark (library-v2 §1) — `small` token is 6.
    RoundedRectangle(cornerRadius: BrandMetrics.Radius.small - 1, style: .continuous)
  }

  var body: some View {
    glyph
      .foregroundStyle(accent)
      .frame(width: size, height: size)
      .background(
        shape.fill(accent.opacity(BrandMetrics.Control.tintedFillOpacity))
      )
      .overlay(
        shape.strokeBorder(accent.opacity(0.4), lineWidth: 1)
      )
      .accessibilityLabel("Extracted by \(provider)")
      .help("Extracted by \(provider)")
  }

  @ViewBuilder
  private var glyph: some View {
    if let icon = ProviderIcon.resolve(for: provider),
       let image = ProviderIconLoader.image(for: icon) {
      Image(nsImage: image)
        .resizable()
        .renderingMode(.template)
        .aspectRatio(contentMode: .fit)
        .frame(
          width: size - Self.glyphInset * 2,
          height: size - Self.glyphInset * 2
        )
    } else {
      Text(letterGlyph)
        .font(BrandTypography.caption.weight(.bold))
    }
  }

  private var letterGlyph: String {
    guard let first = provider.trimmingCharacters(in: .whitespaces).first else {
      return "·"
    }
    return String(first).uppercased()
  }
}

// MARK: - Previews

#Preview("ProviderMark") {
  HStack(spacing: BrandMetrics.Spacing.lg) {
    ProviderMark(provider: "anthropic")
    ProviderMark(provider: "openai")
    ProviderMark(provider: "ollama")
    ProviderMark(provider: "google")
  }
  .padding(BrandMetrics.Spacing.xl)
  .background(BrandColors.backgroundElevated)
  .preferredColorScheme(.dark)
}
