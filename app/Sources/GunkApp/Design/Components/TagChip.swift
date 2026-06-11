import SwiftUI

/// A small capsule chip for module tags. Replaces the inline capsules in
/// `BrowseView`'s `tagRow` (which render a plain tag string).
struct TagChip: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(BrandTypography.caption)
      .foregroundStyle(BrandColors.textSecondary)
      .lineLimit(1)
      .padding(.horizontal, BrandMetrics.Spacing.sm)
      .padding(.vertical, BrandMetrics.Spacing.xs)
      .background(
        Capsule().fill(
          BrandColors.textSecondary.opacity(BrandMetrics.Control.tintedFillOpacity)
        )
      )
      .overlay(
        Capsule().strokeBorder(BrandColors.separator)
      )
  }
}

// MARK: - Previews

private struct TagChipPreview: View {
  var body: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
      HStack(spacing: BrandMetrics.Spacing.xs) {
        TagChip("auth")
        TagChip("payments")
        TagChip("mobile")
        TagChip("api-client")
      }
      HStack(spacing: BrandMetrics.Spacing.xs) {
        TagChip("untagged")
        TagChip("a-very-long-tag-name-that-truncates")
          .frame(maxWidth: 160)
      }
    }
    .padding(BrandMetrics.Spacing.xl)
    .background(BrandColors.backgroundPrimary)
  }
}

#Preview("TagChip — dark") {
  TagChipPreview()
    .preferredColorScheme(.dark)
}

#Preview("TagChip — light") {
  TagChipPreview()
    .preferredColorScheme(.light)
}
