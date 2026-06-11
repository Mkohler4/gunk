import SwiftUI

/// The brand lockup: `BrandMark` + "gunk", sized from `BrandMetrics` and
/// `BrandTypography`. Two arrangements:
///
/// - `.sidebar` — compact horizontal lockup for the app shell's sidebar
///   header (mark `Mark.medium`, `title` type).
/// - `.hero` — stacked lockup for the launch view and full-bleed states
///   (mark `Mark.hero`, `display` type).
///
/// `revealOnAppear` plays the launch reveal using `BrandMotion.settle`;
/// Reduce Motion renders the final frame immediately.
struct BrandWordmark: View {
  enum Style {
    case sidebar
    case hero
  }

  var style: Style = .sidebar
  /// Plays the mark's idle loop (breathe + blink).
  var isAnimated: Bool = false
  /// Plays the reveal (settle-in) when the lockup first appears.
  var revealOnAppear: Bool = false

  @State private var revealed = false

  var body: some View {
    lockup
      .opacity(visible ? 1 : 0)
      .scaleEffect(visible ? 1 : 0.92, anchor: .center)
      .onAppear {
        guard revealOnAppear, !BrandMotion.reduceMotion else {
          revealed = true
          return
        }
        withAnimation(BrandMotion.settle) {
          revealed = true
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("gunk")
  }

  private var visible: Bool {
    !revealOnAppear || revealed
  }

  @ViewBuilder
  private var lockup: some View {
    switch style {
    case .sidebar:
      HStack(spacing: BrandMetrics.Spacing.sm) {
        BrandMark(size: BrandMetrics.Mark.medium, isAnimated: isAnimated)
        wordmarkText(BrandTypography.title)
      }
    case .hero:
      VStack(spacing: BrandMetrics.Spacing.md) {
        BrandMark(size: BrandMetrics.Mark.hero, isAnimated: isAnimated)
        wordmarkText(BrandTypography.display)
      }
    }
  }

  private func wordmarkText(_ font: Font) -> some View {
    Text("gunk")
      .font(font)
      .foregroundStyle(BrandColors.textPrimary)
  }
}

// MARK: - Previews

private struct BrandWordmarkPreview: View {
  var body: some View {
    VStack(spacing: BrandMetrics.Spacing.xl) {
      BrandWordmark(style: .hero, isAnimated: true)
      BrandWordmark(style: .sidebar)
    }
    .padding(BrandMetrics.Spacing.xl)
    .frame(width: 320)
    .background(BrandColors.backgroundPrimary)
  }
}

#Preview("BrandWordmark — dark") {
  BrandWordmarkPreview()
    .preferredColorScheme(.dark)
}

#Preview("BrandWordmark — light") {
  BrandWordmarkPreview()
    .preferredColorScheme(.light)
}
