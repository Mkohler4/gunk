import AppKit
import SwiftUI

/// One-click MCP setup (T-8.10, CP-C): the payoff surface for the warning
/// chip and every other needs-setup affordance. Lists each supported AI
/// client with its live status and a Connect button; errors surface the
/// configurator's abort message verbatim with an open-config affordance —
/// nothing is ever silently overwritten. Content sits on solid surfaces;
/// only the sheet container is system chrome.
@MainActor
struct MCPSetupView: View {
  @ObservedObject var model: MCPSetupModel
  var onClose: () -> Void = {}
  /// Injected so previews/tests don't launch external editors. The default
  /// opens the config in its registered editor — the refining-loop
  /// affordance for diagnosing a malformed config.
  var openConfig: (URL) -> Void = { NSWorkspace.shared.open($0) }

  var body: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
      header

      VStack(spacing: BrandMetrics.Spacing.sm) {
        ForEach(model.rows) { row in
          clientRow(row)
        }
      }

      footer
    }
    .padding(BrandMetrics.Spacing.lg)
    .frame(minWidth: 480, idealWidth: 520)
    .background(BrandColors.backgroundPrimary)
    .onAppear {
      model.refresh()
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(alignment: .top, spacing: BrandMetrics.Spacing.sm) {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        Text("Connect your agent")
          .font(BrandTypography.headline)
          .foregroundStyle(BrandColors.textPrimary)

        // The one-line payoff (task copy): why wiring MCP matters.
        Text("Your agent can use every Agent-ready module in your library.")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
      }

      Spacer(minLength: BrandMetrics.Spacing.sm)

      Button("Done", action: onClose)
        .buttonStyle(.brandSecondary)
    }
  }

  // MARK: Client rows

  private func clientRow(_ row: MCPSetupModel.ClientRow) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs / 2) {
          Text(row.client.displayName)
            .font(BrandTypography.body.weight(.medium))
            .foregroundStyle(
              row.displayStatus == .notDetected
                ? BrandColors.textSecondary
                : BrandColors.textPrimary
            )

          Text(row.configURL.path)
            .font(BrandTypography.caption.monospaced())
            .foregroundStyle(BrandColors.textSecondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        Spacer(minLength: BrandMetrics.Spacing.sm)

        statusBadge(row.displayStatus)

        if row.isConnectable {
          Button("Connect") {
            withAnimation(BrandMotion.standard) {
              model.connect(row.client)
            }
          }
          .buttonStyle(.brandSecondary)
          .help("Add gunk to \(row.client.displayName)'s MCP config")
        }
      }

      if let error = row.actionError {
        errorLine(error, configURL: row.configURL)
      }
    }
    .padding(BrandMetrics.Spacing.sm)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(BrandColors.backgroundElevated)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(row.client.displayName): \(row.displayStatus.label)")
  }

  @ViewBuilder
  private func statusBadge(_ status: MCPSetupModel.DisplayStatus) -> some View {
    switch status {
    case .connected:
      // Accent green on the meaningful state only: the agent is wired in.
      StatusBadge("Connected", variant: .success, systemImage: "checkmark.circle")
    case .notSetUp:
      StatusBadge("Not set up", variant: .warning, systemImage: "exclamationmark.triangle")
    case .notDetected:
      StatusBadge("Not detected", variant: .neutral, systemImage: "circle.dashed")
    case .problem:
      StatusBadge("Problem", variant: .danger, systemImage: "xmark.circle")
    }
  }

  /// The configurator's abort message, verbatim, plus the way out: open the
  /// config the writer refused to touch.
  private func errorLine(_ message: String, configURL: URL) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.sm) {
      Text(message)
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.danger)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)

      Spacer(minLength: BrandMetrics.Spacing.sm)

      Button("Open config") {
        openConfig(configURL)
      }
      .buttonStyle(.brandSecondary)
      .help("Open \(configURL.path)")
    }
  }

  // MARK: Footer

  @ViewBuilder
  private var footer: some View {
    let targets = model.connectAllTargets
    if targets.count >= 2 {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        Spacer(minLength: 0)

        Button("Connect all") {
          withAnimation(BrandMotion.standard) {
            model.connectAll()
          }
        }
        .buttonStyle(.brandPrimary)
        .help("Add gunk to \(targets.map(\.displayName).joined(separator: ", "))")
      }
    }
  }
}
