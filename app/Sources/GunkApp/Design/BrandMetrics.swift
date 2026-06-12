import SwiftUI

/// Spacing, radius, and glass constants for the gunk brand. Views must use
/// these tokens — never magic numbers.
enum BrandMetrics {
  /// Spacing scale, derived from the concept boards' rhythm.
  enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 20
    static let xl: CGFloat = 32
  }

  /// Corner radii. Concept boards use 11px controls, 18px cards, 24px shells.
  enum Radius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 11
    static let large: CGFloat = 18
    /// Shell-scale surfaces — the toolbox-v2 window and `.dropcard` radius.
    static let xl: CGFloat = 24
    static let pill: CGFloat = 999
  }

  /// Constants for the adaptive glass material (see `GlassMaterial`).
  enum Glass {
    /// Opacity of the `surfaceGlass` tint laid over the blur.
    static let tintOpacity: Double = 0.55
    /// Inner hairline stroke, from the toolbox-v2 glass border
    /// `rgba(255,255,255,0.09)`.
    static let strokeOpacity: Double = 0.09
    /// Top-edge sheen gradient strength, from the concept's overlay.
    static let sheenOpacity: Double = 0.16
    /// Crisp 1pt inner top highlight, from the toolbox-v2 glass
    /// `inset 0 1px 0 rgba(255,255,255,0.10)`.
    static let innerTopHighlightOpacity: Double = 0.10
    /// Drop shadow under floating glass surfaces, mapped from the toolbox-v2
    /// glass `0 12px 40px -16px rgba(0,0,0,0.6)`: the -16px spread pulls the
    /// 40px CSS blur in to a ~24px visible falloff, which is a SwiftUI
    /// radius of 12 (visible extent ≈ 2 × radius).
    static let shadowOpacity: Double = 0.6
    static let shadowRadius: CGFloat = 12
    static let shadowYOffset: CGFloat = 12
  }

  /// Constants for interactive controls and tinted fills (see `BrandButton`,
  /// `TagChip`, `StatusBadge`).
  enum Control {
    /// Sheen laid over a control's fill on hover.
    static let hoverHighlightOpacity: Double = 0.12
    /// Scale applied while a control is pressed.
    static let pressedScale: CGFloat = 0.97
    /// Tinted fill behind chips, badges, and destructive controls.
    static let tintedFillOpacity: Double = 0.14
    /// Opacity of a disabled control.
    static let disabledOpacity: Double = 0.45
    /// Square hit target for icon-only buttons.
    static let iconButtonSize: CGFloat = 28
    /// Fixed slot for the model switcher's model-name label (T-8.8). Sized
    /// so the longest catalog name ("Claude Sonnet 4", ~96pt at
    /// callout-medium) fits untruncated with headroom; anything longer
    /// middle-truncates. Fixed (not just a cap) on purpose: a max-only
    /// frame is compressible, which let the appbar's single-row layout
    /// squeeze the name at the 960pt minimum instead of falling back to
    /// the two-row stack, and a compressible label means the chip resizes
    /// as models switch — the exact jump this token exists to prevent.
    static let modelLabelWidth: CGFloat = 112
  }

  /// Brand-mark sizing (see `BrandMark`). The face stays legible down to
  /// 16pt; below that the mark reads as a solid blob, which is intended.
  enum Mark {
    static let small: CGFloat = 16
    static let medium: CGFloat = 32
    static let large: CGFloat = 64
    static let hero: CGFloat = 128
    /// Outline width at the mark's native 100pt design size.
    static let outlineWidth: CGFloat = 3
  }
}
