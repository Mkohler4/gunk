import AppKit
import SwiftUI

/// Semantic color tokens for the gunk brand. Views must use these tokens —
/// never raw `Color` literals — so the palette can be retuned in one place.
///
/// Dark values are the exact toolbox-v2 tokens read from
/// `docs/design/explorations/toolbox-v2-library.html` (`:root`): neutral
/// graphite surfaces, green reserved for meaning. Light values are derived to
/// keep the same elevation ramp legible in light appearance.
enum BrandColors {
  // MARK: Surfaces

  /// Window / deepest background. Dark: mockup `--bg`.
  static let backgroundPrimary = token(
    "BrandBackgroundPrimary",
    light: 0xEFEFF1,
    dark: 0x161618
  )

  /// The content scrolling surface behind cards. Dark: mockup `--bg-2`.
  static let backgroundSecondary = token(
    "BrandBackgroundSecondary",
    light: 0xF5F5F7,
    dark: 0x1D1D20
  )

  /// Raised panels and cards. Dark: mockup `--surface`.
  static let backgroundElevated = token(
    "BrandBackgroundElevated",
    light: 0xFFFFFF,
    dark: 0x27272B
  )

  /// Card hover step above `backgroundElevated`. Dark: mockup `--surface-hi`.
  static let backgroundElevatedHover = token(
    "BrandBackgroundElevatedHover",
    light: 0xF4F4F6,
    dark: 0x303036
  )

  /// Tint laid over blur/glass. Dark: mockup `--glass-tint` base color —
  /// `GlassMaterial` applies it at `BrandMetrics.Glass.tintOpacity` (0.55)
  /// to produce the mockup's `rgba(48,48,54,0.55)`.
  static let surfaceGlass = token(
    "BrandSurfaceGlass",
    light: 0xF0F0F2,
    dark: 0x303036
  )

  // MARK: Accent

  /// Primary brand green. Dark: mockup `--green` (unchanged from Ooze).
  static let accent = token(
    "BrandAccent",
    light: 0x3BBF6E, // darker for light-mode contrast
    dark: 0x5FE08C
  )

  /// Pressed/secondary accent. Dark: mockup `--green-d`.
  static let accentSecondary = token(
    "BrandAccentSecondary",
    light: 0x2DA35C,
    dark: 0x36B566
  )

  // MARK: Text

  /// Dark: mockup `--text`.
  static let textPrimary = token(
    "BrandTextPrimary",
    light: 0x1B1B1E,
    dark: 0xF3F3F5
  )

  /// Dark: mockup `--muted`.
  static let textSecondary = token(
    "BrandTextSecondary",
    light: 0x5E5E66,
    dark: 0x9B9BA2
  )

  /// Dark: mockup `--faint`.
  static let textTertiary = token(
    "BrandTextTertiary",
    light: 0x8A8A92,
    dark: 0x6C6C74
  )

  // MARK: Status

  static let success = token(
    "BrandSuccess",
    light: 0x2DA35C,
    dark: 0x4CD07F
  )

  /// Dark: mockup `--amber` (needs-attention only).
  static let warning = token(
    "BrandWarning",
    light: 0xB5832D,
    dark: 0xE7B765
  )

  /// Dark: mockup `--red` (failed only).
  static let danger = token(
    "BrandDanger",
    light: 0xC04B3E,
    dark: 0xE5786A
  )

  // MARK: Lines

  /// Hairlines and dividers. Dark: mockup `--line` `rgba(255,255,255,0.07)`;
  /// light: equivalent black hairline. Lean on elevation, not strokes.
  static let separator = token(
    "BrandSeparator",
    light: 0x000000,
    lightAlpha: 0.10,
    dark: 0xFFFFFF,
    darkAlpha: 0.07
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

  // MARK: Provider-accent art colors (appearance-invariant)

  /// Fixed art colors keyed to the model provider that extracted a module
  /// (the toolbox-v2 corner badges). Like `Mark`, these are art values, not
  /// semantic tokens, and render identically in light and dark.
  enum Provider {
    static let anthropic = Color(hex: 0xD26D43)
    static let openAI = Color(hex: 0x639FA9)
    static let google = Color(hex: 0x33508A)
    /// Ollama / unknown providers.
    static let neutral = Color(hex: 0x8A8A92)
  }

  /// Resolves a `RunTrace.provider` string (case-insensitive) to its badge
  /// art color. Ollama and unrecognized providers get the neutral fallback.
  static func providerAccent(for provider: String) -> Color {
    let normalized = provider.lowercased()
    if normalized.contains("anthropic") || normalized.contains("claude") {
      return Provider.anthropic
    }
    if normalized.contains("openai") || normalized.contains("gpt") {
      return Provider.openAI
    }
    if normalized.contains("google") || normalized.contains("gemini") {
      return Provider.google
    }
    return Provider.neutral
  }

  // MARK: Resolution

  /// Prefers the named color set in `Assets.xcassets` (used when the catalog
  /// is compiled into the bundle). The SwiftPM build copies the catalog as a
  /// raw folder, so named lookup fails there and we fall back to a dynamic
  /// color built from the same values.
  private static func token(
    _ name: String,
    light: UInt32,
    lightAlpha: CGFloat = 1,
    dark: UInt32,
    darkAlpha: CGFloat = 1
  ) -> Color {
    if let asset = NSColor(named: name, bundle: .module) {
      return Color(nsColor: asset)
    }
    let dynamic = NSColor(name: NSColor.Name(name)) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return isDark
        ? NSColor(srgbHex: dark, alpha: darkAlpha)
        : NSColor(srgbHex: light, alpha: lightAlpha)
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
  convenience init(srgbHex hex: UInt32, alpha: CGFloat = 1) {
    self.init(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: alpha
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
    ("backgroundSecondary", BrandColors.backgroundSecondary),
    ("backgroundElevated", BrandColors.backgroundElevated),
    ("backgroundElevatedHover", BrandColors.backgroundElevatedHover),
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
    ("provider.anthropic", BrandColors.Provider.anthropic),
    ("provider.openAI", BrandColors.Provider.openAI),
    ("provider.google", BrandColors.Provider.google),
    ("provider.neutral", BrandColors.Provider.neutral),
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
