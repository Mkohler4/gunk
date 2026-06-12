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
    .sheet(item: $runInspectorContext) { context in
      RunInspectorView(
        context: context,
        processingModel: services.processingModel,
        onClose: { runInspectorContext = nil }
      )
    }
    .onAppear {
      services.sourceListModel.refresh()
      services.browseModel.refresh()
      mcpStatus = mcpStatusProvider.status()
      applyDropOverlayDebugOverride()
      applyRunInspectorDebugOverride()
      applyToastDebugOverride()
      // Appearing mid-run: snapshot what already exists so the completion
      // summary only counts what this run actually adds (mirrors
      // BrowseView's arrival-highlight snapshot).
      if services.processingModel.isProcessing {
        gunkIdsBeforeRun = services.browseModel.loadedGunkIds
      }
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
          ShellProcessingChip(
            subject: processingStatus.subject,
            fractionComplete: processingStatus.fraction,
            modulesFound: services.processingModel.modulesFound
          ) {
            // Library owns processing visibility (T-8.2+).
            selection = .library
          }
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        ShellMCPChip(
          isConnected: (mcpStatus ?? mcpStatusProvider.status()).state == .ready,
          configPath: mcpStatusProvider.configURL.path
        ) {
          // Until T-8.10's one-click setup flow lands, Connect routes to
          // Settings exactly as the old strip did.
          selection = .settings
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

  /// Subject + averaged progress for the live processing element. The
  /// subject comes from `progressBySource` plus a store lookup; the fraction
  /// is the average across active sources (the old strip's computation,
  /// reused as-is).
  private var processingStatus: (subject: String, fraction: Double) {
    let progress = services.processingModel.progressBySource

    let subject: String
    if progress.count > 1 {
      subject = "\(progress.count) sources"
    } else if let sourceId = progress.keys.first,
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

    let summary = RunCompletionSummary(
      gunkIdsBeforeRun: gunkIdsBeforeRun,
      gunkIdsAfterRun: services.browseModel.loadedGunkIds,
      pendingReviewsAtRunStart: pendingReviewsAtRunStart,
      pendingReviewsNow: services.browseModel.approvalQueue.count
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
    case .success:
      selection = .library
      // Scope the Library to needs-approval only when the run queued
      // reviews (M > 0) — the same wiring as the sidebar badge tap-through.
      if let filter = toast.approvalFilterForView {
        services.browseModel.filters.approval = filter
      }
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
        // The shell's MCP snapshot drives the Agent-ready needs-setup copy
        // (ux §4.5, D8) so the detail line and the status strip can't
        // disagree.
        mcpNeedsSetup: (mcpStatus ?? mcpStatusProvider.status()).state == .needsSetup,
        onShowSettings: { selection = .settings },
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

// MARK: - Run completion summary

/// The truthful run-completion claim ("N modules added · M need review").
/// `modulesAdded` is a store diff — modules that exist now and didn't when
/// the run started. Engine telemetry (`ProcessingModel.modulesFound`) counts
/// pre-gate candidates and corrects *downward* as gates reject; it may label
/// live progress ("N found") but never the completion claim.
struct RunCompletionSummary: Equatable {
  let modulesAdded: Int
  let needsReview: Int

  init(
    gunkIdsBeforeRun: Set<Int64>,
    gunkIdsAfterRun: Set<Int64>,
    pendingReviewsAtRunStart: Int,
    pendingReviewsNow: Int
  ) {
    modulesAdded = gunkIdsAfterRun.subtracting(gunkIdsBeforeRun).count
    needsReview = max(0, pendingReviewsNow - pendingReviewsAtRunStart)
  }
}

// MARK: - Run-end toast (T-8.7)

/// The run-end toast's state, derived once when a run finishes. Success
/// carries the truthful store-diff summary; failure carries no numbers —
/// engine telemetry never becomes a completion claim.
enum ShellRunToast: Equatable {
  case success(RunCompletionSummary)
  case failure

  static func forRunEnd(errorMessage: String?, summary: RunCompletionSummary) -> ShellRunToast {
    errorMessage == nil ? .success(summary) : .failure
  }

  var message: String {
    switch self {
    case .success(let summary):
      var text = "\(summary.modulesAdded) module\(summary.modulesAdded == 1 ? "" : "s") added"
      if summary.needsReview > 0 {
        text += " · \(summary.needsReview) need\(summary.needsReview == 1 ? "s" : "") review"
      }
      return text
    case .failure:
      return "Run failed"
    }
  }

  var actionLabel: String {
    switch self {
    case .success:
      return "View"
    case .failure:
      return "Inspect"
    }
  }

  /// The success View action scopes the Library to needs-approval only when
  /// the run actually queued reviews (M > 0) — the same wiring as the
  /// sidebar badge tap-through (T-8.4). A clean run's View applies nothing.
  var approvalFilterForView: BrowseApprovalFilter? {
    switch self {
    case .success(let summary):
      return summary.needsReview > 0 ? .needsApproval : nil
    case .failure:
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

      Button(toast.actionLabel, action: onAction)
        .buttonStyle(.brandSecondary)

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
/// must never navigate anywhere; hover discloses the config path instead.
/// The warning state is the only click target and routes to setup (Settings,
/// until T-8.10's one-click flow lands). Solid fills: the chip sits on the
/// sidebar surface — glass is reserved for floating layers.
private struct ShellMCPChip: View {
  let isConnected: Bool
  let configPath: String
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
      .help("Configured at \(configPath)")
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Agent connected. MCP configured at \(configPath).")
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

// MARK: - Processing element (T-8.7)

/// Transient processing element stacked above the MCP chip: one job — show
/// the live run. Source name, linear progress, modules found ("found" is
/// engine telemetry, allowed only here, never in the completion claim).
/// Click lands in the Library; the chip disappears when idle — completion
/// feedback is the toast's job.
private struct ShellProcessingChip: View {
  let subject: String
  let fractionComplete: Double
  let modulesFound: Int
  let onOpen: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: onOpen) {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        HStack(spacing: BrandMetrics.Spacing.sm) {
          ProgressView()
            .controlSize(.small)

          Text(subject)
            .font(BrandTypography.callout)
            .foregroundStyle(BrandColors.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)

          Spacer(minLength: 0)
        }

        ProgressView(value: fractionComplete)
          .progressViewStyle(.linear)
          .controlSize(.small)
          .tint(BrandColors.accent)

        Text("\(Int(fractionComplete * 100))% · \(modulesFound) found")
          .font(BrandTypography.caption)
          .monospacedDigit()
          .foregroundStyle(BrandColors.textSecondary)
      }
      .padding(BrandMetrics.Spacing.sm)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
          .fill(
            isHovering
              ? BrandColors.backgroundElevatedHover
              : BrandColors.backgroundElevated
          )
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
    .accessibilityLabel("Processing \(subject), \(Int(fractionComplete * 100)) percent, \(modulesFound) modules found. Open Library.")
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
        onShowRuns: onShowRuns
      )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
