import SwiftUI

/// The Sources list: glass row cards with a per-row status/outcome slot
/// (ux §3.1, D3/D4/D5) — processing progress, "N modules" affordance, or a
/// failure disclosed on the row itself.
struct GunkListView: View {
  let model: GunkListModel
  let processingModel: ProcessingModel
  /// Sources that just arrived (window drop or Dock drop) and should carry
  /// the brief arrival highlight (ux §4.4).
  let arrivedSourceIds: Set<Int64>
  let onShowModules: (Int64) -> Void

  var body: some View {
    Group {
      if model.sources.isEmpty {
        EmptyStateView(
          "No sources yet",
          message: "Drop a folder above, or onto the Dock icon."
        )
      } else {
        ScrollView {
          LazyVStack(spacing: BrandMetrics.Spacing.sm) {
            ForEach(model.sources) { source in
              SourceRow(
                source: source,
                status: status(for: source),
                isArrived: arrivedSourceIds.contains(source.id),
                onShowModules: { onShowModules(source.id) },
                onDelete: { model.delete(id: source.id) }
              )
            }
          }
          // Breathing room so the last card's shadow isn't clipped.
          .padding(.bottom, BrandMetrics.Spacing.sm)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func status(for source: Source) -> SourceRowStatus {
    if let progress = processingModel.progressBySource[source.id] {
      return .processing(progress: progress, found: processingModel.modulesFound)
    }

    if let error = processingModel.errorsBySource[source.id] {
      return .failed(error)
    }

    let count = model.moduleCountBySource[source.id] ?? 0
    return count > 0 ? .modules(count) : .empty
  }
}

// MARK: - Row

enum SourceRowStatus: Equatable {
  case processing(progress: Double, found: Int)
  case modules(Int)
  case failed(String)
  case empty
}

private struct SourceRow: View {
  let source: Source
  let status: SourceRowStatus
  let isArrived: Bool
  let onShowModules: () -> Void
  let onDelete: () -> Void

  var body: some View {
    GlassCard(
      padding: BrandMetrics.Spacing.md,
      cornerRadius: BrandMetrics.Radius.medium,
      elevated: false
    ) {
      HStack(alignment: .center, spacing: BrandMetrics.Spacing.md) {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
          Text(source.name)
            .font(BrandTypography.body.weight(.medium))
            .foregroundStyle(BrandColors.textPrimary)
            .lineLimit(1)

          Text(metadata)
            .font(BrandTypography.caption)
            .foregroundStyle(BrandColors.textSecondary)
            .lineLimit(1)
            .truncationMode(.middle)

          // D5: a source-level failure is disclosed on the affected row,
          // not as a floating caption above the list.
          if case .failed(let error) = status {
            Text(error)
              .font(BrandTypography.caption)
              .foregroundStyle(BrandColors.danger)
              .lineLimit(2)
              .textSelection(.enabled)
          }
        }

        Spacer(minLength: BrandMetrics.Spacing.sm)

        statusSlot

        Button(action: onDelete) {
          Image(systemName: "trash")
        }
        .buttonStyle(.brandIcon)
        .help("Remove \(source.name) from gunk")
        .accessibilityLabel("Remove \(source.name)")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .overlay {
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .strokeBorder(BrandColors.accent.opacity(isArrived ? 1 : 0))
        .allowsHitTesting(false)
    }
    .background {
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(BrandColors.accent.opacity(
          isArrived ? BrandMetrics.Control.tintedFillOpacity : 0
        ))
    }
    .animation(BrandMotion.smooth, value: isArrived)
  }

  private var metadata: String {
    let added = Date(timeIntervalSince1970: Double(source.droppedAt) / 1_000)
      .formatted(.relative(presentation: .named))
    return "\(source.path) · added \(added)"
  }

  @ViewBuilder
  private var statusSlot: some View {
    switch status {
    case .processing(let progress, let found):
      HStack(spacing: BrandMetrics.Spacing.sm) {
        ProgressView(value: progress)
          .progressViewStyle(.linear)
          .tint(BrandColors.accent)
          .frame(width: BrandMetrics.Mark.large)

        Text("\(Int(progress * 100))% · \(found) found")
          .font(BrandTypography.caption)
          .monospacedDigit()
          .foregroundStyle(BrandColors.textSecondary)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Processing, \(Int(progress * 100)) percent, \(found) modules found")

    case .modules(let count):
      // D3: the row's outcome doubles as navigation — straight to Modules
      // filtered to this source.
      Button(action: onShowModules) {
        HStack(spacing: BrandMetrics.Spacing.xs) {
          Text("\(count) module\(count == 1 ? "" : "s")")
            .monospacedDigit()
          Image(systemName: "chevron.forward")
            .font(BrandTypography.caption)
        }
      }
      .buttonStyle(.brandSecondary)
      .help("Show this source's modules")

    case .failed:
      StatusBadge("Failed", variant: .danger, systemImage: "xmark.circle")

    case .empty:
      Text("No modules")
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textTertiary)
    }
  }
}
