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

  /// Pane contract from ux §3.2/§4.6 (D10): browser ≥ 440, detail 300–440,
  /// and both must fit at the 960pt window minimum next to the fixed 192pt
  /// sidebar. The detail width is computed explicitly because HStack's own
  /// negotiation over two flexible panes can overshoot the proposal (it
  /// sizes the bounded detail pane before the browser clamps to its
  /// minimum), which cropped both edges at the minimum window size.
  private static let browserMinWidth: CGFloat = 440
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
      let detailWidth = max(
        Self.detailMinWidth,
        min(
          Self.detailMaxWidth,
          proxy.size.width - Self.browserMinWidth - BrandMetrics.Spacing.md
        )
      )
      let browserWidth = proxy.size.width - detailWidth - BrandMetrics.Spacing.md

      HStack(alignment: .top, spacing: BrandMetrics.Spacing.md) {
        browserPane(width: browserWidth)
          .frame(minWidth: Self.browserMinWidth, maxWidth: .infinity, maxHeight: .infinity)

        detailPane
          .frame(width: detailWidth)
          .frame(maxHeight: .infinity)
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
      EmptyStateView(
        "No modules yet",
        message: "Drag a folder onto the window, or click Add module, and gunk will decompose it into reusable modules."
      ) {
        Button {
          addFolder()
        } label: {
          Label("Add module", systemImage: "plus.square.on.square")
        }
        .buttonStyle(.brandPrimary)
      }
    } else {
      EmptyStateView(
        "No matches",
        message: "No modules match the current search and filters."
      )
    }
  }

  // MARK: Header (the v2 controls layer — glass lives here only)

  private var libraryHeader: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      // Row 1: identity + source management (T-8.3) — split across two rows
      // so controls never fight for width at the 960pt minimum.
      HStack(spacing: BrandMetrics.Spacing.sm) {
        Text("Library")
          .font(BrandTypography.headline)
          .foregroundStyle(BrandColors.textPrimary)

        countChip

        Spacer(minLength: BrandMetrics.Spacing.sm)

        Button {
          sourceListModel.refresh()
          showSourcesPanel = true
        } label: {
          Label("Sources (\(sourceListModel.sources.count))", systemImage: "folder")
        }
        .buttonStyle(.brandSecondary)
        .help("View and manage your sources")

        Button {
          addFolder()
        } label: {
          // "Add module", not "Add folder": the user is adding a capability
          // to their toolbox; the folder picker is just the mechanism.
          Label("Add module", systemImage: "plus.square.on.square")
        }
        .buttonStyle(.brandSecondary)
        .help("Choose a folder and gunk will decompose it into modules")

        // T-8.8's `provider · model` switcher lands in this trailing slot.
      }

      // Row 2: grouping + search. The source/tag/language/approval *filter*
      // UI is intentionally absent for now — `BrowseModel`'s filter state
      // stays intact, and the controls return layered inside the search
      // bar once that design lands (see T-8.3b follow-ups in the task doc).
      HStack(spacing: BrandMetrics.Spacing.sm) {
        // Neutral graphite selection (mockup `.seg`): green is meaning-only
        // and a grouping toggle carries no meaning-state, so the selected
        // segment must not take the accent (nor the system blue).
        Picker("Group", selection: groupBinding) {
          ForEach(BrowseGroup.allCases) { group in
            Text(group.label).tag(group)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .tint(BrandColors.backgroundElevatedHover)
        .frame(width: 168)
        .help("Group the library by source project or by extracting model")

        searchField
      }
    }
    .padding(BrandMetrics.Spacing.md)
    .controlSize(.small)
    .brandGlass(cornerRadius: BrandMetrics.Radius.medium, elevated: true)
  }

  private var countChip: some View {
    Text("\(model.totalModuleCount)")
      .font(BrandTypography.caption.weight(.semibold))
      .monospacedDigit()
      .foregroundStyle(BrandColors.textSecondary)
      .padding(.horizontal, BrandMetrics.Spacing.sm)
      .padding(.vertical, BrandMetrics.Spacing.xs / 2)
      .background(
        Capsule().fill(
          BrandColors.textPrimary.opacity(BrandMetrics.Control.hoverHighlightOpacity / 2)
        )
      )
      .accessibilityLabel("\(model.totalModuleCount) modules in the library")
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
    .padding(.horizontal, BrandMetrics.Spacing.sm)
    .padding(.vertical, BrandMetrics.Spacing.xs)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(BrandColors.textPrimary.opacity(BrandMetrics.Control.hoverHighlightOpacity / 2))
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

  @ViewBuilder
  private var detailPane: some View {
    if let selectedGunkId,
       let detail = model.detail(for: selectedGunkId) {
      ModuleDetailView(
        detail: detail,
        mcpNeedsSetup: mcpNeedsSetup,
        openBundle: openBundle,
        onShowSettings: onShowSettings,
        onRerun: { model.reclassify(sourceId: detail.item.source.id) },
        onDelete: { model.delete(gunkId: detail.item.gunk.id) }
      )
    } else {
      // Interim design only: this resting "Select a module" pane (and the
      // inline detail pane itself) is removed when T-8.6 moves the detail
      // into the toolbox-v2 centered glass sheet. Detail *functionality*
      // stays — only the inline right-pane presentation goes (see the
      // T-8.3b follow-ups in the phase-8 task doc).
      EmptyStateView(
        "Select a module",
        message: "Open a module to inspect its files, bundle, and runability signals."
      )
    }
  }

  // MARK: Filter bindings (unchanged BrowseModel contract)

  private var groupBinding: Binding<BrowseGroup> {
    Binding(
      get: { model.filters.group },
      set: { model.filters.group = $0 }
    )
  }

  private var queryBinding: Binding<String> {
    Binding(
      get: { model.filters.query },
      set: { model.filters.query = $0 }
    )
  }

  /// ux §3.2: filter changes never steal or re-assign the selection. If the
  /// selected module is no longer visible the selection clears, and the
  /// detail pane shows its empty state — that is a valid resting state.
  private func synchronizeSelection() {
    let visibleItems = model.sections.flatMap(\.items)
    if let selectedGunkId,
       !visibleItems.contains(where: { $0.id == selectedGunkId }) {
      self.selectedGunkId = nil
    }
  }
}

// MARK: - Module detail

private struct ModuleDetailView: View {
  let detail: BrowseModuleDetail
  let mcpNeedsSetup: Bool
  let openBundle: (URL) -> Void
  let onShowSettings: () -> Void
  let onRerun: () -> Void
  let onDelete: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
        header
        agentReadyLine
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
    }
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
