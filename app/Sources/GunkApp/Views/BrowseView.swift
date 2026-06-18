import AppKit
import SwiftUI

/// How the Library lays out its modules (library-v2 §1): the briefing-card
/// grid (default) or a denser list. The choice persists in the same
/// Settings-defaults (`@AppStorage`) pattern the app already uses for the
/// model picker — no store schema.
enum LibraryViewMode: String, CaseIterable, Identifiable {
  case grid
  case list

  var id: String {
    rawValue
  }

  /// The appbar toggle's icon-pair glyphs (library-v2 §1).
  var systemImage: String {
    switch self {
    case .grid:
      return "square.grid.2x2"
    case .list:
      return "list.bullet"
    }
  }

  var label: String {
    switch self {
    case .grid:
      return "Grid"
    case .list:
      return "List"
    }
  }
}

@MainActor
struct BrowseView: View {
  let model: BrowseModel
  /// Sources and intake now live in the Library (T-8.3): the source list folds
  /// into a sheet and folders are added through the one true intake path.
  let sourceListModel: GunkListModel
  let processingModel: ProcessingModel
  let dropZoneHandler: DropZoneHandler
  /// From the shared `MCPSetupModel` (owned by the shell): when no client
  /// is wired up, the Agent-ready treatment flips to needs-setup copy that
  /// opens the one-click setup sheet (ux §4.5, D8; T-8.10).
  var mcpNeedsSetup = false
  var onShowSettings: () -> Void = {}
  /// Opens the shell-owned MCP setup sheet (T-8.10) — every needs-setup
  /// affordance routes here instead of Settings.
  var onShowMCPSetup: () -> Void = {}
  /// Summons the shell-owned run inspector (T-8.6) from this view's entry
  /// points: a source row's "View runs".
  var onShowRuns: (RunInspectorContext) -> Void = { _ in }
  /// Navigates to the full module page (T-10.4): selecting a module pushes the
  /// shell's `module(gunkId)` route instead of opening the interim inline pane.
  var onOpenModule: (Int64) -> Void = { _ in }

  /// The grid's selection ring. Selection no longer drives an inline detail
  /// pane (T-10.4 navigates to a page) — it survives navigation so that on
  /// breadcrumb-back the last-opened cell stays highlighted (the CP-F "keep
  /// grid scroll + selection" decision).
  @State private var selectedGunkId: Int64?
  @State private var showSourcesPanel = false

  /// Persisted grid/list choice (library-v2 §1; T-9.3): defaults to grid,
  /// stored in the same `@AppStorage` Settings-defaults the model picker uses.
  @AppStorage("library.viewMode") private var viewModeRawValue = LibraryViewMode.grid.rawValue

  private var viewMode: LibraryViewMode {
    LibraryViewMode(rawValue: viewModeRawValue) ?? .grid
  }

  /// Arrival highlight (ux §4.4), moved from the retired Sources surface to the
  /// module grid: modules created during a run carry the accent treatment for
  /// a beat after the run completes. Mirrors the old `arrivedSourceIds` decay.
  @State private var arrivedGunkIds: Set<Int64> = []
  @State private var gunkIdsBeforeRun: Set<Int64> = []
  @State private var arrivalDecayTasks: [Int64: Task<Void, Never>] = [:]

  /// How long a freshly created module keeps its highlight (ux §4.4).
  private static let arrivalHighlightLifetime: Duration = .seconds(2)

  /// Browser pane minimum from ux §3.2/§4.6 (D10): the grid never drops below
  /// 400pt. With the inline detail pane retired (T-10.4) the grid owns the
  /// whole detail area, so the old detail-pane width band is gone.
  private static let browserMinWidth: CGFloat = 400

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
      // The interim inline detail pane is gone (T-10.4): selecting a module
      // navigates to a full breadcrumb page instead, so the grid always owns
      // the full width. The selection ring survives navigation (see
      // `selectedGunkId`) so back-navigation lands on the highlighted cell.
      browserPane(width: proxy.size.width)
        .frame(minWidth: Self.browserMinWidth, maxWidth: .infinity, maxHeight: .infinity)
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
        // Cards/rows scroll beneath the floating glass controls layer (the
        // safe-area inset header below). Both modes share the same sections,
        // ordering, selection, and arrival behavior — only the layout forks.
        ScrollView {
          LazyVStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
            ForEach(model.sections) { section in
              switch viewMode {
              case .grid:
                sectionView(section, columns: columns, cellWidth: cellWidth)
              case .list:
                listSectionView(section)
              }
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
      viewModePicker
      groupPicker
      searchField
        .frame(minWidth: 160, maxWidth: Self.searchMaxWidth)

      Spacer(minLength: BrandMetrics.Spacing.sm)

      // Transient needs-approval scope chip (T-8.4): lives in the flexible
      // gap only while the scope is active — never a persistent filter UI.
      if showsScopeChip {
        needsApprovalScopeChip
      }

      modelSelector
    }
  }

  /// Narrow fallback: identity + model on top, grouping + search below.
  private var stackedHeader: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        headerTitle
        viewModePicker
        Spacer(minLength: BrandMetrics.Spacing.sm)
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
  ///
  /// NOTE: temporarily unmounted from the header for MVP — the sources/panel
  /// code below is intentionally kept so this can be re-homed later.
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

  /// The grid/list toggle (library-v2 §1): an icon-pair segmented control in
  /// the appbar, immediately right of the count chip and left of the
  /// `Project | Model` grouping. Same neutral graphite well as `groupPicker`
  /// — view mode carries no meaning-state, so no green.
  private var viewModePicker: some View {
    HStack(spacing: Self.segmentInset) {
      ForEach(LibraryViewMode.allCases) { mode in
        viewModeSegment(mode)
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
    .help("Switch between the grid and list layout")
  }

  private func viewModeSegment(_ mode: LibraryViewMode) -> some View {
    let isSelected = viewMode == mode
    return Button {
      withAnimation(BrandMotion.quick) {
        viewModeRawValue = mode.rawValue
      }
    } label: {
      Image(systemName: mode.systemImage)
        .font(BrandTypography.callout.weight(.medium))
        .foregroundStyle(isSelected ? BrandColors.textPrimary : BrandColors.textSecondary)
        .frame(width: BrandMetrics.Mark.small, height: BrandMetrics.Mark.small)
        .padding(.horizontal, BrandMetrics.Spacing.sm)
        .padding(.vertical, BrandMetrics.Spacing.xs)
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
    .accessibilityLabel("\(mode.label) view")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

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

  /// The search field commits through `LibrarySearchField`, which keeps the
  /// typed text in local state and pushes it to the model on a short debounce
  /// — so the grid refresh that follows a query change can't tear the field's
  /// first responder down mid-keystroke (the "one letter at a time" bug).
  private var searchField: some View {
    LibrarySearchField(
      query: model.filters.query,
      onCommit: { model.filters.query = $0 }
    )
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
      onSelect: { openModule(slot.item.id) }
    )
  }

  // MARK: List (library-v2 §1 — one group = one solid card, flattened hero)

  /// A group rendered as a single solid graphite card of hairline-divided
  /// rows (library-v2 §1). The section header and the `Project | Model`
  /// grouping carry over from the grid unchanged — only the body layout forks.
  private func listSectionView(_ section: BrowseSection) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      sectionHeader(section)

      VStack(spacing: 0) {
        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
          if index > 0 {
            Divider()
              .overlay(BrandColors.separator)
          }

          moduleRow(for: item, isMostUsed: index == 0)
        }
      }
      .background(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous)
          .fill(BrandColors.backgroundElevated)
      )
      .clipShape(RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous))
    }
  }

  private func moduleRow(for item: BrowseItem, isMostUsed: Bool) -> some View {
    ModuleRow(
      item: item,
      state: cellState(for: item),
      provenance: model.provenance(for: item),
      // The usage-ranked first row of a group is the flattened hero
      // (library-v2 §1): the quiet `MOST USED` marker, never extra size.
      isMostUsed: isMostUsed,
      isSelected: selectedGunkId == item.id,
      isArrived: arrivedGunkIds.contains(item.id),
      onSelect: { openModule(item.id) }
    )
  }

  /// Selecting a module sets the grid's selection ring and navigates to the
  /// full module page (T-10.4). Selection is set before navigation so the cell
  /// is already highlighted when the user comes back.
  private func openModule(_ gunkId: Int64) {
    selectedGunkId = gunkId
    onOpenModule(gunkId)
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

  // MARK: Selection

  /// ux §3.2: filter changes never steal or re-assign the selection. The
  /// selection ring survives the active scope hiding its cell and survives
  /// navigation to the module page (T-10.4), so breadcrumb-back lands on the
  /// highlighted cell. Selection clears only when the module no longer exists
  /// (deleted or rejected).
  private func synchronizeSelection() {
    if let selectedGunkId,
       !model.loadedGunkIds.contains(selectedGunkId) {
      self.selectedGunkId = nil
    }
  }
}

// MARK: - Library search field

/// The Library search field, isolated into its own view so its first
/// responder survives the grid refreshing beneath it. Typing only mutates
/// local state; the model (and therefore `sections`, and therefore the whole
/// `BrowseView` body) is committed on a short debounce. That keeps the
/// field's `NSTextField` from being rebuilt on every keystroke — the cause
/// of the "search loses focus, one letter at a time" report. External query
/// changes (the run-end View action's project scope, a programmatic clear)
/// flow back in without disturbing in-flight typing.
private struct LibrarySearchField: View {
  /// The model's current query — the source of truth the field reconciles to.
  let query: String
  /// Pushes a committed query back to the model.
  let onCommit: (String) -> Void

  @State private var text: String
  @State private var commitTask: Task<Void, Never>?
  @FocusState private var isFocused: Bool

  /// Short enough to feel live, long enough to batch a burst of keystrokes
  /// into a single grid refresh.
  private static let commitDebounce: Duration = .milliseconds(200)

  init(query: String, onCommit: @escaping (String) -> Void) {
    self.query = query
    self.onCommit = onCommit
    _text = State(initialValue: query)
  }

  var body: some View {
    HStack(spacing: BrandMetrics.Spacing.xs) {
      Image(systemName: "magnifyingglass")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.textTertiary)

      TextField("Search", text: $text)
        .textFieldStyle(.plain)
        .font(BrandTypography.body)
        .foregroundStyle(BrandColors.textPrimary)
        .focused($isFocused)
        .onChange(of: text) { _, newValue in
          scheduleCommit(newValue)
        }

      if !text.isEmpty {
        Button {
          commitTask?.cancel()
          text = ""
          onCommit("")
          isFocused = true
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
    // Reconcile to external query changes (View-action project scope, a
    // model-side clear) without clobbering the user's in-progress typing.
    .onChange(of: query) { _, newValue in
      guard newValue != text else {
        return
      }
      commitTask?.cancel()
      text = newValue
    }
  }

  private func scheduleCommit(_ newValue: String) {
    commitTask?.cancel()
    commitTask = Task {
      try? await Task.sleep(for: Self.commitDebounce)
      guard !Task.isCancelled else {
        return
      }
      onCommit(newValue)
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

// `ModuleDetailView`, `DetailStatus`, and `DetailSection` moved to
// `ModulePageView.swift` (T-10.4): module detail is a full breadcrumb page now,
// not an inline pane.
