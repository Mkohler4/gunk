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
  /// Opens the run inspector pre-selected to this source's most recent run
  /// (T-8.6 entry point a).
  let onShowRuns: (Int64) -> Void

  /// Delete is destructive, so it routes through a confirmation
  /// (Phase 8: "no more one-click permanent deletes"). Held here so the
  /// confirmation copy lives next to the list it acts on.
  @State private var pendingDeletion: Source?

  var body: some View {
    Group {
      if model.sources.isEmpty {
        EmptyStateView(
          "No sources yet",
          message: "Drop a folder anywhere, or use Add folder."
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
                onShowRuns: { onShowRuns(source.id) },
                onDelete: { pendingDeletion = source }
              )
            }
          }
          // Breathing room so the last card's shadow isn't clipped.
          .padding(.bottom, BrandMetrics.Spacing.sm)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .confirmationDialog(
      pendingDeletion.map { "Remove \($0.name)?" } ?? "Remove source?",
      isPresented: confirmDeletionBinding,
      titleVisibility: .visible,
      presenting: pendingDeletion
    ) { source in
      Button("Remove source", role: .destructive) {
        model.delete(id: source.id)
      }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      // Matches the verified store behavior: `Store.removeSource(id:)` only
      // stamps `removed_at` on the source row; the source's gunks are left
      // intact (they're orphaned, not deleted).
      Text("Removes the source from gunk. Its modules remain until you delete them.")
    }
  }

  private var confirmDeletionBinding: Binding<Bool> {
    Binding(
      get: { pendingDeletion != nil },
      set: { presenting in
        if !presenting {
          pendingDeletion = nil
        }
      }
    )
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

// MARK: - Sources panel (sheet)

/// The sources surface, folded into the Library as a sheet (T-8.3). It reuses
/// `GunkListView` verbatim — the same status slot (processing progress,
/// "N modules" navigation, failed-with-error, delete-with-confirmation) — so
/// there is no second source-list implementation to keep in sync. Glass lives
/// on the sheet chrome; the rows and content sit on a solid surface.
@MainActor
struct SourcesPanelView: View {
  let sourceListModel: GunkListModel
  let processingModel: ProcessingModel
  /// Add folder shares the one true intake path (`DropZoneHandler`); the panel
  /// never duplicates insert/processing logic.
  let onAddFolder: () -> Void
  /// "N modules" closes the panel and applies the source filter on the grid.
  let onShowModules: (Int64) -> Void
  /// "View runs" closes the panel and opens the shell's run inspector at
  /// this source (T-8.6).
  let onShowRuns: (Int64) -> Void
  let onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        Text("Sources (\(sourceListModel.sources.count))")
          .font(BrandTypography.headline)
          .foregroundStyle(BrandColors.textPrimary)

        Spacer(minLength: BrandMetrics.Spacing.sm)

        Button(action: onAddFolder) {
          Label("Add folder", systemImage: "folder.badge.plus")
        }
        .buttonStyle(.brandSecondary)
        .help("Choose a folder to add to your library")

        Button("Done", action: onClose)
          .buttonStyle(.brandSecondary)
      }

      if let errorMessage = sourceListModel.errorMessage {
        Text(errorMessage)
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.danger)
          .textSelection(.enabled)
      }

      GunkListView(
        model: sourceListModel,
        processingModel: processingModel,
        // Arrival now lands on the module grid (T-8.3); the panel lists the
        // current sources without re-highlighting them.
        arrivedSourceIds: [],
        onShowModules: onShowModules,
        onShowRuns: onShowRuns
      )
    }
    .padding(BrandMetrics.Spacing.lg)
    .frame(minWidth: 460, idealWidth: 520, minHeight: 420, idealHeight: 520)
    .background(BrandColors.backgroundPrimary)
    .onAppear {
      sourceListModel.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .gunkInserted)) { _ in
      sourceListModel.refresh()
    }
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
  let onShowRuns: () -> Void
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

        Button(action: onShowRuns) {
          Image(systemName: "clock.arrow.circlepath")
        }
        .buttonStyle(.brandIcon)
        .help("View runs for \(source.name)")
        .accessibilityLabel("View runs for \(source.name)")

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
