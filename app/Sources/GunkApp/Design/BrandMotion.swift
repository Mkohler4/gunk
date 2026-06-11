import AppKit
import SwiftUI

/// Named motion tokens for the gunk brand. Views must use these — never
/// inline `Animation` values or magic durations.
///
/// All timing comes from the approved "Gunk Birth" animation spec:
/// breathe 3.4s, blink every 5s for 0.34s, hop 0.62s, birth 3.6s + 1.9s idle.
enum BrandMotion {
  // MARK: Interaction animations

  /// Hover/press feedback (concept buttons use 0.15s transitions).
  static let quick = Animation.easeOut(duration: 0.15)
  /// Default UI state changes.
  static let standard = Animation.easeInOut(duration: 0.25)
  /// Surface enter/exit, layout shifts.
  static let smooth = Animation.easeInOut(duration: 0.4)
  /// Playful overshoot used when something "lands" (ease-out-back analog,
  /// c1 = 1.70158 in the spec).
  static let settle = Animation.spring(response: 0.45, dampingFraction: 0.62)
  /// The mascot's hop (0.62s ease in the spec).
  static let hop = Animation.easeInOut(duration: Mascot.hopDuration)

  // MARK: Mascot idle spec

  /// Idle "alive" loop constants for `BrandMark` and downstream loaders.
  enum Mascot {
    /// One full breathe cycle.
    static let breatheDuration: TimeInterval = 3.4
    /// Vertical scale amplitude while breathing (+2.8% / −2.2% horizontal).
    static let breatheScaleY: CGFloat = 0.028
    static let breatheScaleX: CGFloat = 0.022
    /// Upward lift at the top of a breath, in design units (100pt canvas).
    static let breatheLift: CGFloat = 0.6
    /// A blink happens once per cycle…
    static let blinkCycle: TimeInterval = 5.0
    /// …and lasts this long.
    static let blinkDuration: TimeInterval = 0.34
    /// Eyes never fully vanish mid-blink.
    static let blinkMinimum: CGFloat = 0.08
    static let hopDuration: TimeInterval = 0.62
  }

  // MARK: Birth sequence spec

  /// "Born from the goo" launch/loading sequence constants. The full
  /// metaball rise is implemented where the launch view needs it (T-7.5+);
  /// these tokens are the single source for its timing.
  enum Birth {
    static let duration: TimeInterval = 3.6
    /// Idle time shown after the birth before a loop restarts.
    static let idleTail: TimeInterval = 1.9
    /// Phase breakpoints as fractions of `duration`.
    static let stirring: Double = 0.16
    static let rising: Double = 0.32
    static let pinch: Double = 0.60
    static let forming: Double = 0.72
    static let alive: Double = 0.94
    /// Eyes pop open with overshoot during this window.
    static let eyesOpenStart: Double = 0.74
    static let eyesOpenEnd: Double = 0.92
  }

  /// Honors the system Reduce Motion setting; idle loops and the birth
  /// sequence must render their final frame instead of animating.
  static var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }
}

#Preview("Motion tokens") {
  BrandMotionPreview()
    .preferredColorScheme(.dark)
}

struct BrandMotionPreview: View {
  @State private var toggled = false

  private let tokens: [(String, Animation)] = [
    ("quick", BrandMotion.quick),
    ("standard", BrandMotion.standard),
    ("smooth", BrandMotion.smooth),
    ("settle", BrandMotion.settle),
    ("hop", BrandMotion.hop),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
      ForEach(tokens, id: \.0) { name, animation in
        HStack(spacing: BrandMetrics.Spacing.lg) {
          Text(name)
            .font(BrandTypography.mono)
            .foregroundStyle(BrandColors.textSecondary)
            .frame(width: 80, alignment: .trailing)
          Circle()
            .fill(BrandColors.accent)
            .frame(width: 18, height: 18)
            .offset(x: toggled ? 160 : 0)
            .animation(animation, value: toggled)
        }
      }
      Button(toggled ? "Reset" : "Play") {
        toggled.toggle()
      }
      .font(BrandTypography.callout)
    }
    .padding(BrandMetrics.Spacing.xl)
    .frame(width: 360, alignment: .leading)
    .background(BrandColors.backgroundPrimary)
  }
}
