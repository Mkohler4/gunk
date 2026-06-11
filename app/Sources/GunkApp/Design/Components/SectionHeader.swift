import SwiftUI

/// A branded section heading with an optional accent-tinted glyph. Replaces
/// `DetailSectionHeader` in `BrowseView`'s detail pane.
struct SectionHeader: View {
  let title: String
  var systemImage: String?

  init(_ title: String, systemImage: String? = nil) {
    self.title = title
    self.systemImage = systemImage
  }

  var body: some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      if let systemImage {
        Image(systemName: systemImage)
          .font(BrandTypography.headline)
          .foregroundStyle(BrandColors.accent)
      }
      Text(title)
        .font(BrandTypography.headline)
        .foregroundStyle(BrandColors.textPrimary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

// MARK: - Previews

private struct SectionHeaderPreview: View {
  var body: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
      SectionHeader("Runability", systemImage: "checkmark.seal")
      SectionHeader("Bundle path", systemImage: "folder")
      SectionHeader("Owned files", systemImage: "doc.text")
      SectionHeader("No glyph")
    }
    .padding(BrandMetrics.Spacing.xl)
    .background(BrandColors.backgroundPrimary)
  }
}

#Preview("SectionHeader — dark") {
  SectionHeaderPreview()
    .preferredColorScheme(.dark)
}

#Preview("SectionHeader — light") {
  SectionHeaderPreview()
    .preferredColorScheme(.light)
}
