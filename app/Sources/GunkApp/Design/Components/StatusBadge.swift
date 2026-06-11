import SwiftUI

/// A tinted capsule badge for statuses (verification results, approval state,
/// confidence). Replaces the inline status capsules in `BrowseView`'s
/// `statusRow` and `pill`.
struct StatusBadge: View {
  enum Variant {
    case success
    case warning
    case danger
    case neutral

    var color: Color {
      switch self {
      case .success: return BrandColors.success
      case .warning: return BrandColors.warning
      case .danger: return BrandColors.danger
      case .neutral: return BrandColors.textSecondary
      }
    }
  }

  let label: String
  var variant: Variant = .neutral
  var systemImage: String?

  init(_ label: String, variant: Variant = .neutral, systemImage: String? = nil) {
    self.label = label
    self.variant = variant
    self.systemImage = systemImage
  }

  var body: some View {
    HStack(spacing: BrandMetrics.Spacing.xs) {
      if let systemImage {
        Image(systemName: systemImage)
          .font(BrandTypography.caption)
      }
      Text(label)
        .font(BrandTypography.callout)
        .lineLimit(1)
    }
    .foregroundStyle(variant.color)
    .padding(.horizontal, BrandMetrics.Spacing.sm)
    .padding(.vertical, BrandMetrics.Spacing.xs)
    .background(
      Capsule().fill(variant.color.opacity(BrandMetrics.Control.tintedFillOpacity))
    )
  }
}

// MARK: - Previews

private struct StatusBadgePreview: View {
  var body: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        StatusBadge("Passed", variant: .success, systemImage: "checkmark.circle")
        StatusBadge("Needs attention", variant: .warning, systemImage: "exclamationmark.triangle")
        StatusBadge("Failed", variant: .danger, systemImage: "xmark.circle")
        StatusBadge("Not verified", variant: .neutral, systemImage: "questionmark.circle")
      }
      HStack(spacing: BrandMetrics.Spacing.sm) {
        StatusBadge("Approved", variant: .success)
        StatusBadge("Pending", variant: .neutral)
        StatusBadge("Skipped", variant: .neutral)
        StatusBadge("92%", variant: .success)
      }
    }
    .padding(BrandMetrics.Spacing.xl)
    .background(BrandColors.backgroundPrimary)
  }
}

#Preview("StatusBadge — dark") {
  StatusBadgePreview()
    .preferredColorScheme(.dark)
}

#Preview("StatusBadge — light") {
  StatusBadgePreview()
    .preferredColorScheme(.light)
}
