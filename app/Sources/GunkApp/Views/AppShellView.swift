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
  /// One MCP model for the whole shell (T-8.10): the chip, the setup sheet,
  /// and Settings observe the same instance, so a wire/unwire from any
  /// surface re-checks all of them and they can never disagree.
  @StateObject private var mcpSetup = MCPSetupModel()
  @State private var showMCPSetup = false
  /// The run-end toast (T-8.7): the completion/failure moment is a floating
  /// overlay over the detail area, not a sidebar chip.
  @State private var toast: ShellRunToast?
  /// Snapshot of `BrowseModel.loadedGunkIds` when a run starts. The
  /// completion toast's "N modules added" is the store diff against this
  /// — the engine's mid-run `modulesFound` telemetry counts pre-gate
  /// candidates and must never become the completion claim (it once showed
  /// "14 added" on a run that persisted zero).
  @State private var gunkIdsBeforeRun: Set<Int64> = []
  @State private var pendingReviewsAtRunStart = 0
  @State private var toastDecayTask: Task<Void, Never>?

  /// Whole-window drop target state (T-8.5): the overlay phase is owned
  /// here, not by `isTargeted`, so it can outlive the drag to show the
  /// invalid-drop error inside the overlay before dismissing.
  @State private var dropPhase: WindowDropOverlay.Phase = .hidden
  @State private var dropOverlayDismissTask: Task<Void, Never>?

  /// Run inspector presentation (T-8.6): traces stopped being a tab, so the
  /// shell owns the sheet and every entry point (sources panel, module
  /// detail, the run-failed status element) requests it with a context.
  @State private var runInspectorContext: RunInspectorContext?

  /// How long the run-end toast floats before auto-dismissing (the old
  /// strip's completed-state lifetime, kept at 8s — ux §4.3).
  private static let toastLifetime: Duration = .seconds(8)

  /// SwiftUI `.onDrop` + window-level overlays can fight `NSWindow` first
  /// responder during drags; debounce the exit so the overlay never
  /// flickers mid-drag (T-8.5 refining loop).
  private static let dropExitDebounce: Duration = .milliseconds(100)
  /// How long the invalid-drop error stays inside the overlay before it
  /// dismisses.
  private static let dropErrorLifetime: Duration = .milliseconds(1600)

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
    .sheet(item: $runInspectorContext) { context in
      RunInspectorView(
        context: context,
        processingModel: services.processingModel,
        onClose: { runInspectorContext = nil }
      )
    }
    .sheet(isPresented: $showMCPSetup) {
      MCPSetupView(model: mcpSetup, onClose: { showMCPSetup = false })
    }
    .onAppear {
      services.sourceListModel.refresh()
      services.browseModel.refresh()
      mcpSetup.refresh()
      applyDropOverlayDebugOverride()
      applyRunInspectorDebugOverride()
      applyToastDebugOverride()
      applyMCPSetupDebugOverride()
      applyProcessingDebugOverride()
      // Appearing mid-run: snapshot what already exists so the completion
      // summary only counts what this run actually adds (mirrors
      // BrowseView's arrival-highlight snapshot).
      if services.processingModel.isProcessing {
        gunkIdsBeforeRun = services.browseModel.loadedGunkIds
      }
    }
    .onChange(of: selection) {
      mcpSetup.refresh()
    }
    .onChange(of: services.processingModel.isProcessing) { wasProcessing, isProcessing in
      if !wasProcessing, isProcessing {
        runDidStart()
      }
      if wasProcessing, !isProcessing {
        runDidEnd()
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
      // T-8.7 decomposed the old four-jobs-in-one status strip: a transient
      // processing element stacked above the persistent MCP chip. Run-end
      // feedback is the toast over the detail area, not a sidebar state.
      VStack(spacing: BrandMetrics.Spacing.sm) {
        if services.processingModel.isProcessing {
          // The one global live-run element (library-v2 §2; T-9.4): the
          // T-8.7 processing chip extended into a run panel that owns queue
          // depth. There is no second indicator — the pulsing Library-row
          // dot is its quiet echo, and the run-end toast is its terminal
          // frame. A flex spacer above absorbs the panel's height
          // (GlassSidebar), so nothing else moves when it appears (D15).
          ShellRunPanel(
            subject: processingStatus.subject,
            fractionComplete: processingStatus.fraction,
            modulesFound: services.processingModel.modulesFound,
            waitingCount: services.processingModel.waitingCount,
            nextWaitingName: services.processingModel.nextWaitingName
          ) {
            // Library owns processing visibility (T-8.2+).
            selection = .library
          }
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        ShellMCPChip(
          isConnected: mcpSetup.isAnyClientConnected,
          connectedSummary: mcpSetup.connectedSummary
        ) {
          // T-8.10: Connect opens the one-click setup sheet.
          showMCPSetup = true
        }
      }
      .animation(BrandMotion.standard, value: services.processingModel.isProcessing)
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

  // MARK: Processing element (T-8.7)

  /// Subject + progress for the live run panel. Processing is strictly
  /// one-at-a-time now (T-9.4), so there is exactly one active source — the
  /// old "N sources" branch is gone (queue depth lives in the panel's
  /// "N waiting" copy instead). The subject is that source's name; the
  /// fraction is its progress.
  private var processingStatus: (subject: String, fraction: Double) {
    let progress = services.processingModel.progressBySource

    let subject: String
    if let sourceId = progress.keys.first,
       let source = try? services.store.source(id: sourceId) {
      subject = source.name
    } else {
      subject = "Processing"
    }

    let fraction = progress.isEmpty
      ? 0
      : progress.values.reduce(0, +) / Double(progress.count)

    return (subject, fraction)
  }

  // MARK: Run-end toast (T-8.7)

  private func runDidStart() {
    dismissToast()
    gunkIdsBeforeRun = services.browseModel.loadedGunkIds
    pendingReviewsAtRunStart = services.browseModel.approvalQueue.count
  }

  private func runDidEnd() {
    services.browseModel.refresh()
    services.sourceListModel.refresh()

    let gunkIdsAfterRun = services.browseModel.loadedGunkIds
    let addedIds = gunkIdsAfterRun.subtracting(gunkIdsBeforeRun)

    let summary = RunCompletionSummary(
      gunkIdsBeforeRun: gunkIdsBeforeRun,
      gunkIdsAfterRun: gunkIdsAfterRun,
      pendingReviewsAtRunStart: pendingReviewsAtRunStart,
      pendingReviewsNow: services.browseModel.approvalQueue.count,
      addedProjectNames: services.browseModel.projectNames(for: addedIds)
    )

    presentToast(
      .forRunEnd(
        errorMessage: services.processingModel.errorMessage,
        summary: summary
      )
    )
  }

  private func presentToast(_ newToast: ShellRunToast) {
    // The settle spring is deliberate: the completion moment should land
    // like feedback, not blink in like a chip swap.
    withAnimation(BrandMotion.settle) {
      toast = newToast
    }

    toastDecayTask?.cancel()
    toastDecayTask = Task {
      try? await Task.sleep(for: Self.toastLifetime)
      guard !Task.isCancelled else {
        return
      }
      withAnimation(BrandMotion.smooth) {
        toast = nil
      }
    }
  }

  private func dismissToast() {
    toastDecayTask?.cancel()
    toastDecayTask = nil
    withAnimation(BrandMotion.smooth) {
      toast = nil
    }
  }

  private func handleToastAction(_ toast: ShellRunToast) {
    switch toast {
    case .success(let summary):
      selection = .library
      if let filter = toast.approvalFilterForView {
        // Reviews queued (M > 0): scope to needs-approval — the same wiring
        // as the sidebar badge tap-through.
        services.browseModel.filters.approval = filter
      } else if summary.addedProjectNames.count == 1,
                let project = summary.addedProjectNames.first {
        // Clean run, single project: reveal exactly what the run added by
        // searching its project name (the search now matches the folder).
        // Otherwise (multiple projects) View just lands on the Library.
        services.browseModel.filters.approval = .all
        services.browseModel.filters.query = project
      }
    case .noModules:
      // No action button is rendered for this state; nothing to do.
      break
    case .failure:
      // Same target as the old strip's runFailed tap: the run inspector at
      // the most recent failure (T-8.6) — no new plumbing.
      runInspectorContext = .mostRecentFailure
    }
    dismissToast()
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

  /// Dev-only screenshot hook (same family as `GUNK_DEBUG_SECTION`): opens
  /// the run inspector at launch with a given context — "all", "failure",
  /// or "source:<id>" — so scripted runs can capture it without staging a
  /// click path. No-op in normal launches.
  private func applyRunInspectorDebugOverride() {
    guard let value = ProcessInfo.processInfo.environment["GUNK_DEBUG_RUN_INSPECTOR"] else {
      return
    }

    if value == "failure" {
      runInspectorContext = .mostRecentFailure
    } else if value.hasPrefix("source:"), let sourceId = Int64(value.dropFirst("source:".count)) {
      runInspectorContext = .source(sourceId)
    } else {
      runInspectorContext = .all
    }
  }

  /// Dev-only screenshot hook (same family as `GUNK_DEBUG_RUN_INSPECTOR`):
  /// `GUNK_DEBUG_MCP_SETUP=1` opens the setup sheet at launch. Pair with
  /// `GUNK_DEBUG_MCP_HOME=<dir>` (see `MCPSetupModel`) so staged captures —
  /// including live Connect clicks — never touch real client configs.
  /// No-op in normal launches.
  private func applyMCPSetupDebugOverride() {
    if ProcessInfo.processInfo.environment["GUNK_DEBUG_MCP_SETUP"] == "1" {
      showMCPSetup = true
    }
  }

  /// Dev-only screenshot hook (same family as `GUNK_DEBUG_TOAST`): stages the
  /// live run panel (library-v2 §2; T-9.4) at launch against the first real
  /// source, without spawning the engine. `GUNK_DEBUG_PROCESSING=running`
  /// shows a single active run; `=queued` adds the "N waiting / next:" depth.
  /// No-op in normal launches, or when the store has no sources to attribute.
  private func applyProcessingDebugOverride() {
    guard let value = ProcessInfo.processInfo.environment["GUNK_DEBUG_PROCESSING"],
          let source = try? services.store.listSources().first else {
      return
    }

    services.processingModel.begin(sourceId: source.id)
    services.processingModel.update(sourceId: source.id, progress: 0.58, modulesFound: 2)

    if value == "queued" {
      services.processingModel.setWaitingSourceNames(["tts-playground", "audio-utils"])
    }
  }

  /// Dev-only screenshot hook (same family as `GUNK_DEBUG_DROP_OVERLAY`):
  /// stages the run-end toast at launch — "success" or "failure" — without
  /// a live run. No decay task, so scripted captures aren't racing the 8s
  /// auto-dismiss. No-op in normal launches.
  private func applyToastDebugOverride() {
    switch ProcessInfo.processInfo.environment["GUNK_DEBUG_TOAST"] {
    case "success":
      toast = .success(
        RunCompletionSummary(
          gunkIdsBeforeRun: [],
          gunkIdsAfterRun: [1, 2, 3, 4, 5],
          pendingReviewsAtRunStart: 0,
          pendingReviewsNow: 2
        )
      )
    case "failure":
      toast = .failure
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
      // Run-end toast (T-8.7): a floating glass overlay — never injected
      // layout. Docked bottom-center: at the 960pt minimum window the
      // module detail's action row owns the bottom-trailing corner, so
      // center-with-margin is the position that can never overlap it.
      .overlay(alignment: .bottom) {
        if let toast {
          RunToastView(
            toast: toast,
            onAction: { handleToastAction(toast) },
            onDismiss: dismissToast
          )
          .padding(.bottom, BrandMetrics.Spacing.lg)
          .transition(
            .asymmetric(
              insertion: .move(edge: .bottom).combined(with: .opacity),
              removal: .opacity
            )
          )
        }
      }
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
        // The shared MCP model drives the Agent-ready needs-setup copy
        // (ux §4.5, D8) so the detail line and the chip can't disagree.
        mcpNeedsSetup: !mcpSetup.isAnyClientConnected,
        onShowSettings: { selection = .settings },
        onShowMCPSetup: { showMCPSetup = true },
        onShowRuns: { runInspectorContext = $0 }
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
      SettingsView(storePath: services.store.databasePath, mcpSetup: mcpSetup)
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

// MARK: - Run completion summary

/// The truthful run-completion claim ("N modules added · M need review").
/// `modulesAdded` is a store diff — modules that exist now and didn't when
/// the run started. Engine telemetry (`ProcessingModel.modulesFound`) counts
/// pre-gate candidates and corrects *downward* as gates reject; it may label
/// live progress ("N found") but never the completion claim.
struct RunCompletionSummary: Equatable {
  let modulesAdded: Int
  let needsReview: Int
  /// The source project/folder name(s) the run added modules to. The View
  /// action uses this to scope the Library to exactly what the run produced
  /// (the search already matches the project name).
  let addedProjectNames: [String]

  init(
    gunkIdsBeforeRun: Set<Int64>,
    gunkIdsAfterRun: Set<Int64>,
    pendingReviewsAtRunStart: Int,
    pendingReviewsNow: Int,
    addedProjectNames: [String] = []
  ) {
    modulesAdded = gunkIdsAfterRun.subtracting(gunkIdsBeforeRun).count
    needsReview = max(0, pendingReviewsNow - pendingReviewsAtRunStart)
    self.addedProjectNames = addedProjectNames
  }
}

// MARK: - Run-end toast (T-8.7)

/// The run-end toast's state, derived once when a run finishes. Success
/// carries the truthful store-diff summary; a run that persisted nothing is
/// its own state (no count to brag about, nothing to view); failure carries
/// no numbers — engine telemetry never becomes a completion claim.
enum ShellRunToast: Equatable {
  case success(RunCompletionSummary)
  /// A run that ended cleanly but added no modules — distinct from success
  /// because "0 modules added" with a View button is a contradiction: there
  /// is nothing new to view.
  case noModules
  case failure

  static func forRunEnd(errorMessage: String?, summary: RunCompletionSummary) -> ShellRunToast {
    if errorMessage != nil {
      return .failure
    }
    return summary.modulesAdded == 0 ? .noModules : .success(summary)
  }

  var message: String {
    switch self {
    case .success(let summary):
      var text = "\(summary.modulesAdded) module\(summary.modulesAdded == 1 ? "" : "s") added"
      if summary.needsReview > 0 {
        text += " · \(summary.needsReview) need\(summary.needsReview == 1 ? "s" : "") review"
      }
      return text
    case .noModules:
      return "Run finished — no new modules"
    case .failure:
      return "Run failed"
    }
  }

  /// `nil` means the toast has no action button — the no-modules state has
  /// nowhere to send the user (there is nothing new to view).
  var actionLabel: String? {
    switch self {
    case .success:
      return "View"
    case .noModules:
      return nil
    case .failure:
      return "Inspect"
    }
  }

  /// The success View action scopes the Library to needs-approval only when
  /// the run actually queued reviews (M > 0) — the same wiring as the
  /// sidebar badge tap-through (T-8.4). A clean run's View instead reveals
  /// the run's additions by their project (see `handleToastAction`).
  var approvalFilterForView: BrowseApprovalFilter? {
    switch self {
    case .success(let summary):
      return summary.needsReview > 0 ? .needsApproval : nil
    case .noModules, .failure:
      return nil
    }
  }
}

/// Floating glass toast over the detail area's bottom edge: the completion
/// moment as feedback, with exactly two click targets — the action button
/// (View → Library / Inspect → run inspector) and the dismiss ×. Glass is
/// allowed here: the toast floats on the controls layer; it never sits in
/// layout.
private struct RunToastView: View {
  let toast: ShellRunToast
  let onAction: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    HStack(spacing: BrandMetrics.Spacing.md) {
      icon

      Text(toast.message)
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.textPrimary)
        .lineLimit(1)

      if let actionLabel = toast.actionLabel {
        Button(actionLabel, action: onAction)
          .buttonStyle(.brandSecondary)
      }

      Button(action: onDismiss) {
        Image(systemName: "xmark")
      }
      .buttonStyle(.brandIcon)
      .help("Dismiss")
      .accessibilityLabel("Dismiss")
    }
    .padding(.horizontal, BrandMetrics.Spacing.md)
    .padding(.vertical, BrandMetrics.Spacing.sm)
    // The toast always renders at its intrinsic width — the overlay must
    // never compress the message or the action label.
    .fixedSize()
    .brandGlass(cornerRadius: BrandMetrics.Radius.large)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(toast.message)
  }

  @ViewBuilder
  private var icon: some View {
    switch toast {
    case .success:
      // Accent green on the success moment — meaningful positive state.
      Image(systemName: "sparkles")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.accent)
    case .noModules:
      // Neutral: the run worked, it just produced nothing new — not a
      // success to celebrate, not a failure to flag.
      Image(systemName: "checkmark.circle")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.textSecondary)
    case .failure:
      Image(systemName: "xmark.circle")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.danger)
    }
  }
}

// MARK: - MCP chip (T-8.7)

/// Persistent MCP chip pinned at the sidebar bottom: one job — is the agent
/// wired in? Exactly two states. Healthy is *not* a button — a healthy chip
/// must never navigate anywhere; hover discloses which clients are wired
/// (and through which config). The warning state is the only click target
/// and opens the one-click setup sheet (T-8.10). Solid fills: the chip sits
/// on the sidebar surface — glass is reserved for floating layers.
private struct ShellMCPChip: View {
  let isConnected: Bool
  let connectedSummary: String
  let onConnect: () -> Void

  @State private var isHovering = false

  var body: some View {
    if isConnected {
      chipBody(
        systemImage: "checkmark.circle",
        tint: BrandColors.success,
        title: "Agent connected",
        subtitle: nil,
        hovering: false
      )
      .help("Connected: \(connectedSummary)")
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Agent connected. \(connectedSummary).")
    } else {
      Button(action: onConnect) {
        chipBody(
          systemImage: "exclamationmark.triangle",
          tint: BrandColors.warning,
          title: "MCP not set up",
          subtitle: "Connect",
          hovering: isHovering
        )
      }
      .buttonStyle(.plain)
      .onHover { hovering in
        withAnimation(BrandMotion.quick) {
          isHovering = hovering
        }
      }
      .accessibilityLabel("MCP not set up. Connect your agent.")
    }
  }

  private func chipBody(
    systemImage: String,
    tint: Color,
    title: String,
    subtitle: String?,
    hovering: Bool
  ) -> some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      Image(systemName: systemImage)
        .font(BrandTypography.callout)
        .foregroundStyle(tint)

      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs / 2) {
        Text(title)
          .font(BrandTypography.callout)
          .foregroundStyle(BrandColors.textPrimary)
          .lineLimit(1)

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
        .fill(
          tint.opacity(
            hovering
              ? BrandMetrics.Control.tintedFillOpacity + BrandMetrics.Control.hoverHighlightOpacity
              : BrandMetrics.Control.tintedFillOpacity
          )
        )
    )
    .contentShape(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
    )
  }
}

// MARK: - Run panel (library-v2 §2; T-9.4 — the one global live-run element)

/// The single global live-run element (library-v2 §2): the T-8.7 processing
/// element extended into a sidebar run panel that also owns **queue depth**.
/// It animates while a folder decomposes and reads as "alive" without stealing
/// the window. One job — show the live run + what's waiting behind it. Source
/// name, a spinner ring, determinate linear progress, modules found ("found"
/// is engine telemetry, allowed only here, never in the completion claim), and
/// "N waiting · next:" when the queue has more. Click lands in the Library;
/// the panel disappears when idle — completion feedback is the toast's job.
/// Glass-on-glass inside the already-glass sidebar (never on a content card).
private struct ShellRunPanel: View {
  let subject: String
  let fractionComplete: Double
  let modulesFound: Int
  /// Sources waiting behind the active run (library-v2 §2 queue depth).
  let waitingCount: Int
  let nextWaitingName: String?
  let onOpen: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: onOpen) {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
        HStack(spacing: BrandMetrics.Spacing.sm) {
          RunSpinnerRing()
            .frame(width: 18, height: 18)

          VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs / 2) {
            Text(subject)
              .font(BrandTypography.callout)
              .foregroundStyle(BrandColors.textPrimary)
              .lineLimit(1)
              .truncationMode(.middle)

            Text("decomposing · \(modulesFound) found")
              .font(BrandTypography.caption)
              .foregroundStyle(BrandColors.textSecondary)
              .lineLimit(1)
          }

          Spacer(minLength: BrandMetrics.Spacing.xs)

          // Green reads the positive progress (library-v2 §2): accent is
          // meaningful here — a live run advancing.
          Text("\(Int(fractionComplete * 100))%")
            .font(BrandTypography.callout.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(BrandColors.accent)
        }

        ProgressView(value: fractionComplete)
          .progressViewStyle(.linear)
          .controlSize(.small)
          .tint(BrandColors.accent)

        if waitingCount > 0 {
          queueDepth
        }
      }
      .padding(BrandMetrics.Spacing.sm)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        // Glass-on-glass: the run panel floats on the sidebar's controls
        // layer (library-v2 §2). A hover tint warms it without leaving glass.
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
          .fill(BrandColors.textPrimary.opacity(
            isHovering ? BrandMetrics.Control.hoverHighlightOpacity : 0
          ))
      )
      .brandGlass(cornerRadius: BrandMetrics.Radius.medium, elevated: false)
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
    .accessibilityLabel(accessibilityLabel)
  }

  /// "N waiting · next: <source>" (library-v2 §2): the queue depth, only when
  /// something is actually waiting. There is no "N sources running" — runs are
  /// strictly one-at-a-time (T-9.4).
  private var queueDepth: some View {
    HStack(spacing: BrandMetrics.Spacing.xs) {
      Text(waitingCount == 1 ? "1 waiting" : "\(waitingCount) waiting")
        .monospacedDigit()
        .fixedSize()

      if let nextWaitingName {
        Text("· next: \(nextWaitingName)")
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
    .font(BrandTypography.caption)
    .foregroundStyle(BrandColors.textTertiary)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var accessibilityLabel: String {
    var label = "Processing \(subject), \(Int(fractionComplete * 100)) percent, \(modulesFound) modules found."
    if waitingCount > 0 {
      label += " \(waitingCount) waiting."
      if let nextWaitingName {
        label += " Next: \(nextWaitingName)."
      }
    }
    label += " Open Library."
    return label
  }
}

/// A quiet spinner ring for the run panel (library-v2 §2): a 3/4 accent arc
/// that rotates while a run is live and reads as "working". Honors Reduce
/// Motion — it holds as a **static 3/4 arc** (presence without spin), the
/// locked reduced-motion fallback.
private struct RunSpinnerRing: View {
  @State private var isSpinning = false

  /// Track + arc weight, sized for the panel's compact ring.
  private static let lineWidth: CGFloat = 2
  /// The arc covers 3/4 of the circle (reads "working").
  private static let arcLength: CGFloat = 0.75
  private static let spinDuration: TimeInterval = 0.9

  var body: some View {
    ZStack {
      Circle()
        .stroke(
          BrandColors.textPrimary.opacity(BrandMetrics.Control.hoverHighlightOpacity),
          lineWidth: Self.lineWidth
        )

      Circle()
        .trim(from: 0, to: Self.arcLength)
        .stroke(
          BrandColors.accent,
          style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
        )
        .rotationEffect(.degrees(isSpinning ? 360 : 0))
    }
    .onAppear {
      guard !BrandMotion.reduceMotion else {
        return
      }
      withAnimation(.linear(duration: Self.spinDuration).repeatForever(autoreverses: false)) {
        isSpinning = true
      }
    }
    .accessibilityHidden(true)
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
  let onShowMCPSetup: () -> Void
  let onShowRuns: (RunInspectorContext) -> Void

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
        onShowSettings: onShowSettings,
        onShowMCPSetup: onShowMCPSetup,
        onShowRuns: onShowRuns
      )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
