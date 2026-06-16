import SwiftUI

/// The brand's adaptive glass surface.
///
/// On macOS 26 (built with the Xcode 26 toolchain) this applies the real
/// Liquid Glass `glassEffect`. On older systems — or when built with an older
/// SDK — it falls back to a layered `.ultraThinMaterial` treatment tuned to
/// look intentional: blur, brand tint, top sheen, hairline stroke, and a soft
/// shadow, all driven by `BrandMetrics.Glass`.
///
/// The `#if compiler(>=6.2)` guard exists because `glassEffect` only exists
/// in the macOS 26 SDK; the branch starts compiling automatically once the
/// Xcode 26 toolchain is installed (T-7.1).
struct GlassMaterial: ViewModifier {
  var cornerRadius: CGFloat = BrandMetrics.Radius.large
  var elevated: Bool = true

  func body(content: Content) -> some View {
    #if compiler(>=6.2)
      if #available(macOS 26.0, *) {
        content
          .glassEffect(
            .regular.tint(BrandColors.surfaceGlass.opacity(BrandMetrics.Glass.tintOpacity)),
            in: .rect(cornerRadius: cornerRadius)
          )
          .overlay(innerTopHighlight)
          .shadow(
            color: .black.opacity(elevated ? BrandMetrics.Glass.shadowOpacity : 0),
            radius: BrandMetrics.Glass.shadowRadius,
            y: BrandMetrics.Glass.shadowYOffset
          )
      } else {
        fallback(content: content)
      }
    #else
      fallback(content: content)
    #endif
  }

  /// The toolbox-v2 glass `inset 0 1px 0 rgba(255,255,255,0.10)`: a crisp
  /// 1pt highlight hugging the inside of the top edge, clipped by the shape
  /// so it fades out through the corner curves.
  private var innerTopHighlight: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(.clear)
      .overlay(alignment: .top) {
        Rectangle()
          .fill(.white.opacity(BrandMetrics.Glass.innerTopHighlightOpacity))
          .frame(height: 1)
      }
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .allowsHitTesting(false)
  }

  private func fallback(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    return content
      .background {
        ZStack {
          shape.fill(.ultraThinMaterial)
          shape.fill(BrandColors.surfaceGlass.opacity(BrandMetrics.Glass.tintOpacity))
          shape.fill(
            LinearGradient(
              colors: [
                .white.opacity(BrandMetrics.Glass.sheenOpacity),
                .white.opacity(0),
              ],
              startPoint: .top,
              endPoint: UnitPoint(x: 0.5, y: 0.46)
            )
          )
        }
      }
      .overlay(
        shape.strokeBorder(.white.opacity(BrandMetrics.Glass.strokeOpacity))
      )
      .overlay(innerTopHighlight)
      .clipShape(shape)
      .shadow(
        color: .black.opacity(elevated ? BrandMetrics.Glass.shadowOpacity : 0),
        radius: BrandMetrics.Glass.shadowRadius,
        y: BrandMetrics.Glass.shadowYOffset
      )
  }
}

extension View {
  /// Applies the brand's adaptive glass surface (see `GlassMaterial`).
  func brandGlass(
    cornerRadius: CGFloat = BrandMetrics.Radius.large,
    elevated: Bool = true
  ) -> some View {
    modifier(GlassMaterial(cornerRadius: cornerRadius, elevated: elevated))
  }

  /// A full-bleed glass *header* strip — the soft, edge-to-edge counterpart to
  /// `brandGlass`'s floating card. No rounded box, no stroke, no drop shadow,
  /// and no separating hairline: just blurred brand glass fused to the top of
  /// the page so scrolled content reads through it. This is the "glass
  /// neomorphic" header treatment (vs. the old-school bordered bar).
  func headerGlass() -> some View {
    modifier(HeaderGlassMaterial())
  }
}

/// See `View.headerGlass()`. Kept separate from `GlassMaterial` because a
/// header has none of the card chrome (corner radius, border, sheen, shadow)
/// — those are exactly the "box / separating line" the design rejects.
private struct HeaderGlassMaterial: ViewModifier {
  func body(content: Content) -> some View {
    #if compiler(>=6.2)
      if #available(macOS 26.0, *) {
        content
          .background(.clear)
          .glassEffect(
            .regular.tint(BrandColors.surfaceGlass.opacity(BrandMetrics.Glass.tintOpacity)),
            in: .rect(cornerRadius: 0)
          )
      } else {
        fallback(content: content)
      }
    #else
      fallback(content: content)
    #endif
  }

  private func fallback(content: Content) -> some View {
    content.background {
      ZStack {
        Rectangle().fill(.ultraThinMaterial)
        Rectangle().fill(BrandColors.surfaceGlass.opacity(BrandMetrics.Glass.tintOpacity))
      }
      .ignoresSafeArea()
    }
  }
}

#Preview("Glass material") {
  ZStack {
    LinearGradient(
      colors: [BrandColors.accent.opacity(0.5), BrandColors.backgroundPrimary],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    VStack(spacing: BrandMetrics.Spacing.lg) {
      Text("Liquid Glass surface")
        .font(BrandTypography.headline)
        .foregroundStyle(BrandColors.textPrimary)
        .padding(BrandMetrics.Spacing.xl)
        .brandGlass()
      Text("Flat (not elevated)")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.textSecondary)
        .padding(BrandMetrics.Spacing.lg)
        .brandGlass(cornerRadius: BrandMetrics.Radius.medium, elevated: false)
    }
  }
  .frame(width: 420, height: 320)
  .preferredColorScheme(.dark)
}
