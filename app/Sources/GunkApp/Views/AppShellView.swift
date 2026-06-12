import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct AppLaunchView: View {
  @ObservedObject var runtime: AppRuntime

  var body: some View {
    Group {
      if let services = runtime.services {
        AppShellView(services: services)
      } else {
        launchFailureView
      }
    }
    // ux §4.6: below 960pt the Modules layout cannot fit and the sidebar
    // collapses into an overlay (D10).
    .frame(minWidth: 960, minHeight: 600)
  }

  private var launchFailureView: some View {
    VStack(spacing: BrandMetrics.Spacing.md) {
      BrandWordmark(style: .hero, revealOnAppear: true)
        .padding(.bottom, BrandMetrics.Spacing.sm)

      Text("gunk could not open")
        .font(.title3.bold())

      Text(runtime.launchError ?? "Unknown launch error.")
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .textSelection(.enabled)
    }
    .padding(BrandMetrics.Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

@MainActor
struct AppShellView: View {
  let services: AppServices

  @State private var selection: AppSection
  @State private var mcpStatus: SettingsStatusItem?
  @State private var completedSummary: RunCompletionSummary?
  @State private var modulesFoundDuringRun = 0
  @State private var pendingReviewsAtRunStart = 0
  @State private var summaryDecayTask: Task<Void, Never>?

  /// Whole-window drop target state (T-8.5): the overlay phase is owned
  /// here, not by `isTargeted`, so it can outlive the drag to show the
  /// invalid-drop error inside the overlay before dismissing.
  @State private var dropPhase: WindowDropOverlay.Phase = .hidden
  @State private var dropOverlayDismissTask: Task<Void, Never>?

  /// How long the transient completed summary stays in the status strip
  /// before decaying back to the idle MCP chip (ux §4.3).
  private static let completedStateLifetime: Duration = .seconds(8)

  /// SwiftUI `.onDrop` + window-level overlays can fight `NSWindow` first
  /// responder during drags; debounce the exit so the overlay never
  /// flickers mid-drag (T-8.5 refining loop).
  private static let dropExitDebounce: Duration = .milliseconds(100)
  /// How long the invalid-drop error stays inside the overlay before it
  /// dismisses.
  private static let dropErrorLifetime: Duration = .milliseconds(1600)

  private let mcpStatusProvider = MCPStatusProvider()

  init(services: AppServices) {
    self.services = services
    // Landing rule (T-8.2): always land on Library. Its empty state covers
    // first-run, so the old sources-vs-modules split dies with the Sources
    // tab. Dev-only (like GUNK_DESIGN_GALLERY_SECTION): scripted screenshot
    // runs can land on another section via GUNK_DEBUG_SECTION.
    let debugSection = ProcessInfo.processInfo.environment["GUNK_DEBUG_SECTION"]
      .flatMap(AppSection.init(rawValue:))
    _selection = State(initialValue: debugSection ?? .library)
  }

  /// Fixed sidebar width — the toolbox-v2 mockup's 232pt (Mark's review:
  /// the old 192 read too narrow). The Library's pane minimums were relaxed
  /// to keep 232 + content fitting the 960pt minimum window (the inline
  /// detail pane is interim and collapsed at rest since the T-8.3b
  /// follow-ups).
  private static let sidebarWidth: CGFloat = 232

  var body: some View {
    // A plain two-pane layout instead of NavigationSplitView: the split
    // view collapses the sidebar into an overlay whenever the Modules
    // browser's reported ideal width doesn't fit (observed even at 1120pt),
    // which is exactly the D10 failure this task must fix. A fixed sidebar
    // can never collapse, and GlassSidebar supplies its own chrome.
    NavigationStack {
      HStack(spacing: 0) {
        sidebar
          .frame(width: Self.sidebarWidth)

        detailContainer
      }
      .navigationTitle("gunk")
    }
    .background(BrandColors.backgroundPrimary)
    // Whole-window drop target (T-8.5): one `.onDrop` on the shell's root —
    // over sidebar *and* detail — so folders drop from any section. The
    // overlay floats in a layer above everything; the layout beneath never
    // reflows, resizes, or scrolls during a drag.
    .onDrop(
      of: [UTType.fileURL],
      delegate: WindowDropDelegate(
        dragEntered: handleDragEntered,
        dragUpdated: handleDragUpdated,
        dragExited: handleDragExited,
        receiveDrop: receiveDrop
      )
    )
    .overlay {
      if dropPhase != .hidden {
        WindowDropOverlay(phase: dropPhase)
          .transition(.opacity)
      }
    }
    .onAppear {
      services.sourceListModel.refresh()
      services.browseModel.refresh()
      mcpStatus = mcpStatusProvider.status()
      applyDropOverlayDebugOverride()
    }
    .onChange(of: selection) {
      mcpStatus = mcpStatusProvider.status()
    }
    .onChange(of: services.processingModel.isProcessing) { wasProcessing, isProcessing in
      if !wasProcessing, isProcessing {
        runDidStart()
      }
      if wasProcessing, !isProcessing {
        runDidEnd()
      }
    }
    .onChange(of: services.processingModel.modulesFound) { _, found in
      // `ProcessingModel.complete` resets the count in the same update that
      // flips `isProcessing`, so capture it while the run is still live.
      if services.processingModel.isProcessing, found > 0 {
        modulesFoundDuringRun = max(modulesFoundDuringRun, found)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .gunkInserted)) { _ in
      services.browseModel.refresh()
      services.sourceListModel.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .sourcesArrivedViaOpen)) { _ in
      // Dock-drop feedback (ux §4.4, D1): the window raises (AppDelegate)
      // and the shell navigates to Library (sources fold in there).
      selection = .library
    }
  }

  // MARK: Sidebar

  private var sidebar: some View {
    GlassSidebar {
      BrandWordmark(style: .sidebar)
        .padding(.top, BrandMetrics.Spacing.xs)
    } content: {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        ForEach(AppSection.allCases) { section in
          sidebarRow(section)
        }
      }
    } footer: {
      ShellStatusStrip(state: stripState, onTap: handleStripTap)
    }
    .padding(BrandMetrics.Spacing.sm)
  }

  private func sidebarRow(_ section: AppSection) -> some View {
    SidebarRow(
      title: section.title,
      systemImage: section.systemImage,
      isSelected: selection == section,
      accessory: accessory(for: section),
      accessoryAction: accessoryAction(for: section)
    ) {
      selection = section
    }
  }

  private func accessory(for section: AppSection) -> SidebarRow.Accessory? {
    switch section {
    case .library:
      // Library now owns both shell signals (T-8.2): the processing dot
      // wins while a run is active; otherwise the pending-review count,
      // hidden at zero. The queue is computed by BrowseModel with the same
      // membership rule the review surface renders, so badge and queue can
      // never disagree.
      if services.processingModel.isProcessing {
        return .processing
      }
      let count = services.browseModel.approvalQueue.count
      return count > 0 ? .count(count) : nil
    case .marketplace, .addModule, .settings:
      return nil
    }
  }

  /// Badge tap-through (T-8.4): the Library count badge navigates to Library
  /// *and* scopes it to the approval queue — review is a state in the
  /// Library, not a separate room. The scope applies the same
  /// `BrowseApprovalFilter.needsApproval` the queue rule feeds, so badge and
  /// scope can never disagree.
  private func accessoryAction(for section: AppSection) -> (() -> Void)? {
    guard section == .library, case .count = accessory(for: section) else {
      return nil
    }

    return {
      selection = .library
      services.browseModel.filters.approval = .needsApproval
    }
  }

  // MARK: Status strip (ux §4.3)

  private var stripState: ShellStripState {
    let processingModel = services.processingModel

    if processingModel.isProcessing {
      let (subject, detail) = processingStatus
      return .processing(subject: subject, detail: detail)
    }

    if let completedSummary {
      return .completed(completedSummary)
    }

    if processingModel.errorMessage != nil {
      return .runFailed
    }

    return .idle(mcp: mcpStatus ?? mcpStatusProvider.status())
  }

  private var processingStatus: (subject: String, detail: String) {
    let model = services.processingModel
    let progress = model.progressBySource

    let subject: String
    if progress.count > 1 {
      subject = "\(progress.count) sources"
    } else if let sourceId = progress.keys.first,
              let source = try? services.store.source(id: sourceId) {
      subject = source.name
    } else {
      subject = "Processing"
    }

    let percent = progress.isEmpty
      ? 0
      : Int((progress.values.reduce(0, +) / Double(progress.count)) * 100)

    return (subject, "\(percent)% · \(model.modulesFound) found")
  }

  private func handleStripTap() {
    // The strip itself is rebuilt in T-8.7; for now its taps route to the
    // surviving sections. Sources, review, and runs all fold into Library
    // (runs becomes an inspector in T-8.6), so processing/completed/failed
    // land there; the idle MCP chip still routes to Settings.
    switch stripState {
    case .processing, .completed, .runFailed:
      selection = .library
    case .idle:
      selection = .settings
    }
  }

  private func runDidStart() {
    summaryDecayTask?.cancel()
    summaryDecayTask = nil
    withAnimation(BrandMotion.standard) {
      completedSummary = nil
    }
    modulesFoundDuringRun = 0
    pendingReviewsAtRunStart = services.browseModel.approvalQueue.count
  }

  private func runDidEnd() {
    services.browseModel.refresh()
    services.sourceListModel.refresh()

    // A failed run shows the run-failed chip instead of a summary.
    guard services.processingModel.errorMessage == nil else {
      return
    }

    let summary = RunCompletionSummary(
      modulesAdded: modulesFoundDuringRun,
      needsReview: max(0, services.browseModel.approvalQueue.count - pendingReviewsAtRunStart)
    )

    withAnimation(BrandMotion.standard) {
      completedSummary = summary
    }

    summaryDecayTask?.cancel()
    summaryDecayTask = Task {
      try? await Task.sleep(for: Self.completedStateLifetime)
      guard !Task.isCancelled else {
        return
      }
      withAnimation(BrandMotion.smooth) {
        completedSummary = nil
      }
    }
  }

  // MARK: Whole-window drop target (T-8.5)

  private func handleDragEntered() {
    dropOverlayDismissTask?.cancel()
    dropOverlayDismissTask = nil
    if dropPhase == .hidden {
      withAnimation(BrandMotion.standard) {
        dropPhase = .dragOver
      }
    }
  }

  /// `dropUpdated` is the system's drop-ready negotiation (the mockup's
  /// `dragover` → `.drop.ready`): the card's dashed border goes solid green
  /// with the "— let go" affordance.
  private func handleDragUpdated() {
    if dropPhase == .dragOver {
      withAnimation(BrandMotion.standard) {
        dropPhase = .ready
      }
    }
  }

  private func handleDragExited() {
    scheduleDropOverlayDismissal(after: Self.dropExitDebounce)
  }

  private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
    guard !providers.isEmpty else {
      return false
    }

    // Keep the overlay up while the providers load; `finishDrop` decides
    // between dismissal and the in-overlay error.
    dropOverlayDismissTask?.cancel()
    dropOverlayDismissTask = nil

    DropPayloadLoader.loadFileURLs(from: providers) { urls in
      finishDrop(urls: urls)
    }

    return true
  }

  private func finishDrop(urls: [URL]) {
    do {
      let inserted = try services.dropZoneHandler.handleDrop(urls: urls)
      if inserted {
        withAnimation(BrandMotion.standard) {
          dropPhase = .hidden
        }
        // Same feedback as Dock drops (ux §4.4, D1): a successful drop from
        // any section lands the user in the Library.
        selection = .library
      } else {
        // Invalid drop (no directories): the error renders *inside* the
        // overlay before it dismisses — never as injected layout.
        withAnimation(BrandMotion.standard) {
          dropPhase = .error("Only folders can be added.")
        }
        scheduleDropOverlayDismissal(after: Self.dropErrorLifetime)
      }
    } catch {
      withAnimation(BrandMotion.standard) {
        dropPhase = .error(error.localizedDescription)
      }
      scheduleDropOverlayDismissal(after: Self.dropErrorLifetime)
    }
  }

  private func scheduleDropOverlayDismissal(after delay: Duration) {
    dropOverlayDismissTask?.cancel()
    dropOverlayDismissTask = Task {
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else {
        return
      }
      withAnimation(BrandMotion.standard) {
        dropPhase = .hidden
      }
    }
  }

  /// Dev-only screenshot hook, like `GUNK_DESIGN_GALLERY`: forces the drop
  /// overlay phase so both drag states can be captured without a live drag
  /// session. No-op in normal launches.
  private func applyDropOverlayDebugOverride() {
    switch ProcessInfo.processInfo.environment["GUNK_DEBUG_DROP_OVERLAY"] {
    case "over":
      dropPhase = .dragOver
    case "ready":
      dropPhase = .ready
    case "error":
      dropPhase = .error("Only folders can be added.")
    default:
      break
    }
  }

  // MARK: Detail

  private var detailContainer: some View {
    detailView(for: selection)
      .padding(.horizontal, detailHorizontalPadding)
      .padding(.vertical, BrandMetrics.Spacing.md)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      // Solid window background — no glass wash. Toolbox-v2 confines glass
      // to the floating controls layer; the old flush wash drew a hairline
      // rim around the whole content area.
      .background(BrandColors.backgroundPrimary.ignoresSafeArea())
      .toolbar(removing: .title)
      .toolbar {
        // D13: the window title stays "gunk" (its text is removed from the
        // toolbar because the sidebar wordmark already reads "gunk"); the
        // section name lives here instead.
        ToolbarItem(placement: .navigation) {
          Text(selection.title)
            .font(BrandTypography.headline)
            .foregroundStyle(BrandColors.textPrimary)
        }
        .sharedBackgroundVisibility(.hidden)
      }
      .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
  }

  /// The Modules browser needs 765pt internally (browser min 440 + detail
  /// min 300 + its own spacing), so it gets no extra horizontal padding to
  /// keep the sidebar from collapsing at the 960pt minimum (ux §4.6, D10).
  private var detailHorizontalPadding: CGFloat {
    selection == .library ? 0 : BrandMetrics.Spacing.lg
  }

  @ViewBuilder
  private func detailView(for section: AppSection) -> some View {
    switch section {
    case .library:
      // T-8.2 renders the existing Modules browser as-is; the sources and
      // review merges land in T-8.3/T-8.4.
      ModulesSectionView(
        model: services.browseModel,
        // Sources fold into the Library here (T-8.3): the source list, its
        // status, "N modules" navigation, delete, and add-folder are all
        // reachable from the Library header.
        sourceListModel: services.sourceListModel,
        processingModel: services.processingModel,
        dropZoneHandler: services.dropZoneHandler,
        // The shell's MCP snapshot drives the Agent-ready needs-setup copy
        // (ux §4.5, D8) so the detail line and the status strip can't
        // disagree.
        mcpNeedsSetup: (mcpStatus ?? mcpStatusProvider.status()).state == .needsSetup,
        onShowSettings: { selection = .settings }
      )
    case .marketplace:
      EmptyStateView(
        "Marketplace — coming soon",
        message: "Use other people's modules, and publish yours."
      )
    case .addModule:
      // Intentionally blank: the appbar's folder-picker intake moved here
      // (Mark's direction, T-8.3b follow-ups) and Mark designs this screen
      // later. Drag-and-drop and the empty-Library button still intake.
      Color.clear
    case .settings:
      SettingsView(storePath: services.store.databasePath)
    }
  }
}

// MARK: - Whole-window drop delegate (T-8.5)

/// Bridges the shell's `.onDrop` to the overlay state machine. A delegate
/// (instead of `isTargeted:`) because the overlay distinguishes the
/// drag-over-window and drop-ready states, and must survive the drag's end
/// to show invalid-drop feedback.
private struct WindowDropDelegate: DropDelegate {
  let dragEntered: () -> Void
  let dragUpdated: () -> Void
  let dragExited: () -> Void
  let receiveDrop: ([NSItemProvider]) -> Bool

  func validateDrop(info: DropInfo) -> Bool {
    info.hasItemsConforming(to: [UTType.fileURL])
  }

  func dropEntered(info: DropInfo) {
    dragEntered()
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    dragUpdated()
    return DropProposal(operation: .copy)
  }

  func dropExited(info: DropInfo) {
    dragExited()
  }

  func performDrop(info: DropInfo) -> Bool {
    receiveDrop(info.itemProviders(for: [UTType.fileURL]))
  }
}

// MARK: - Sections

private enum AppSection: String, CaseIterable, Identifiable {
  case library
  case marketplace
  case addModule
  case settings

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .library:
      return "Library"
    case .marketplace:
      return "Marketplace"
    case .addModule:
      return "Add module"
    case .settings:
      return "Settings"
    }
  }

  var systemImage: String {
    switch self {
    case .library:
      return "square.grid.2x2"
    case .marketplace:
      return "storefront"
    case .addModule:
      return "plus.square.on.square"
    case .settings:
      return "gearshape"
    }
  }
}

// MARK: - Sidebar row

private struct SidebarRow: View {
  enum Accessory: Equatable {
    case processing
    case count(Int)
  }

  let title: String
  let systemImage: String
  let isSelected: Bool
  let accessory: Accessory?
  /// Tap-through on the accessory itself (e.g. the Library count badge →
  /// the needs-approval scope); the rest of the row keeps `action`.
  var accessoryAction: (() -> Void)?
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        Image(systemName: systemImage)
          .font(BrandTypography.callout)
          .foregroundStyle(isSelected ? BrandColors.accent : BrandColors.textSecondary)
          .frame(width: BrandMetrics.Mark.small)

        Text(title)
          .font(BrandTypography.body)
          .foregroundStyle(isSelected ? BrandColors.textPrimary : BrandColors.textSecondary)

        Spacer(minLength: BrandMetrics.Spacing.xs)

        accessoryView
      }
      .padding(.horizontal, BrandMetrics.Spacing.sm)
      .padding(.vertical, BrandMetrics.Spacing.sm)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
          .fill(rowFill)
      )
      .contentShape(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(BrandMotion.quick) {
        isHovering = hovering
      }
    }
    .accessibilityLabel(title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  @ViewBuilder
  private var accessoryView: some View {
    switch accessory {
    case .processing:
      SidebarProcessingIndicator()
    case .count(let count):
      if let accessoryAction {
        Button(action: accessoryAction) {
          countBadge(count)
        }
        .buttonStyle(.plain)
        .help("Review modules that need approval")
        .accessibilityLabel("\(count) modules need approval. Review them.")
      } else {
        countBadge(count)
      }
    case nil:
      EmptyView()
    }
  }

  private func countBadge(_ count: Int) -> some View {
    Text("\(count)")
      .font(BrandTypography.caption.weight(.semibold))
      .monospacedDigit()
      .foregroundStyle(BrandColors.backgroundPrimary)
      .padding(.horizontal, BrandMetrics.Spacing.xs)
      .frame(minWidth: BrandMetrics.Mark.small, minHeight: BrandMetrics.Mark.small)
      .background(Capsule().fill(BrandColors.accent))
      .contentShape(Capsule())
  }

  private var rowFill: Color {
    if isSelected {
      return BrandColors.accent.opacity(BrandMetrics.Control.tintedFillOpacity)
    }
    if isHovering {
      return BrandColors.textPrimary.opacity(BrandMetrics.Control.hoverHighlightOpacity)
    }
    return .clear
  }
}

/// Pulsing accent dot shown on the Sources row while a run is active.
private struct SidebarProcessingIndicator: View {
  @State private var dimmed = false

  var body: some View {
    Circle()
      .fill(BrandColors.accent)
      .frame(width: BrandMetrics.Spacing.sm, height: BrandMetrics.Spacing.sm)
      .opacity(dimmed ? BrandMetrics.Control.disabledOpacity : 1)
      .onAppear {
        guard !BrandMotion.reduceMotion else {
          return
        }
        withAnimation(
          .easeInOut(duration: BrandMotion.Mascot.breatheDuration / 2)
            .repeatForever(autoreverses: true)
        ) {
          dimmed = true
        }
      }
      .accessibilityLabel("Processing")
  }
}

// MARK: - Status strip

private struct RunCompletionSummary: Equatable {
  let modulesAdded: Int
  let needsReview: Int
}

private enum ShellStripState: Equatable {
  case idle(mcp: SettingsStatusItem)
  case processing(subject: String, detail: String)
  case completed(RunCompletionSummary)
  case runFailed
}

/// The app's one global status location, pinned at the sidebar bottom
/// (ux §4.3, D2/D4/D8).
private struct ShellStatusStrip: View {
  let state: ShellStripState
  let onTap: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        icon

        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs / 2) {
          Text(title)
            .font(BrandTypography.callout)
            .foregroundStyle(BrandColors.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)

          if let subtitle {
            Text(subtitle)
              .font(BrandTypography.caption)
              .foregroundStyle(BrandColors.textSecondary)
              .lineLimit(1)
          }
        }

        Spacer(minLength: 0)
      }
      .padding(BrandMetrics.Spacing.sm)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
          .fill(tint.opacity(fillOpacity))
      )
      .contentShape(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(BrandMotion.quick) {
        isHovering = hovering
      }
    }
    .animation(BrandMotion.standard, value: state)
    .accessibilityLabel(accessibilityText)
  }

  @ViewBuilder
  private var icon: some View {
    switch state {
    case .idle(let mcp):
      Image(systemName: mcp.state == .ready ? "checkmark.circle" : "exclamationmark.triangle")
        .font(BrandTypography.callout)
        .foregroundStyle(mcp.state == .ready ? BrandColors.success : BrandColors.warning)
    case .processing:
      ProgressView()
        .controlSize(.small)
    case .completed:
      Image(systemName: "sparkles")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.accent)
    case .runFailed:
      Image(systemName: "xmark.circle")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.danger)
    }
  }

  private var title: String {
    switch state {
    case .idle(let mcp):
      return mcp.state == .ready ? "Agent connected" : "MCP not set up"
    case .processing(let subject, _):
      return subject
    case .completed(let summary):
      var text = "\(summary.modulesAdded) module\(summary.modulesAdded == 1 ? "" : "s") added"
      if summary.needsReview > 0 {
        text += " · \(summary.needsReview) need\(summary.needsReview == 1 ? "s" : "") review"
      }
      return text
    case .runFailed:
      return "Run failed"
    }
  }

  private var subtitle: String? {
    switch state {
    case .idle(let mcp):
      return mcp.state == .ready ? nil : "Connect Cursor → Settings"
    case .processing(_, let detail):
      return detail
    case .completed(let summary):
      return summary.needsReview > 0 ? "Review → Approval" : "View → Modules"
    case .runFailed:
      return "View → Runs"
    }
  }

  private var tint: Color {
    switch state {
    case .idle(let mcp):
      return mcp.state == .ready ? BrandColors.success : BrandColors.warning
    case .processing:
      return BrandColors.accent
    case .completed:
      return BrandColors.accent
    case .runFailed:
      return BrandColors.danger
    }
  }

  private var fillOpacity: Double {
    isHovering
      ? BrandMetrics.Control.tintedFillOpacity + BrandMetrics.Control.hoverHighlightOpacity
      : BrandMetrics.Control.tintedFillOpacity
  }

  private var accessibilityText: String {
    if let subtitle {
      return "\(title). \(subtitle)"
    }
    return title
  }
}

// MARK: - Section wrappers

@MainActor
private struct ModulesSectionView: View {
  let model: BrowseModel
  let sourceListModel: GunkListModel
  let processingModel: ProcessingModel
  let dropZoneHandler: DropZoneHandler
  let mcpNeedsSetup: Bool
  let onShowSettings: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
      if let errorMessage = model.errorMessage {
        Text(errorMessage)
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.danger)
          .textSelection(.enabled)
      }

      BrowseView(
        model: model,
        sourceListModel: sourceListModel,
        processingModel: processingModel,
        dropZoneHandler: dropZoneHandler,
        mcpNeedsSetup: mcpNeedsSetup,
        onShowSettings: onShowSettings
      )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
