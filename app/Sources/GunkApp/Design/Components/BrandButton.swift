import SwiftUI

/// The brand's button system. Apply with `.buttonStyle(.brandPrimary)`,
/// `.brandSecondary`, `.brandDestructive`, or `.brandIcon`.
///
/// Hover and press feedback animate with `BrandMotion.quick`; disabled
/// controls dim via `BrandMetrics.Control.disabledOpacity`.
struct BrandButtonStyle: ButtonStyle {
  enum Variant {
    /// Filled accent — the one main action on a surface.
    case primary
    /// Glass-tinted with a hairline — everything else.
    case secondary
    /// Danger-tinted — destructive actions.
    case destructive
    /// Square, chrome-free until hovered — toolbar/row glyph buttons.
    case icon
  }

  var variant: Variant

  func makeBody(configuration: Configuration) -> some View {
    BrandButtonBody(configuration: configuration, variant: variant)
  }
}

extension ButtonStyle where Self == BrandButtonStyle {
  static var brandPrimary: BrandButtonStyle { .init(variant: .primary) }
  static var brandSecondary: BrandButtonStyle { .init(variant: .secondary) }
  static var brandDestructive: BrandButtonStyle { .init(variant: .destructive) }
  static var brandIcon: BrandButtonStyle { .init(variant: .icon) }
}

private struct BrandButtonBody: View {
  let configuration: ButtonStyle.Configuration
  let variant: BrandButtonStyle.Variant

  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovering = false

  var body: some View {
    configuration.label
      .font(BrandTypography.callout)
      .foregroundStyle(foreground)
      .modifier(IconFrame(isIcon: variant == .icon))
      .padding(.horizontal, variant == .icon ? 0 : BrandMetrics.Spacing.md)
      .padding(.vertical, variant == .icon ? 0 : BrandMetrics.Spacing.sm)
      .background(shape.fill(fill))
      .overlay(shape.strokeBorder(stroke))
      .overlay(
        // Hover sheen, matching the glass material's white-overlay treatment.
        shape.fill(
          .white.opacity(
            isHovering && isEnabled ? BrandMetrics.Control.hoverHighlightOpacity : 0
          )
        )
      )
      .contentShape(shape)
      .scaleEffect(configuration.isPressed ? BrandMetrics.Control.pressedScale : 1)
      .opacity(isEnabled ? 1 : BrandMetrics.Control.disabledOpacity)
      .animation(BrandMotion.quick, value: isHovering)
      .animation(BrandMotion.quick, value: configuration.isPressed)
      .onHover { isHovering = $0 }
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(
      cornerRadius: variant == .icon ? BrandMetrics.Radius.small : BrandMetrics.Radius.medium,
      style: .continuous
    )
  }

  private var fill: Color {
    switch variant {
    case .primary:
      return configuration.isPressed ? BrandColors.accentSecondary : BrandColors.accent
    case .secondary:
      return BrandColors.surfaceGlass
    case .destructive:
      return BrandColors.danger.opacity(BrandMetrics.Control.tintedFillOpacity)
    case .icon:
      return isHovering && isEnabled ? BrandColors.surfaceGlass : .clear
    }
  }

  private var stroke: Color {
    switch variant {
    case .primary:
      return .clear
    case .secondary:
      return BrandColors.separator
    case .destructive:
      return BrandColors.danger.opacity(BrandMetrics.Control.tintedFillOpacity)
    case .icon:
      return .clear
    }
  }

  private var foreground: Color {
    switch variant {
    case .primary:
      // The background token inverts against the accent in both appearances:
      // near-black on the bright dark-mode green, near-white on the deeper
      // light-mode green.
      return BrandColors.backgroundPrimary
    case .secondary:
      return BrandColors.textPrimary
    case .destructive:
      return BrandColors.danger
    case .icon:
      return isHovering && isEnabled ? BrandColors.textPrimary : BrandColors.textSecondary
    }
  }
}

/// Gives icon-only buttons a fixed square hit target.
private struct IconFrame: ViewModifier {
  let isIcon: Bool

  func body(content: Content) -> some View {
    if isIcon {
      content.frame(
        width: BrandMetrics.Control.iconButtonSize,
        height: BrandMetrics.Control.iconButtonSize
      )
    } else {
      content
    }
  }
}

// MARK: - Previews

private struct BrandButtonPreview: View {
  var body: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
      HStack(spacing: BrandMetrics.Spacing.md) {
        Button("Approve module") {}
          .buttonStyle(.brandPrimary)
        Button("Re-run") {}
          .buttonStyle(.brandSecondary)
        Button("Delete") {}
          .buttonStyle(.brandDestructive)
        Button {} label: {
          Image(systemName: "folder")
        }
        .buttonStyle(.brandIcon)
        .help("Open bundle in Finder")
      }

      HStack(spacing: BrandMetrics.Spacing.md) {
        Button("Approve module") {}
          .buttonStyle(.brandPrimary)
        Button("Re-run") {}
          .buttonStyle(.brandSecondary)
        Button("Delete") {}
          .buttonStyle(.brandDestructive)
        Button {} label: {
          Image(systemName: "folder")
        }
        .buttonStyle(.brandIcon)
      }
      .disabled(true)

      HStack(spacing: BrandMetrics.Spacing.md) {
        Button {} label: {
          Label("Open in Finder", systemImage: "folder")
        }
        .buttonStyle(.brandSecondary)
        Button {} label: {
          Image(systemName: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.brandIcon)
        Button {} label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.brandIcon)
      }
    }
    .padding(BrandMetrics.Spacing.xl)
    .background(BrandColors.backgroundPrimary)
  }
}

#Preview("BrandButton — dark") {
  BrandButtonPreview()
    .preferredColorScheme(.dark)
}

#Preview("BrandButton — light") {
  BrandButtonPreview()
    .preferredColorScheme(.light)
}
