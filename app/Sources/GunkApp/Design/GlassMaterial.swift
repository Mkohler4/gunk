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
