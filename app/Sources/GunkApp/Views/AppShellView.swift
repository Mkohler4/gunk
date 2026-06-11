import SwiftUI

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

  /// How long the transient completed summary stays in the status strip
  /// before decaying back to the idle MCP chip (ux §4.3).
  private static let completedStateLifetime: Duration = .seconds(8)

  private let mcpStatusProvider = MCPStatusProvider()

  init(services: AppServices) {
    self.services = services
    // Landing rule (ux §4.1): applies at window creation only. No sources in
    // the store → Sources; otherwise → Modules. Never re-routes in-session.
    let hasSources = ((try? services.store.listSources())?.isEmpty == false)
    _selection = State(initialValue: hasSources ? .modules : .sources)
  }

  /// Fixed sidebar width. 192 (not the ux doc's nominal 200) because the
  /// Modules browser is 765pt wide at minimum, and 192 + 765 must fit the
  /// 960pt minimum window without squeezing (ux §4.6, D10).
  private static let sidebarWidth: CGFloat = 192

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
    .onAppear {
      services.sourceListModel.refresh()
      services.browseModel.refresh()
      mcpStatus = mcpStatusProvider.status()
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
      // and the shell navigates to Sources.
      selection = .sources
    }
  }

  // MARK: Sidebar

  private var sidebar: some View {
    GlassSidebar {
      BrandWordmark(style: .sidebar)
        .padding(.top, BrandMetrics.Spacing.xs)
    } content: {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        ForEach(AppSection.journeySections) { section in
          sidebarRow(section)
        }

        Rectangle()
          .fill(BrandColors.separator)
          .frame(height: 1)
          .padding(.vertical, BrandMetrics.Spacing.sm)
          .padding(.horizontal, BrandMetrics.Spacing.sm)

        ForEach(AppSection.utilitySections) { section in
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
      accessory: accessory(for: section)
    ) {
      selection = section
    }
  }

  private func accessory(for section: AppSection) -> SidebarRow.Accessory? {
    switch section {
    case .sources:
      // Processing indicator while any source is processing (ux §4.2, D2).
      return services.processingModel.isProcessing ? .processing : nil
    case .approval:
      // Pending-review count, hidden at zero (ux §4.2, D6). The queue is
      // computed by BrowseModel with the same membership rule the Approval
      // section renders, so badge and queue can never disagree.
      let count = services.browseModel.approvalQueue.count
      return count > 0 ? .count(count) : nil
    case .modules, .runs, .settings:
      return nil
    }
  }

  // MARK: Status strip (ux §4.3)

  private var stripState: ShellStripState {
    let processingModel = services.processingModel

    if processingModel.isProcessing {
      return .processing(label: processingLabel)
    }

    if let completedSummary {
      return .completed(completedSummary)
    }

    if processingModel.errorMessage != nil {
      return .runFailed
    }

    return .idle(mcp: mcpStatus ?? mcpStatusProvider.status())
  }

  private var processingLabel: String {
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

    return "\(subject) · \(percent)% · \(model.modulesFound) found"
  }

  private func handleStripTap() {
    switch stripState {
    case .processing:
      selection = .sources
    case .completed(let summary):
      selection = summary.needsReview > 0 ? .approval : .modules
    case .runFailed:
      selection = .runs
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

  // MARK: Detail

  private var detailContainer: some View {
    detailView(for: selection)
      .padding(.horizontal, detailHorizontalPadding)
      .padding(.vertical, BrandMetrics.Spacing.md)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background {
        // backgroundPrimary base with a flush glass wash on top — the
        // detail container's glass layering (ux §3.0).
        BrandColors.backgroundPrimary
          .brandGlass(cornerRadius: 0, elevated: false)
          .ignoresSafeArea()
      }
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
    selection == .modules ? 0 : BrandMetrics.Spacing.lg
  }

  @ViewBuilder
  private func detailView(for section: AppSection) -> some View {
    switch section {
    case .sources:
      SourcesSectionView(
        processingModel: services.processingModel,
        sourceListModel: services.sourceListModel,
        dropZoneHandler: services.dropZoneHandler
      )
    case .modules:
      ModulesSectionView(model: services.browseModel)
    case .approval:
      ApprovalSectionView(model: services.browseModel)
    case .runs:
      RunsView()
    case .settings:
      SettingsView(storePath: services.store.databasePath)
    }
  }
}

// MARK: - Sections

private enum AppSection: String, CaseIterable, Identifiable {
  case sources
  case modules
  case approval
  case runs
  case settings

  /// Journey order, separated from the utility pair (ux §4.2, D6).
  static let journeySections: [AppSection] = [.sources, .modules, .approval]
  static let utilitySections: [AppSection] = [.runs, .settings]

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .sources:
      return "Sources"
    case .modules:
      return "Modules"
    case .approval:
      return "Approval"
    case .runs:
      return "Runs"
    case .settings:
      return "Settings"
    }
  }

  var systemImage: String {
    switch self {
    case .sources:
      return "tray.and.arrow.down"
    case .modules:
      return "square.grid.2x2"
    case .approval:
      return "checkmark.seal"
    case .runs:
      return "clock.arrow.circlepath"
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
      Text("\(count)")
        .font(BrandTypography.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(BrandColors.backgroundPrimary)
        .padding(.horizontal, BrandMetrics.Spacing.xs)
        .frame(minWidth: BrandMetrics.Mark.small, minHeight: BrandMetrics.Mark.small)
        .background(Capsule().fill(BrandColors.accent))
    case nil:
      EmptyView()
    }
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
  case processing(label: String)
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
    case .processing(let label):
      return label
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
    case .processing:
      return nil
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
private struct SourcesSectionView: View {
  let processingModel: ProcessingModel
  let sourceListModel: GunkListModel
  let dropZoneHandler: DropZoneHandler

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      statusView

      DropZoneView(handler: dropZoneHandler)
        .frame(height: 170)

      GunkListView(model: sourceListModel)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear {
      sourceListModel.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .gunkInserted)) { _ in
      sourceListModel.refresh()
    }
  }

  @ViewBuilder
  private var statusView: some View {
    if processingModel.isProcessing {
      ProgressView("Processing")
    }

    if let errorMessage = processingModel.errorMessage {
      Text(errorMessage)
        .font(.caption)
        .foregroundStyle(.red)
        .textSelection(.enabled)
    }

    if let errorMessage = sourceListModel.errorMessage {
      Text(errorMessage)
        .font(.caption)
        .foregroundStyle(.red)
        .textSelection(.enabled)
    }
  }
}

@MainActor
private struct ModulesSectionView: View {
  let model: BrowseModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let errorMessage = model.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .textSelection(.enabled)
      }

      BrowseView(model: model)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

@MainActor
private struct ApprovalSectionView: View {
  let model: BrowseModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        if let errorMessage = model.errorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(.red)
            .textSelection(.enabled)
        }

        ApprovalQueueView(model: model)
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .onReceive(NotificationCenter.default.publisher(for: .gunkInserted)) { _ in
      model.refresh()
    }
  }
}
