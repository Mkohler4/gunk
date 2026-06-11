import SwiftUI

/// The branded replacement for `ContentUnavailableView`: the Ooze (alive,
/// idle-breathing via `BrandMotion.Mascot`) above a title, an optional
/// message, and an optional actions row.
struct EmptyStateView<Actions: View>: View {
  let title: String
  var message: String?
  @ViewBuilder var actions: Actions

  init(
    _ title: String,
    message: String? = nil,
    @ViewBuilder actions: () -> Actions
  ) {
    self.title = title
    self.message = message
    self.actions = actions()
  }

  var body: some View {
    VStack(spacing: BrandMetrics.Spacing.md) {
      BrandMark(size: BrandMetrics.Mark.large, isAnimated: true)

      Text(title)
        .font(BrandTypography.headline)
        .foregroundStyle(BrandColors.textPrimary)

      if let message {
        Text(message)
          .font(BrandTypography.callout)
          .foregroundStyle(BrandColors.textSecondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 320)
      }

      actions
        .padding(.top, BrandMetrics.Spacing.xs)
    }
    .padding(BrandMetrics.Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

extension EmptyStateView where Actions == EmptyView {
  init(_ title: String, message: String? = nil) {
    self.init(title, message: message) { EmptyView() }
  }
}

// MARK: - Previews

private struct EmptyStateViewPreview: View {
  var body: some View {
    VStack(spacing: 0) {
      EmptyStateView(
        "No modules",
        message: "Drop a folder on the bin to decompose it into reusable modules."
      ) {
        Button("Add a source") {}
          .buttonStyle(.brandPrimary)
      }

      Divider()

      EmptyStateView(
        "Select a module",
        message: "Open a module to inspect its files, bundle, and runability signals."
      )
    }
    .frame(width: 420, height: 560)
    .background(BrandColors.backgroundPrimary)
  }
}

#Preview("EmptyStateView — dark") {
  EmptyStateViewPreview()
    .preferredColorScheme(.dark)
}

#Preview("EmptyStateView — light") {
  EmptyStateViewPreview()
    .preferredColorScheme(.light)
}
