import AppKit
import SwiftUI

@MainActor
struct BrowseView: View {
  let model: BrowseModel
  /// Sources and intake now live in the Library (T-8.3): the source list folds
  /// into a sheet and folders are added through the one true intake path.
  let sourceListModel: GunkListModel
  let processingModel: ProcessingModel
  let dropZoneHandler: DropZoneHandler
  /// From the shared `MCPStatusProvider` (owned by the shell): when Cursor
  /// isn't wired up, the Agent-ready treatment flips to needs-setup copy
  /// that navigates to Settings (ux §4.5, D8).
  var mcpNeedsSetup = false
  var openBundle: (URL) -> Void = { NSWorkspace.shared.open($0) }
  var onShowSettings: () -> Void = {}
  /// Summons the shell-owned run inspector (T-8.6) from this view's entry
  /// points: a source row's "View runs" and the module detail's "Last run".
  var onShowRuns: (RunInspectorContext) -> Void = { _ in }

  @State private var selectedGunkId: Int64?
  @State private var showSourcesPanel = false

  /// Arrival highlight (ux §4.4), moved from the retired Sources surface to the
  /// module grid: modules created during a run carry the accent treatment for
  /// a beat after the run completes. Mirrors the old `arrivedSourceIds` decay.
  @State private var arrivedGunkIds: Set<Int64> = []
  @State private var gunkIdsBeforeRun: Set<Int64> = []
  @State private var arrivalDecayTasks: [Int64: Task<Void, Never>] = [:]

  /// How long a freshly created module keeps its highlight (ux §4.4).
  private static let arrivalHighlightLifetime: Duration = .seconds(2)

  /// Pane contract from ux §3.2/§4.6 (D10), relaxed for the 232pt mockup
  /// sidebar: browser ≥ 400, detail 300–440, and both must fit at the 960pt
  /// window minimum (960 − 232 = 728 ≥ 400 + 300 + spacing). The detail
  /// width is computed explicitly because HStack's own negotiation over two
  /// flexible panes can overshoot the proposal (it sizes the bounded detail
  /// pane before the browser clamps to its minimum), which cropped both
  /// edges at the minimum window size.
  private static let browserMinWidth: CGFloat = 400
  private static let detailMinWidth: CGFloat = 300
  private static let detailMaxWidth: CGFloat = 440

  /// Grid metrics from the toolbox-v2 mockup: `--card: 262px` min cell width,
  /// up to 3 columns. At the 960pt window minimum the browser pane is ~440pt,
  /// which resolves to a single column with the hero at full width (the
  /// mockup's own narrow reflow) — cells never shrink below `cardMinWidth`.
  private static let cardMinWidth: CGFloat = 262
  private static let gridGap: CGFloat = BrandMetrics.Spacing.md
  private static let maxColumns = 3
  /// Uniform row heights keep grid rows flush (cells stretch to the row).
  private static let standardRowHeight: CGFloat = 200
  private static let heroRowHeight: CGFloat = 256

  var body: some View {
    GeometryReader { proxy in
      // The resting "Select a module" placeholder is gone (T-8.3b follow-up
      // 1): with nothing selected the grid owns the full width. The inline
      // pane only appears for a selected module, and remains interim until
      // the module-detail surface is re-decided (module-run-v1 proposes a
      // full page; sheet-vs-page is Mark's call, Phase 10).
      let detail = selectedGunkId.flatMap { model.detail(for: $0) }
      let detailWidth = max(
        Self.detailMinWidth,
        min(
          Self.detailMaxWidth,
          proxy.size.width - Self.browserMinWidth - BrandMetrics.Spacing.md
        )
      )
      let browserWidth = detail == nil
        ? proxy.size.width
        : proxy.size.width - detailWidth - BrandMetrics.Spacing.md

      HStack(alignment: .top, spacing: BrandMetrics.Spacing.md) {
        browserPane(width: browserWidth)
          .frame(minWidth: Self.browserMinWidth, maxWidth: .infinity, maxHeight: .infinity)

        if let detail {
          detailPane(for: detail)
            .frame(width: detailWidth)
            .frame(maxHeight: .infinity)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .onAppear {
      // D12: run-completion freshness is handled by the shell, which calls
      // `BrowseModel.refresh()` when `isProcessing` flips false (T-7.6);
      // this refresh covers section re-entry.
      model.refresh()
      sourceListModel.refresh()
      synchronizeSelection()
      // Entering mid-run: snapshot what already exists so completion only
      // highlights what the run actually adds.
      if processingModel.isProcessing {
        gunkIdsBeforeRun = model.loadedGunkIds
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .gunkInserted)) { _ in
      model.refresh()
      sourceListModel.refresh()
    }
    .onChange(of: model.sections) {
      synchronizeSelection()
    }
    .onChange(of: processingModel.isProcessing) { wasProcessing, isProcessing in
      if !wasProcessing, isProcessing {
        gunkIdsBeforeRun = model.loadedGunkIds
      } else if wasProcessing, !isProcessing {
        // Reload so the run's new modules are loaded, then highlight only the
        // ids that weren't present when the run started.
        model.refresh()
        let added = model.loadedGunkIds.subtracting(gunkIdsBeforeRun)
        for gunkId in added {
          markArrived(gunkId)
        }
      }
    }
    .sheet(isPresented: $showSourcesPanel) {
      SourcesPanelView(
        sourceListModel: sourceListModel,
        processingModel: processingModel,
        onAddFolder: addFolder,
        onShowModules: { sourceId in
          showSourcesPanel = false
          model.filters.sourceId = sourceId
        },
        onShowRuns: { sourceId in
          // Hand off to the shell's inspector sheet; the panel closes first
          // so the two sheets never stack.
          showSourcesPanel = false
          onShowRuns(.source(sourceId))
        },
        onClose: { showSourcesPanel = false }
      )
    }
  }

  /// Arrival treatment (ux §4.4): the new cell carries the highlight, then it
  /// decays after a beat. Per-id decay tasks so overlapping arrivals don't
  /// cancel each other.
  private func markArrived(_ gunkId: Int64) {
    withAnimation(BrandMotion.settle) {
      _ = arrivedGunkIds.insert(gunkId)
    }

    arrivalDecayTasks[gunkId]?.cancel()
    arrivalDecayTasks[gunkId] = Task {
      try? await Task.sleep(for: Self.arrivalHighlightLifetime)
      guard !Task.isCancelled else {
        return
      }
      withAnimation(BrandMotion.smooth) {
        _ = arrivedGunkIds.remove(gunkId)
      }
      arrivalDecayTasks.removeValue(forKey: gunkId)
    }
  }

  /// Folder picker → the one true intake path. Never duplicates the insert /
  /// processing logic that lives in `DropZoneHandler`.
  private func addFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.prompt = "Add"
    panel.message = "Choose folders to add to your library"

    guard panel.runModal() == .OK, !panel.urls.isEmpty else {
      return
    }

    do {
      try dropZoneHandler.handleDrop(urls: panel.urls)
    } catch {
      NSApp.presentError(error)
    }
  }

  // MARK: Browser

  private func browserPane(width: CGFloat) -> some View {
    let contentWidth = width - 2 * BrandMetrics.Spacing.md
    let columns = max(
      1,
      min(Self.maxColumns, Int((contentWidth + Self.gridGap) / (Self.cardMinWidth + Self.gridGap)))
    )
    let cellWidth = (contentWidth - Self.gridGap * CGFloat(columns - 1)) / CGFloat(columns)

    return Group {
      if model.sections.isEmpty {
        emptyState
      } else {
        // Cards scroll beneath the floating glass controls layer (the
        // safe-area inset header below).
        ScrollView {
          LazyVStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
            ForEach(model.sections) { section in
              sectionView(section, columns: columns, cellWidth: cellWidth)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, BrandMetrics.Spacing.md)
          .padding(.bottom, BrandMetrics.Spacing.md)
          .padding(.top, BrandMetrics.Spacing.sm)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .safeAreaInset(edge: .top, spacing: BrandMetrics.Spacing.sm) {
      libraryHeader
        .padding(.horizontal, BrandMetrics.Spacing.md)
        .padding(.top, BrandMetrics.Spacing.sm)
    }
    // The content scrolling surface behind the cards (mockup `--bg-2`).
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous)
        .fill(BrandColors.backgroundSecondary)
    )
    .clipShape(RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous))
  }

  @ViewBuilder
  private var emptyState: some View {
    if model.totalModuleCount == 0 {
      // First-run (T-8.5): the content area itself is the add affordance —
      // a click-or-drag zone sharing the full-window drop overlay's visual
      // language, so the empty state *teaches* the drag gesture. Drag is
      // never the only door: the panel and its button both open the picker.
      LibraryIntakeZone(onAddFolder: addFolder)
    } else if model.filters.approval == .needsApproval, model.approvalQueue.isEmpty {
      // Cleared-queue state (T-8.4 refining loop): approving the last queued
      // module lands here, not on the generic no-matches state. The scope
      // chip is already gone (`showsScopeChip`); the button is the way out.
      EmptyStateView(
        "All caught up",
        message: "No modules are waiting for review."
      ) {
        Button {
          withAnimation(BrandMotion.standard) {
            model.filters.approval = .all
          }
        } label: {
          Label("Show all modules", systemImage: "square.grid.2x2")
        }
        .buttonStyle(.brandSecondary)
      }
    } else {
      EmptyStateView(
        "No matches",
        message: "No modules match the current search and filters."
      )
    }
  }

  // MARK: Header (the v2 controls layer — glass lives here only)

  /// The annotated-mockup appbar (T-8.3b follow-up 2): one row — `Library` +
  /// count, the `Project | Model` segmented, one long search field, then the
  /// actions. At the 960pt window minimum a single row can't hold a useful
  /// search width, so it falls back to the two-row stack instead of
  /// shrinking touch targets (T-8.3 refining loop).
  ///
  /// The source/tag/language/approval *filter* UI is intentionally absent —
  /// `BrowseModel`'s filter state stays intact, and the controls return
  /// layered inside the search bar once that design lands (`[HOLD FOR ME]`,
  /// see the T-8.3b follow-ups in the task doc).
  private var libraryHeader: some View {
    ViewThatFits(in: .horizontal) {
      singleRowHeader
      stackedHeader
    }
    // Regular-weight controls and md padding land the mockup `.toolbar`'s
    // 56pt presence — small controls read too thin against the cards.
    .padding(BrandMetrics.Spacing.md)
    .brandGlass(cornerRadius: BrandMetrics.Radius.medium, elevated: true)
  }

  /// Mockup `.search { max-width: 300px }` — the field must not run the
  /// whole appbar.
  private static let searchMaxWidth: CGFloat = 300

  private var singleRowHeader: some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      headerTitle
      groupPicker
      searchField
        .frame(minWidth: 160, maxWidth: Self.searchMaxWidth)

      Spacer(minLength: BrandMetrics.Spacing.sm)

      // Transient needs-approval scope chip (T-8.4): lives in the flexible
      // gap only while the scope is active — never a persistent filter UI.
      if showsScopeChip {
        needsApprovalScopeChip
      }

      sourcesButton
      modelSelector
    }
  }

  /// Narrow fallback: identity + model on top, grouping + search below.
  private var stackedHeader: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        headerTitle
        Spacer(minLength: BrandMetrics.Spacing.sm)
        sourcesButton
        modelSelector
      }

      HStack(spacing: BrandMetrics.Spacing.sm) {
        groupPicker
        searchField
          .frame(maxWidth: Self.searchMaxWidth)

        if showsScopeChip {
          needsApprovalScopeChip
        }
      }
    }
  }

  /// The sources panel's door. T-8.3 folded sources into the Library with
  /// the panel reachable "from the Library header", but the T-8.3b appbar
  /// slimming dropped the trigger — `showSourcesPanel` had no setter left.
  /// Restored here because T-8.6's "View runs" entry point lives on the
  /// panel's rows. A quiet icon in the actions cluster: not filter UI, so it
  /// doesn't violate the one-row appbar rule.
  private var sourcesButton: some View {
    Button {
      showSourcesPanel = true
    } label: {
      Image(systemName: "folder")
    }
    .buttonStyle(.brandIcon)
    .help("Sources (\(sourceListModel.sources.count))")
    .accessibilityLabel("Show sources, \(sourceListModel.sources.count) total")
  }

  /// The chip rides with the scope, not the grid: it disappears with the
  /// cleared-queue state (the empty grid already says "All caught up", and
  /// "Needs approval (0)" would be noise).
  private var showsScopeChip: Bool {
    model.filters.approval == .needsApproval && !model.approvalQueue.isEmpty
  }

  /// "Needs approval (N) ×" — clearable, amber-tinted (amber is the
  /// needs-attention color; this is scope state, not a control accent).
  /// Clearing restores the unscoped Library.
  private var needsApprovalScopeChip: some View {
    Button {
      withAnimation(BrandMotion.standard) {
        model.filters.approval = .all
      }
    } label: {
      HStack(spacing: BrandMetrics.Spacing.xs) {
        Text("Needs approval (\(model.approvalQueue.count))")
          .font(BrandTypography.callout.weight(.medium))
          .monospacedDigit()

        Image(systemName: "xmark")
          .font(BrandTypography.caption.weight(.semibold))
      }
      .foregroundStyle(BrandColors.warning)
      .lineLimit(1)
      .padding(.horizontal, BrandMetrics.Spacing.md)
      .padding(.vertical, BrandMetrics.Spacing.sm)
      .background(
        Capsule()
          .fill(BrandColors.warning.opacity(BrandMetrics.Control.tintedFillOpacity))
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .transition(.opacity)
    .help("Showing only modules that need approval — click to clear")
    .accessibilityLabel(
      "Scoped to \(model.approvalQueue.count) modules needing approval. Clear scope."
    )
  }

  private var headerTitle: some View {
    HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.sm) {
      Text("Library")
        .font(BrandTypography.headline)
        .foregroundStyle(BrandColors.textPrimary)

      // Plain muted count, no pill — the mockup's `.tb-title .count`.
      Text("\(model.totalModuleCount)")
        .font(BrandTypography.caption.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(BrandColors.textSecondary)
        .accessibilityLabel("\(model.totalModuleCount) modules in the library")
    }
  }

  /// Inset of the segment buttons inside their well (mockup `.seg`
  /// `padding: 2px`); the inner radius stays concentric with the well.
  private static let segmentInset: CGFloat = 2

  /// Custom-built segmented (mockup `.seg`, scaled to the appbar's weight —
  /// the system control reads too thin). Neutral graphite selection: green
  /// is meaning-only and a grouping toggle carries no meaning-state.
  private var groupPicker: some View {
    HStack(spacing: Self.segmentInset) {
      ForEach(BrowseGroup.allCases) { group in
        segmentButton(group)
      }
    }
    .padding(Self.segmentInset)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(BrandColors.textPrimary.opacity(BrandMetrics.Control.hoverHighlightOpacity / 2))
    )
    .overlay(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .strokeBorder(BrandColors.separator)
    )
    .help("Group the library by source project or by extracting model")
  }

  private func segmentButton(_ group: BrowseGroup) -> some View {
    let isSelected = model.filters.group == group
    return Button {
      model.filters.group = group
    } label: {
      Text(group.label)
        .font(BrandTypography.callout.weight(.medium))
        .foregroundStyle(isSelected ? BrandColors.textPrimary : BrandColors.textSecondary)
        .padding(.horizontal, BrandMetrics.Spacing.md)
        .padding(.vertical, BrandMetrics.Spacing.sm)
        .background(
          RoundedRectangle(
            cornerRadius: BrandMetrics.Radius.medium - Self.segmentInset,
            style: .continuous
          )
          .fill(
            isSelected
              ? BrandColors.textPrimary.opacity(BrandMetrics.Control.hoverHighlightOpacity)
              : .clear
          )
        )
        .contentShape(
          RoundedRectangle(
            cornerRadius: BrandMetrics.Radius.medium - Self.segmentInset,
            style: .continuous
          )
        )
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Group by \(group.label)")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  /// The trailing `provider · model` switcher (mockup `.model` +
  /// `.model-menu`, T-8.8 brought forward): a working menu that lists each
  /// keyed provider's models and routes to Settings for key entry.
  private var modelSelector: some View {
    ModelSwitcher(onShowSettings: onShowSettings)
  }

  private var searchField: some View {
    HStack(spacing: BrandMetrics.Spacing.xs) {
      Image(systemName: "magnifyingglass")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.textTertiary)

      TextField("Search", text: queryBinding)
        .textFieldStyle(.plain)
        .font(BrandTypography.body)
        .foregroundStyle(BrandColors.textPrimary)

      if !model.filters.query.isEmpty {
        Button {
          model.filters.query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(BrandTypography.callout)
            .foregroundStyle(BrandColors.textTertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
      }
    }
    // Taller than the mockup's 8pt input padding per Mark's review — the
    // field carries the appbar's vertical weight.
    .padding(.horizontal, BrandMetrics.Spacing.md)
    .padding(.vertical, BrandMetrics.Spacing.md)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(BrandColors.textPrimary.opacity(BrandMetrics.Control.hoverHighlightOpacity / 2))
    )
    .overlay(
      // Mockup `.search input` hairline border.
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .strokeBorder(BrandColors.separator)
    )
    .frame(maxWidth: .infinity)
  }

  // MARK: Grouped grid (usage-ranked hero per group)

  private func sectionView(_ section: BrowseSection, columns: Int, cellWidth: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      sectionHeader(section)

      VStack(spacing: Self.gridGap) {
        ForEach(Array(gridRows(for: section, columns: columns).enumerated()), id: \.offset) { _, row in
          gridRow(row, columns: columns, cellWidth: cellWidth)
        }
      }
    }
  }

  private func sectionHeader(_ section: BrowseSection) -> some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      Image(systemName: model.filters.group == .project ? "folder" : "cpu")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.textTertiary)

      Text(section.tag)
        .font(BrandTypography.headline)
        .foregroundStyle(BrandColors.textPrimary)
        .lineLimit(1)

      Spacer(minLength: BrandMetrics.Spacing.sm)

      Text(section.items.count == 1 ? "1 capability" : "\(section.items.count) capabilities")
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textTertiary)
    }
  }

  private struct GridSlot: Identifiable {
    let item: BrowseItem
    let isHero: Bool

    var id: Int64 {
      item.id
    }
  }

  /// Splits a section's hero-rank-ordered items into grid rows: the first
  /// item is the hero, spanning two columns (or full width when the pane is
  /// narrow — the hero reflows rather than shrinking); the rest flow in
  /// `columns`-wide rows.
  private func gridRows(for section: BrowseSection, columns: Int) -> [[GridSlot]] {
    guard let hero = section.items.first else {
      return []
    }

    var rows: [[GridSlot]] = []
    var firstRow: [GridSlot] = [GridSlot(item: hero, isHero: true)]
    let heroSpan = min(2, columns)
    var standards = Array(section.items.dropFirst())

    let seatsBesideHero = max(0, columns - heroSpan)
    for item in standards.prefix(seatsBesideHero) {
      firstRow.append(GridSlot(item: item, isHero: false))
    }
    standards.removeFirst(min(seatsBesideHero, standards.count))
    rows.append(firstRow)

    var index = 0
    while index < standards.count {
      let end = min(index + columns, standards.count)
      rows.append(standards[index..<end].map { GridSlot(item: $0, isHero: false) })
      index = end
    }

    return rows
  }

  private func gridRow(_ row: [GridSlot], columns: Int, cellWidth: CGFloat) -> some View {
    let containsHero = row.contains(where: \.isHero)
    let rowHeight = containsHero ? Self.heroRowHeight : Self.standardRowHeight
    let heroSpan = min(2, columns)
    let heroWidth = cellWidth * CGFloat(heroSpan) + Self.gridGap * CGFloat(heroSpan - 1)

    return HStack(alignment: .top, spacing: Self.gridGap) {
      ForEach(row) { slot in
        moduleCell(for: slot)
          .frame(width: slot.isHero ? heroWidth : cellWidth, height: rowHeight)
      }

      if row.count < columns, !containsHero {
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func moduleCell(for slot: GridSlot) -> some View {
    ModuleCell(
      item: slot.item,
      state: cellState(for: slot.item),
      provenance: model.provenance(for: slot.item),
      isHero: slot.isHero,
      isSelected: selectedGunkId == slot.item.id,
      isArrived: arrivedGunkIds.contains(slot.item.id),
      onSelect: { selectedGunkId = slot.item.id }
    )
  }

  /// One trust verdict per cell: extracted modules are agent-ready, the
  /// approval queue is amber, and everything else not yet extracted is the
  /// dimmed *Not in toolbox* quiet state.
  private func cellState(for item: BrowseItem) -> ModuleCellState {
    if item.gunk.extractedAt != nil {
      return .agentReady
    }

    if model.approvalFilter(for: item) == .needsApproval {
      return .needsApproval
    }

    return .notInToolbox
  }

  // MARK: Detail

  /// Interim presentation only: the inline right pane goes away when the
  /// module-detail surface is re-decided (module-run-v1 proposes a full
  /// page, Phase 10). Detail *functionality* (trust readout, files, bundle,
  /// actions) survives wherever it lands.
  private func detailPane(for detail: BrowseModuleDetail) -> some View {
    ModuleDetailView(
      detail: detail,
      // Same membership rule as `BrowseModel.approvalQueue` (and therefore
      // the sidebar badge), so the review block can never disagree with
      // either.
      needsApproval: model.approvalFilter(for: detail.item) == .needsApproval,
      approvalThreshold: model.confidenceThreshold,
      mcpNeedsSetup: mcpNeedsSetup,
      openBundle: openBundle,
      onShowSettings: onShowSettings,
      onApprove: {
        // Approve feedback (T-8.4): the Agent-ready line transitions to its
        // success state in place; `settle` gives the landing overshoot.
        withAnimation(BrandMotion.settle) {
          model.approve(gunkId: detail.item.gunk.id)
        }
      },
      onReject: { model.reject(gunkId: detail.item.gunk.id) },
      onRerun: { model.reclassify(sourceId: detail.item.source.id) },
      onDelete: { model.delete(gunkId: detail.item.gunk.id) },
      onShowRuns: { onShowRuns(.source(detail.item.source.id)) }
    )
  }

  // MARK: Filter bindings (unchanged BrowseModel contract)

  private var queryBinding: Binding<String> {
    Binding(
      get: { model.filters.query },
      set: { model.filters.query = $0 }
    )
  }

  /// ux §3.2: filter changes never steal or re-assign the selection. The
  /// selection survives the active scope hiding its cell (T-8.4: approving a
  /// queued module under the needs-approval scope must keep the detail open
  /// so its post-approve feedback stays visible — the cell never silently
  /// vanishes from under the user). Selection clears only when the module no
  /// longer exists (deleted or rejected), collapsing the inline pane back to
  /// the full-width grid.
  private func synchronizeSelection() {
    if let selectedGunkId,
       !model.loadedGunkIds.contains(selectedGunkId) {
      self.selectedGunkId = nil
    }
  }
}

// MARK: - Intake affordances (T-8.5 — drag is never the only door)

/// The first-run empty Library: a centered click-or-drag panel that shares
/// the full-window drop overlay's visual language (glass card, dashed
/// border, folder icon) so it *teaches* the drag gesture, plus an accent
/// **Add folder** button for the no-gesture path. Clicking anywhere on the
/// panel opens the same folder picker.
private struct LibraryIntakeZone: View {
  let onAddFolder: () -> Void

  @State private var isHovering = false

  /// Matches `WindowDropOverlay`'s card width so the two surfaces read as
  /// the same affordance.
  private static let panelMaxWidth: CGFloat = 460

  var body: some View {
    VStack(spacing: BrandMetrics.Spacing.md) {
      Image(systemName: "folder.badge.plus")
        .font(BrandTypography.sans(size: 44, weight: .regular))
        .foregroundStyle(isHovering ? BrandColors.textPrimary : BrandColors.textSecondary)

      Text("Drag a folder here, or click to browse")
        .font(BrandTypography.cardTitleHero)
        .foregroundStyle(BrandColors.textPrimary)
        .multilineTextAlignment(.center)

      Text("gunk decomposes each folder into reusable, verified capabilities for your agent.")
        .font(BrandTypography.body)
        .foregroundStyle(BrandColors.textSecondary)
        .multilineTextAlignment(.center)

      Button(action: onAddFolder) {
        Label("Add folder", systemImage: "folder.badge.plus")
      }
      .buttonStyle(.brandPrimary)
      .padding(.top, BrandMetrics.Spacing.xs)
    }
    .padding(.vertical, BrandMetrics.Spacing.xl + BrandMetrics.Spacing.md)
    .padding(.horizontal, BrandMetrics.Spacing.xl + BrandMetrics.Spacing.sm)
    .frame(maxWidth: Self.panelMaxWidth)
    .brandGlass(cornerRadius: BrandMetrics.Radius.xl, elevated: false)
    .overlay {
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.xl, style: .continuous)
        .strokeBorder(
          isHovering ? BrandColors.textSecondary : BrandColors.textTertiary,
          style: StrokeStyle(
            lineWidth: 2,
            dash: [BrandMetrics.Spacing.sm, BrandMetrics.Spacing.xs]
          )
        )
    }
    .contentShape(RoundedRectangle(cornerRadius: BrandMetrics.Radius.xl, style: .continuous))
    .onTapGesture(perform: onAddFolder)
    .onHover { hovering in
      withAnimation(BrandMotion.quick) {
        isHovering = hovering
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Add a folder to your library. Drag one here, or click to browse.")
  }
}

// MARK: - Module detail

private struct ModuleDetailView: View {
  let detail: BrowseModuleDetail
  /// Queue membership by `BrowseModel`'s rule — drives the review block.
  let needsApproval: Bool
  /// The auto-accept gate the queue rule computes from
  /// (`BrowseModel.confidenceThreshold`), so the threshold copy below and
  /// the queue behavior can never disagree.
  let approvalThreshold: Double
  let mcpNeedsSetup: Bool
  let openBundle: (URL) -> Void
  let onShowSettings: () -> Void
  let onApprove: () -> Void
  let onReject: () -> Void
  let onRerun: () -> Void
  let onDelete: () -> Void
  /// Opens the run inspector at this module's source (T-8.6). Deliberately
  /// a quiet text affordance: the module-run-v1 full page will own run
  /// provenance properly (Phase 10) — this is the interim door, not a
  /// destination treatment.
  let onShowRuns: () -> Void

  @State private var showRejectConfirmation = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
        header
        agentReadyLine
        reviewSection
        actionsRow
        runabilitySection
        bundleSection
        filesSection
        sharedDependenciesSection
        entrypointsSection
        verificationDetailsSection
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .padding(.bottom, BrandMetrics.Spacing.sm)
      // Approve feedback in place: the review block leaves and the
      // Agent-ready line lands its success state on the same surface.
      .animation(BrandMotion.settle, value: needsApproval)
    }
  }

  // MARK: Review (T-8.4 — approval folded into the detail)

  /// Approve/reject for a queued module, above the actions row. Interim
  /// home: moves with the rest of this view when module detail is
  /// re-decided (module-run-v1, Phase 10).
  @ViewBuilder
  private var reviewSection: some View {
    if needsApproval {
      DetailSection(title: "Needs approval", systemImage: "exclamationmark.triangle") {
        Text(confidenceContextLine)
          .font(BrandTypography.callout)
          .foregroundStyle(BrandColors.textPrimary)

        Text("Approving extracts the module and makes it available to your agent through MCP.")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)

        HStack(spacing: BrandMetrics.Spacing.sm) {
          Button(action: onApprove) {
            Label("Approve", systemImage: "checkmark.circle")
          }
          .buttonStyle(.brandPrimary)
          .help("Approve and extract \(detail.item.gunk.name)")

          Button(role: .destructive) {
            showRejectConfirmation = true
          } label: {
            Label("Reject", systemImage: "xmark.circle")
          }
          .buttonStyle(.brandDestructive)
          .help("Reject and permanently delete \(detail.item.gunk.name)")
          .confirmationDialog(
            "Reject \(detail.item.gunk.name)?",
            isPresented: $showRejectConfirmation,
            titleVisibility: .visible
          ) {
            Button("Reject and delete", role: .destructive, action: onReject)
            Button("Cancel", role: .cancel) {}
          } message: {
            Text("Rejecting permanently deletes this module from your library. This cannot be undone.")
          }
        }
        .padding(.top, BrandMetrics.Spacing.xs)
      }
      .transition(.opacity)
    }
  }

  /// "62% — below the 70% auto-accept threshold": confidence shown with the
  /// context of the gate that actually queued it.
  private var confidenceContextLine: String {
    let confidence = (detail.item.gunk.confidence ?? 0)
      .formatted(.percent.precision(.fractionLength(0)))
    let threshold = approvalThreshold
      .formatted(.percent.precision(.fractionLength(0)))
    return "\(confidence) — below the \(threshold) auto-accept threshold"
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      Text(detail.item.gunk.name)
        .font(BrandTypography.headline)
        .foregroundStyle(BrandColors.textPrimary)
        .lineLimit(2)

      if let purpose = detail.item.gunk.purpose {
        Text(purpose)
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
      }

      HStack(spacing: BrandMetrics.Spacing.xs) {
        TagChip(detail.item.source.name)
        TagChip(detail.item.gunk.language ?? "Unknown language")
        TagChip(
          (detail.item.gunk.confidence ?? 0).formatted(.percent.precision(.fractionLength(0)))
        )
      }
      .padding(.top, BrandMetrics.Spacing.xs)

      Button(action: onShowRuns) {
        HStack(spacing: BrandMetrics.Spacing.xs) {
          Image(systemName: "clock.arrow.circlepath")
          Text("Last run")
          Image(systemName: "chevron.forward")
        }
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textSecondary)
      }
      .buttonStyle(.plain)
      .help("Inspect the latest extraction run for \(detail.item.source.name)")
    }
  }

  /// The MCP payoff truth line (ux §4.5, D8), derived from `extractedAt` —
  /// no new store state. The needs-setup variant routes to Settings.
  @ViewBuilder
  private var agentReadyLine: some View {
    if mcpNeedsSetup {
      Button(action: onShowSettings) {
        HStack(spacing: BrandMetrics.Spacing.sm) {
          StatusBadge(
            "MCP not set up",
            variant: .warning,
            systemImage: "exclamationmark.triangle"
          )
          Text("Connect Cursor → Settings")
            .font(BrandTypography.caption)
            .foregroundStyle(BrandColors.textSecondary)
        }
      }
      .buttonStyle(.plain)
      .help("Open Settings to connect Cursor")
    } else if detail.item.gunk.extractedAt != nil {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        StatusBadge("Agent-ready", variant: .success, systemImage: "sparkles")
        Text("Available to your agent through MCP.")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
      }
    } else {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        StatusBadge("Not agent-visible yet", variant: .neutral, systemImage: "circle.dashed")
        Text("Approve this module to extract it for agents.")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
      }
    }
  }

  /// Re-run and delete live here exclusively — destructive and heavyweight
  /// actions get the deliberate surface, not the row (ux §3.2).
  private var actionsRow: some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      Button {
        onRerun()
      } label: {
        Label("Re-run source", systemImage: "arrow.triangle.2.circlepath")
      }
      .buttonStyle(.brandSecondary)
      .help("Re-run decomposition for \(detail.item.source.name)")

      Button(role: .destructive, action: onDelete) {
        Label("Delete", systemImage: "trash")
      }
      .buttonStyle(.brandDestructive)
      .help("Delete \(detail.item.gunk.name)")
    }
  }

  private var runabilitySection: some View {
    DetailSection(title: "Runability", systemImage: "checkmark.seal") {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        statusRow(title: "Self-contained for AI reuse", status: selfContainmentStatus)
        Text("Checks whether module-owned imports stay inside the bundle and claimed entrypoints are present.")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
      }

      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        statusRow(title: "Standalone runnable project", status: buildStatus)
        Text("Separate from self-containment: many gunks are reusable feature or library slices that still need a host project, installed packages, or runtime configuration.")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
      }
    }
  }

  private var bundleSection: some View {
    DetailSection(title: "Bundle path", systemImage: "folder") {
      if let bundlePath = detail.bundlePath {
        Text(bundlePath)
          .font(BrandTypography.mono)
          .foregroundStyle(BrandColors.textSecondary)
          .textSelection(.enabled)
          .lineLimit(3)
          .truncationMode(.middle)

        Button {
          openBundle(URL(fileURLWithPath: bundlePath))
        } label: {
          Label("Open in Finder", systemImage: "folder")
        }
        .buttonStyle(.brandSecondary)
      } else {
        emptyText("No extracted bundle path recorded.")
      }
    }
  }

  private var filesSection: some View {
    DetailSection(title: "Owned files", systemImage: "doc.text") {
      if detail.ownedFiles.isEmpty {
        emptyText("No owned files recorded.")
      } else {
        pathList(detail.ownedFiles)
      }
    }
  }

  private var sharedDependenciesSection: some View {
    DetailSection(title: "Shared dependencies", systemImage: "link") {
      if detail.sharedDependencies.isEmpty {
        emptyText("No shared dependencies recorded.")
      } else {
        pathList(detail.sharedDependencies)
      }
    }
  }

  private var entrypointsSection: some View {
    DetailSection(title: "Entrypoints", systemImage: "arrow.right.circle") {
      if detail.entrypoints.isEmpty {
        emptyText("No confident entrypoints recorded.")
      } else {
        pathList(detail.entrypoints.map(\.label))
      }
    }
  }

  @ViewBuilder
  private var verificationDetailsSection: some View {
    if let selfContainment = detail.selfContainment, !selfContainment.passed {
      DetailSection(title: "Self-containment details", systemImage: "exclamationmark.triangle") {
        if !selfContainment.danglingImports.isEmpty {
          Text("Dangling imports")
            .font(BrandTypography.caption.weight(.semibold))
            .foregroundStyle(BrandColors.textPrimary)
          pathList(selfContainment.danglingImports.map(danglingImportLabel))
        }

        if !selfContainment.missingEntrypoints.isEmpty {
          Text("Missing entrypoints")
            .font(BrandTypography.caption.weight(.semibold))
            .foregroundStyle(BrandColors.textPrimary)
          pathList(selfContainment.missingEntrypoints.map(missingEntrypointLabel))
        }
      }
    }

    if let buildVerification = detail.buildVerification {
      DetailSection(title: "Build verification", systemImage: "hammer") {
        if let command = buildVerification.command {
          Text(command)
            .font(BrandTypography.mono)
            .foregroundStyle(BrandColors.textSecondary)
            .textSelection(.enabled)
        }

        Text(buildVerification.log)
          .font(BrandTypography.mono)
          .foregroundStyle(BrandColors.textSecondary)
          .textSelection(.enabled)
          .lineLimit(8)
      }
    }
  }

  private func statusRow(title: String, status: DetailStatus) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.sm) {
      Text(title)
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.textPrimary)
      Spacer(minLength: BrandMetrics.Spacing.sm)
      StatusBadge(status.label, variant: status.variant, systemImage: status.systemImage)
    }
  }

  private func pathList(_ values: [String]) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      ForEach(values, id: \.self) { value in
        Text(value)
          .font(BrandTypography.mono)
          .foregroundStyle(BrandColors.textSecondary)
          .textSelection(.enabled)
          .lineLimit(2)
          .truncationMode(.middle)
      }
    }
  }

  private func emptyText(_ text: String) -> some View {
    Text(text)
      .font(BrandTypography.caption)
      .foregroundStyle(BrandColors.textTertiary)
  }

  private func danglingImportLabel(_ importRecord: RunTrace.DanglingImport) -> String {
    let target = importRecord.resolvedTarget ?? importRecord.moduleSpecifier ?? "unknown target"
    return "\(importRecord.fromPath) -> \(target) (\(importRecord.reason))"
  }

  private func missingEntrypointLabel(_ entrypoint: RunTrace.MissingEntrypoint) -> String {
    if let symbol = entrypoint.symbol {
      return "\(entrypoint.path) · \(symbol) (\(entrypoint.reason))"
    }

    return "\(entrypoint.path) (\(entrypoint.reason))"
  }

  private var selfContainmentStatus: DetailStatus {
    guard let selfContainment = detail.selfContainment else {
      return DetailStatus(label: "Not verified", variant: .neutral, systemImage: "questionmark.circle")
    }

    if selfContainment.passed {
      return DetailStatus(label: "Passed", variant: .success, systemImage: "checkmark.circle")
    }

    return DetailStatus(label: "Needs attention", variant: .warning, systemImage: "exclamationmark.triangle")
  }

  private var buildStatus: DetailStatus {
    guard let buildVerification = detail.buildVerification else {
      return DetailStatus(label: "Not verified", variant: .neutral, systemImage: "questionmark.circle")
    }

    if buildVerification.skipped {
      return DetailStatus(label: "Skipped", variant: .neutral, systemImage: "minus.circle")
    }

    if buildVerification.built {
      return DetailStatus(label: "Passed", variant: .success, systemImage: "checkmark.circle")
    }

    return DetailStatus(label: "Failed", variant: .danger, systemImage: "xmark.circle")
  }
}

private struct DetailStatus {
  let label: String
  let variant: StatusBadge.Variant
  let systemImage: String
}

/// A glass detail card with a branded section header.
private struct DetailSection<Content: View>: View {
  let title: String
  let systemImage: String
  @ViewBuilder let content: Content

  var body: some View {
    GlassCard(
      padding: BrandMetrics.Spacing.md,
      cornerRadius: BrandMetrics.Radius.medium,
      elevated: false
    ) {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
        SectionHeader(title, systemImage: systemImage)
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
