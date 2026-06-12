import SwiftUI

/// The toolbox-v2 provenance corner badge: a small rounded square color-keyed
/// to the model provider that extracted a module, with the provider's initial
/// as the glyph. Quiet and scannable — never a state signal.
struct ProviderBadge: View {
  let provider: String

  /// Mockup `.mbadge`: 19×19, radius 6, white glyph at ~95% on the
  /// provider-colored fill.
  private static let size: CGFloat = 19

  var body: some View {
    Text(glyph)
      .font(BrandTypography.caption.weight(.bold))
      .foregroundStyle(.white.opacity(0.95))
      .frame(width: Self.size, height: Self.size)
      .background(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.small, style: .continuous)
          .fill(BrandColors.providerAccent(for: provider))
      )
      .accessibilityLabel("Extracted by \(provider)")
      .help("Extracted by \(provider)")
  }

  private var glyph: String {
    guard let first = provider.trimmingCharacters(in: .whitespaces).first else {
      return "·"
    }

    return String(first).uppercased()
  }
}

// MARK: - Previews

#Preview("ProviderBadge") {
  HStack(spacing: BrandMetrics.Spacing.md) {
    ProviderBadge(provider: "anthropic")
    ProviderBadge(provider: "openai")
    ProviderBadge(provider: "google")
    ProviderBadge(provider: "ollama")
  }
  .padding(BrandMetrics.Spacing.xl)
  .background(BrandColors.backgroundElevated)
  .preferredColorScheme(.dark)
}
