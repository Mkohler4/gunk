import AppKit
import SwiftUI

/// Semantic color tokens for the gunk brand. Views must use these tokens —
/// never raw `Color` literals — so the palette can be retuned in one place.
///
/// Dark values come from the approved "Ooze" concept boards. Light values are
/// derived from the concept's light chips where available and are otherwise
/// `// BRAND-PLACEHOLDER` pending CP1 sign-off.
enum BrandColors {
  // MARK: Surfaces

  /// Window / deepest background. Dark: concept `--bg`.
  static let backgroundPrimary = token(
    "BrandBackgroundPrimary",
    light: 0xF4F6F4, // BRAND-PLACEHOLDER: derived light background
    dark: 0x0B0D0C
  )

  /// Raised panels and cards. Dark: concept `--panel`.
  static let backgroundElevated = token(
    "BrandBackgroundElevated",
    light: 0xFFFFFF, // BRAND-PLACEHOLDER: derived light elevated surface
    dark: 0x121613
  )

  /// Tint laid over blur/glass. Dark: concept `--panel-2`; light: concept chip.
  static let surfaceGlass = token(
    "BrandSurfaceGlass",
    light: 0xEEF1EE,
    dark: 0x171C18
  )

  // MARK: Accent

  /// Primary brand green. Dark: concept `--accent`.
  static let accent = token(
    "BrandAccent",
    light: 0x3BBF6E, // concept `--accent-2`, darker for light-mode contrast
    dark: 0x5FE08C
  )

  /// Pressed/secondary accent. Dark: concept `--accent-2`.
  static let accentSecondary = token(
    "BrandAccentSecondary",
    light: 0x2DA35C, // BRAND-PLACEHOLDER: derived deep green
    dark: 0x3BBF6E
  )

  // MARK: Text

  /// Dark: concept `--text`.
  static let textPrimary = token(
    "BrandTextPrimary",
    light: 0x1A201C, // BRAND-PLACEHOLDER: derived near-black green
    dark: 0xE9EDE9
  )

  /// Dark: concept `--muted`; light: concept light-chip text.
  static let textSecondary = token(
    "BrandTextSecondary",
    light: 0x5B645D,
    dark: 0x8B948D
  )

  /// Dark: concept `--faint`.
  static let textTertiary = token(
    "BrandTextTertiary",
    light: 0x8B948D,
    dark: 0x5B645D
  )

  // MARK: Status

  static let success = token(
    "BrandSuccess",
    light: 0x2DA35C, // BRAND-PLACEHOLDER: status greens pending CP1
    dark: 0x4CD07F // BRAND-PLACEHOLDER
  )

  static let warning = token(
    "BrandWarning",
    light: 0xB98A2E, // BRAND-PLACEHOLDER
    dark: 0xE0C25F // BRAND-PLACEHOLDER
  )

  static let danger = token(
    "BrandDanger",
    light: 0xC04B3E, // BRAND-PLACEHOLDER
    dark: 0xE0685F // BRAND-PLACEHOLDER
  )

  // MARK: Lines

  /// Hairlines and dividers. Dark: concept `--line`; light: concept chip border.
  static let separator = token(
    "BrandSeparator",
    light: 0xD7DDD7,
    dark: 0x262D28
  )

  // MARK: Brand-mark art colors (appearance-invariant)

  /// The Ooze renders identically in light and dark; these are fixed art
  /// values from the approved concept, not semantic tokens.
  enum Mark {
    static let gradientTop = Color(hex: 0xAEF4CA)
    static let gradientMid = Color(hex: 0x5FE08C)
    static let gradientBottom = Color(hex: 0x23914F)
    static let outline = Color(hex: 0x16703D)
    static let face = Color(hex: 0x11502D)
    /// App-icon tile gradient behind the mark.
    static let tileTop = Color(hex: 0x6EE79A)
    static let tileBottom = Color(hex: 0x34B463)
    /// Dark icon-tile gradient (menubar / loader treatment).
    static let darkTileTop = Color(hex: 0x161B18)
    static let darkTileBottom = Color(hex: 0x0C0F0D)
  }

  // MARK: Resolution

  /// Prefers the named color set in `Assets.xcassets` (used when the catalog
  /// is compiled into the bundle). The SwiftPM build copies the catalog as a
  /// raw folder, so named lookup fails there and we fall back to a dynamic
  /// color built from the same values.
  private static func token(_ name: String, light: UInt32, dark: UInt32) -> Color {
    if let asset = NSColor(named: name, bundle: .module) {
      return Color(nsColor: asset)
    }
    let dynamic = NSColor(name: NSColor.Name(name)) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return NSColor(srgbHex: isDark ? dark : light)
    }
    return Color(nsColor: dynamic)
  }
}

extension Color {
  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: opacity
    )
  }
}

extension NSColor {
  convenience init(srgbHex hex: UInt32) {
    self.init(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}

#Preview("Palette — dark") {
  BrandPaletteSwatches()
    .preferredColorScheme(.dark)
}

#Preview("Palette — light") {
  BrandPaletteSwatches()
    .preferredColorScheme(.light)
}

struct BrandPaletteSwatches: View {
  private let tokens: [(String, Color)] = [
    ("backgroundPrimary", BrandColors.backgroundPrimary),
    ("backgroundElevated", BrandColors.backgroundElevated),
    ("surfaceGlass", BrandColors.surfaceGlass),
    ("accent", BrandColors.accent),
    ("accentSecondary", BrandColors.accentSecondary),
    ("textPrimary", BrandColors.textPrimary),
    ("textSecondary", BrandColors.textSecondary),
    ("textTertiary", BrandColors.textTertiary),
    ("success", BrandColors.success),
    ("warning", BrandColors.warning),
    ("danger", BrandColors.danger),
    ("separator", BrandColors.separator),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      ForEach(tokens, id: \.0) { name, color in
        HStack(spacing: BrandMetrics.Spacing.md) {
          RoundedRectangle(cornerRadius: BrandMetrics.Radius.small)
            .fill(color)
            .frame(width: 56, height: 28)
            .overlay(
              RoundedRectangle(cornerRadius: BrandMetrics.Radius.small)
                .strokeBorder(BrandColors.separator)
            )
          Text(name)
            .font(BrandTypography.mono)
            .foregroundStyle(BrandColors.textSecondary)
        }
      }
    }
    .padding(BrandMetrics.Spacing.xl)
    .background(BrandColors.backgroundPrimary)
  }
}
