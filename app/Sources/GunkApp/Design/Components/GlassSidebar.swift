import SwiftUI

/// The navigation container shell for the app's sidebar: a glass column with
/// a header slot (wordmark, T-7.5), a content slot (navigation rows), and an
/// optional footer slot (status, settings shortcut).
///
/// This is layout-agnostic about width — the app shell (T-7.6) owns the
/// sidebar's frame; this component owns its glass treatment and rhythm.
struct GlassSidebar<Header: View, Content: View, Footer: View>: View {
  @ViewBuilder var header: Header
  @ViewBuilder var content: Content
  @ViewBuilder var footer: Footer

  var body: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
      header

      content
        .frame(maxWidth: .infinity, alignment: .leading)

      Spacer(minLength: BrandMetrics.Spacing.sm)

      footer
    }
    .padding(BrandMetrics.Spacing.md)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    // The mockup sidebar shares the `.glass` treatment with the toolbar —
    // including its drop shadow — so it floats like the controls layer
    // instead of sitting flush (toolbox-v2-library.html `.glass`).
    .brandGlass(cornerRadius: BrandMetrics.Radius.large, elevated: true)
  }
}

extension GlassSidebar where Footer == EmptyView {
  init(
    @ViewBuilder header: () -> Header,
    @ViewBuilder content: () -> Content
  ) {
    self.init(header: header, content: content, footer: { EmptyView() })
  }
}

// MARK: - Previews

private struct GlassSidebarPreview: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [BrandColors.accent.opacity(0.4), BrandColors.backgroundPrimary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      GlassSidebar {
        HStack(spacing: BrandMetrics.Spacing.sm) {
          BrandMark(size: BrandMetrics.Mark.medium)
          Text("gunk")
            .font(BrandTypography.title)
            .foregroundStyle(BrandColors.textPrimary)
        }
      } content: {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
          ForEach(
            ["Sources", "Modules", "Runs", "Approval", "Settings"],
            id: \.self
          ) { item in
            Text(item)
              .font(BrandTypography.body)
              .foregroundStyle(
                item == "Modules" ? BrandColors.accent : BrandColors.textSecondary
              )
              .padding(.horizontal, BrandMetrics.Spacing.sm)
              .padding(.vertical, BrandMetrics.Spacing.xs)
          }
        }
      } footer: {
        Text("v0.7 · local store")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textTertiary)
      }
      .frame(width: 200)
      .padding(BrandMetrics.Spacing.lg)
    }
    .frame(width: 360, height: 380)
  }
}

#Preview("GlassSidebar — dark") {
  GlassSidebarPreview()
    .preferredColorScheme(.dark)
}

#Preview("GlassSidebar — light") {
  GlassSidebarPreview()
    .preferredColorScheme(.light)
}
