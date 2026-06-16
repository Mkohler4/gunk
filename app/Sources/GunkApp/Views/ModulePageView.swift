import AppKit
import SwiftUI

/// The full module page (T-10.4): clicking a module navigates here instead of
/// opening the interim inline pane. It carries every former `ModuleDetailView`
/// capability — the trust readout, files, bundle path + Open-in-Finder, and the
/// approve/reject review block — under a breadcrumb (`‹ Library › <source> ›
/// <module>`). The proof/run console + coverage ledger (module-run-v2) land on
/// this shell in T-10.5+; this task is the structural page that hosts them.
///
/// The page reads its `BrowseModuleDetail` live from the `BrowseModel` by
/// `gunkId` so approve/re-run/delete update in place (the model is
/// `@Observable`); a module that disappears underneath the page (deleted or
/// rejected) bounces back to the grid.
@MainActor
struct ModulePageView: View {
  let model: BrowseModel
  let gunkId: Int64
  /// From the shared `MCPSetupModel` (owned by the shell): drives the
  /// Agent-ready needs-setup line, exactly as the inline pane did.
  let mcpNeedsSetup: Bool
  var openBundle: (URL) -> Void = { NSWorkspace.shared.open($0) }
  /// Pops the module-page route back to the Library (the breadcrumb `‹ Library`
  /// and the post-destructive bounce both call this — the shell owns the path).
  let onBack: () -> Void
  let onShowMCPSetup: () -> Void
  /// Opens the shell-owned run inspector (Hard data fact 7): the provenance
  /// line's `view run →` reuses the extraction-run inspector, scoped to this
  /// module's source.
  let onShowRuns: (RunInspectorContext) -> Void

  @State private var showRejectConfirmation = false
  @State private var showDeleteConfirmation = false
  /// The breadcrumb's trailing trust chip appears only once the page is
  /// scrolled (per the second reference PNG) — at rest the verdict reads on
  /// the page state line instead, so the two never shout the same thing.
  @State private var showsStateChip = false

  /// Content stays in a readable left column rather than stretching the full
  /// (now sidebar-free) window width; the breadcrumb bar spans the full width.
  private static let contentMaxWidth: CGFloat = 900
  /// How far the page must scroll before the breadcrumb gains its trust chip.
  private static let chipRevealThreshold: CGFloat = 24

  var body: some View {
    Group {
      if let detail = model.detail(for: gunkId) {
        page(for: detail)
      } else {
        // The module vanished from under the page (deleted/rejected elsewhere,
        // or a refresh dropped it): return to the grid rather than render an
        // empty shell.
        Color.clear
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .onAppear(perform: onBack)
      }
    }
    .background(BrandColors.backgroundPrimary.ignoresSafeArea())
  }

  // MARK: Page

  private func page(for detail: BrowseModuleDetail) -> some View {
    let verdict = verdict(for: detail)

    return ScrollView {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
        stateLine(verdict)
        titleAndPurpose(detail)
        provenanceLine(detail)
        agentReadyLine(detail)
        reviewSection(detail)
        trustReadout(detail)
        callItSection(detail)
        bundleSection(detail)
        filesSection(detail)
        requirementsSection(detail)
        entrypointsSection(detail)
        verificationDetailsSection(detail)
        footerActions(detail)
      }
      .frame(maxWidth: Self.contentMaxWidth, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .padding(.horizontal, BrandMetrics.Spacing.lg)
      .padding(.bottom, BrandMetrics.Spacing.xl)
      .padding(.top, BrandMetrics.Spacing.sm)
      // Approve feedback in place: the review block leaves and the Agent-ready
      // line lands its success state on the same surface (carried over from
      // the inline pane unchanged).
      .animation(BrandMotion.settle, value: needsApproval(detail))
    }
    .onScrollGeometryChange(for: Bool.self) { geometry in
      geometry.contentOffset.y > Self.chipRevealThreshold
    } action: { _, isScrolled in
      withAnimation(BrandMotion.quick) {
        showsStateChip = isScrolled
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      ModulePageBreadcrumb(
        sourceName: detail.item.source.name,
        moduleName: detail.item.gunk.name,
        verdict: verdict,
        showsStateChip: showsStateChip,
        onBack: onBack
      )
      .padding(.horizontal, BrandMetrics.Spacing.lg)
      .padding(.top, BrandMetrics.Spacing.md)
      .padding(.bottom, BrandMetrics.Spacing.sm)
    }
  }

  // MARK: State line + title

  /// The module-run-v1 top state line: the trust verdict in its color, plus
  /// `· ★ Golden` when a golden example is pinned. Golden state is net-new and
  /// arrives with the proof loop (T-10.9+), so the marker stays dormant until
  /// then — the shell is ready for it.
  private func stateLine(_ verdict: ModuleCellState) -> some View {
    HStack(spacing: BrandMetrics.Spacing.xs) {
      Text(verdict.label)
        .font(BrandTypography.callout.weight(.semibold))
        .foregroundStyle(verdict.color)
    }
    .accessibilityLabel("Status: \(verdict.label)")
  }

  private func titleAndPurpose(_ detail: BrowseModuleDetail) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      Text(detail.item.gunk.name)
        .font(BrandTypography.title)
        .foregroundStyle(BrandColors.textPrimary)
        .lineLimit(3)

      if let purpose = detail.item.gunk.purpose {
        Text(purpose)
          .font(BrandTypography.body)
          .foregroundStyle(BrandColors.textSecondary)
      }
    }
  }

  /// `From <source> · <language> ·` provider mark `Extracted with <model> ·
  /// <provider> · view run →`. The `view run →` opens the extraction-run
  /// inspector scoped to this module's source (Hard data fact 7 — reused, not
  /// rebuilt).
  private func provenanceLine(_ detail: BrowseModuleDetail) -> some View {
    let provenance = model.provenance(for: detail.item)
    let language = detail.item.gunk.language ?? "Unknown language"

    return HStack(spacing: BrandMetrics.Spacing.sm) {
      Text("From \(detail.item.source.name) · \(language) ·")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.textSecondary)
        .lineLimit(1)

      if let provenance {
        ProviderMark(provider: provenance.provider, size: 18)

        Text("Extracted with \(provenance.model) · \(provenance.provider)")
          .font(BrandTypography.callout)
          .foregroundStyle(BrandColors.textSecondary)
          .lineLimit(1)
      }

      Button {
        onShowRuns(.source(detail.item.source.id))
      } label: {
        HStack(spacing: BrandMetrics.Spacing.xs / 2) {
          Text("view run")
          Image(systemName: "arrow.forward")
        }
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.accent)
      }
      .buttonStyle(.plain)
      .help("Inspect the extraction run for \(detail.item.source.name)")

      Spacer(minLength: 0)
    }
  }

  /// The MCP payoff truth line (ux §4.5, D8), derived from `extractedAt` — no
  /// new store state. The needs-setup variant opens the one-click setup sheet
  /// (T-8.10). Carried over verbatim from the inline pane.
  @ViewBuilder
  private func agentReadyLine(_ detail: BrowseModuleDetail) -> some View {
    if mcpNeedsSetup {
      Button(action: onShowMCPSetup) {
        HStack(spacing: BrandMetrics.Spacing.sm) {
          StatusBadge(
            "MCP not set up",
            variant: .warning,
            systemImage: "exclamationmark.triangle"
          )
          Text("Connect your agent")
            .font(BrandTypography.caption)
            .foregroundStyle(BrandColors.textSecondary)
        }
      }
      .buttonStyle(.plain)
      .help("Connect your agent through MCP")
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

  // MARK: Review (T-8.4 — approval, carried onto the page)

  @ViewBuilder
  private func reviewSection(_ detail: BrowseModuleDetail) -> some View {
    if needsApproval(detail) {
      DetailSection(title: "Needs approval", systemImage: "exclamationmark.triangle") {
        Text(confidenceContextLine(detail))
          .font(BrandTypography.callout)
          .foregroundStyle(BrandColors.textPrimary)

        Text("Approving extracts the module and makes it available to your agent through MCP.")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)

        HStack(spacing: BrandMetrics.Spacing.sm) {
          Button {
            // Approve feedback (T-8.4): the Agent-ready line transitions to its
            // success state in place; `settle` gives the landing overshoot.
            withAnimation(BrandMotion.settle) {
              model.approve(gunkId: detail.item.gunk.id)
            }
          } label: {
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
            Button("Reject and delete", role: .destructive) {
              model.reject(gunkId: detail.item.gunk.id)
              onBack()
            }
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

  // MARK: Call it (T-10.5 — copyable invocation snippet)

  /// The "Call it" snippet: a generated, one-glance "how do I use this" call
  /// built from the stored entrypoints + symbols, copyable in one click. Mono
  /// is allowed here — it is code. Hidden entirely when no entrypoint resolves,
  /// so the page never shows an empty code block.
  @ViewBuilder
  private func callItSection(_ detail: BrowseModuleDetail) -> some View {
    let snippets = model.callItSnippets(for: detail)
    if !snippets.isEmpty {
      CallItView(snippets: snippets)
    }
  }

  // MARK: Trust readout (3-up — module-run-v1)

  /// The 3-up trust readout (Confidence / Self-contained / Build), the
  /// toolbox-v2 detail-sheet spec resident on the page, plus the two
  /// explanatory notes the inline pane carried so no information is lost in the
  /// move.
  private func trustReadout(_ detail: BrowseModuleDetail) -> some View {
    DetailSection(title: "Trust readout", systemImage: "checkmark.seal") {
      HStack(alignment: .top, spacing: BrandMetrics.Spacing.md) {
        trustTile(title: "Confidence", status: confidenceStatus(detail))
        trustTile(title: "Self-contained", status: selfContainmentStatus(detail))
        trustTile(title: "Build", status: buildStatus(detail))
      }

      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        Text("Self-contained checks whether module-owned imports stay inside the bundle and claimed entrypoints are present.")
        Text("Build is separate: many gunks are reusable feature or library slices that still need a host project, installed packages, or runtime configuration.")
      }
      .font(BrandTypography.caption)
      .foregroundStyle(BrandColors.textSecondary)
      .padding(.top, BrandMetrics.Spacing.xs)
    }
  }

  private func trustTile(title: String, status: DetailStatus) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      Text(title)
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textTertiary)

      StatusBadge(status.label, variant: status.variant, systemImage: status.systemImage)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: Bundle / files

  private func bundleSection(_ detail: BrowseModuleDetail) -> some View {
    DetailSection(title: "Bundle path", systemImage: "folder") {
      if let bundlePath = detail.bundlePath {
        Text(bundlePath)
          .font(BrandTypography.mono)
          .foregroundStyle(BrandColors.textSecondary)
          .textSelection(.enabled)
          .lineLimit(3)
          .truncationMode(.middle)
      } else {
        emptyText("No extracted bundle path recorded.")
      }
    }
  }

  private func filesSection(_ detail: BrowseModuleDetail) -> some View {
    DetailSection(title: "Owned files", systemImage: "doc.text") {
      if detail.ownedFiles.isEmpty {
        emptyText("No owned files recorded.")
      } else {
        pathList(detail.ownedFiles)
      }
    }
  }

  // MARK: Requirements readout (T-10.6 — "to run this elsewhere, you need")

  /// The portability readout that replaces the old shared-dependency *paths*
  /// list: three honest rows — runtime, packages, env vars — derived from real
  /// manifest data persisted into the bundle's `gunk.yml`. Empty rows read
  /// `none`; nothing is invented. Packages are neutral chips (never earned
  /// green); env vars are mono because they are literal identifiers.
  private func requirementsSection(_ detail: BrowseModuleDetail) -> some View {
    let requirements = detail.requirements ?? .empty

    return DetailSection(title: "To run this elsewhere, you need", systemImage: "shippingbox") {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
        requirementRow(label: "Runtime") {
          if let runtime = requirements.runtime, !runtime.isEmpty {
            Text(runtime)
              .font(BrandTypography.callout)
              .foregroundStyle(BrandColors.textPrimary)
              .textSelection(.enabled)
          } else {
            noneValue
          }
        }

        requirementRow(label: "Packages") {
          if requirements.packages.isEmpty {
            noneValue
          } else {
            RequirementChips(values: requirements.packages, mono: false)
          }
        }

        requirementRow(label: "Env vars") {
          if requirements.env.isEmpty {
            noneValue
          } else {
            RequirementChips(values: requirements.env, mono: true)
          }
        }
      }
    }
  }

  private func requirementRow<Content: View>(
    label: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.md) {
      Text(label)
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textTertiary)
        .frame(width: 92, alignment: .leading)

      content()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var noneValue: some View {
    Text("none")
      .font(BrandTypography.callout)
      .foregroundStyle(BrandColors.textTertiary)
  }

  private func entrypointsSection(_ detail: BrowseModuleDetail) -> some View {
    DetailSection(title: "Entrypoints", systemImage: "arrow.right.circle") {
      if detail.entrypoints.isEmpty {
        emptyText("No confident entrypoints recorded.")
      } else {
        pathList(detail.entrypoints.map(\.label))
      }
    }
  }

  @ViewBuilder
  private func verificationDetailsSection(_ detail: BrowseModuleDetail) -> some View {
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

  // MARK: Footer actions

  /// Open in Finder / Re-run source / **Delete** (destructive, right-aligned,
  /// confirmed). Re-run and delete are heavyweight, so they get the deliberate
  /// footer surface rather than riding near the title (ux §3.2).
  private func footerActions(_ detail: BrowseModuleDetail) -> some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      if let bundlePath = detail.bundlePath {
        Button {
          openBundle(URL(fileURLWithPath: bundlePath))
        } label: {
          Label("Open in Finder", systemImage: "folder")
        }
        .buttonStyle(.brandSecondary)
        .help("Reveal the extracted bundle in Finder")
      }

      Button {
        model.reclassify(sourceId: detail.item.source.id)
      } label: {
        Label("Re-run source", systemImage: "arrow.triangle.2.circlepath")
      }
      .buttonStyle(.brandSecondary)
      .help("Re-run decomposition for \(detail.item.source.name)")

      Spacer(minLength: BrandMetrics.Spacing.sm)

      Button(role: .destructive) {
        showDeleteConfirmation = true
      } label: {
        Label("Delete", systemImage: "trash")
      }
      .buttonStyle(.brandDestructive)
      .help("Delete \(detail.item.gunk.name)")
      .confirmationDialog(
        "Delete \(detail.item.gunk.name)?",
        isPresented: $showDeleteConfirmation,
        titleVisibility: .visible
      ) {
        Button("Delete", role: .destructive) {
          model.delete(gunkId: detail.item.gunk.id)
          onBack()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Deleting permanently removes this module from your library. This cannot be undone.")
      }
    }
    .padding(.top, BrandMetrics.Spacing.sm)
  }

  // MARK: Derivations

  /// The page's verdict, computed with the exact rule the Library cell uses
  /// (`BrowseView.cellState`) so the page state line and the grid cell can
  /// never disagree.
  private func verdict(for detail: BrowseModuleDetail) -> ModuleCellState {
    if detail.item.gunk.extractedAt != nil {
      return .agentReady
    }

    if model.approvalFilter(for: detail.item) == .needsApproval {
      return .needsApproval
    }

    return .notInToolbox
  }

  private func needsApproval(_ detail: BrowseModuleDetail) -> Bool {
    model.approvalFilter(for: detail.item) == .needsApproval
  }

  /// "62% — below the 70% auto-accept threshold": confidence shown with the
  /// context of the gate that actually queued it (same source as the queue).
  private func confidenceContextLine(_ detail: BrowseModuleDetail) -> String {
    let confidence = (detail.item.gunk.confidence ?? 0)
      .formatted(.percent.precision(.fractionLength(0)))
    let threshold = model.confidenceThreshold
      .formatted(.percent.precision(.fractionLength(0)))
    return "\(confidence) — below the \(threshold) auto-accept threshold"
  }

  private func confidenceStatus(_ detail: BrowseModuleDetail) -> DetailStatus {
    guard let confidence = detail.item.gunk.confidence else {
      return DetailStatus(label: "—", variant: .neutral, systemImage: "questionmark.circle")
    }

    let label = confidence.formatted(.percent.precision(.fractionLength(0)))
    // Green only when the confidence cleared the auto-accept gate; below it the
    // module needed a human, so amber, matching the review block's framing.
    let variant: StatusBadge.Variant = confidence >= model.confidenceThreshold ? .success : .warning
    return DetailStatus(label: label, variant: variant, systemImage: "gauge.medium")
  }

  private func selfContainmentStatus(_ detail: BrowseModuleDetail) -> DetailStatus {
    guard let selfContainment = detail.selfContainment else {
      return DetailStatus(label: "Not verified", variant: .neutral, systemImage: "questionmark.circle")
    }

    if selfContainment.passed {
      return DetailStatus(label: "Passed", variant: .success, systemImage: "checkmark.circle")
    }

    return DetailStatus(label: "Needs attention", variant: .warning, systemImage: "exclamationmark.triangle")
  }

  private func buildStatus(_ detail: BrowseModuleDetail) -> DetailStatus {
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

  // MARK: Lists

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
}

// MARK: - Breadcrumb (the glass controls layer)

/// The module page's breadcrumb bar — the floating glass controls layer over
/// the solid graphite page: `‹ Library` back, then `<source> › <module>`. When
/// the page is scrolled it gains a compact trailing trust chip (per the second
/// reference PNG), so the verdict stays visible once the page state line has
/// scrolled away.
private struct ModulePageBreadcrumb: View {
  let sourceName: String
  let moduleName: String
  let verdict: ModuleCellState
  let showsStateChip: Bool
  let onBack: () -> Void

  var body: some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      Button(action: onBack) {
        HStack(spacing: BrandMetrics.Spacing.xs) {
          Image(systemName: "chevron.backward")
          Text("Library")
        }
        .font(BrandTypography.callout.weight(.medium))
        .foregroundStyle(BrandColors.accent)
      }
      .buttonStyle(.plain)
      .help("Back to the Library")
      .accessibilityLabel("Back to the Library")

      separator
      crumb(sourceName, color: BrandColors.textSecondary)
      separator
      crumb(moduleName, color: BrandColors.textPrimary)

      Spacer(minLength: BrandMetrics.Spacing.sm)

      if showsStateChip {
        StatusBadge(verdict.label, variant: verdict.badgeVariant, systemImage: verdict.badgeSystemImage)
          .transition(.opacity.combined(with: .move(edge: .trailing)))
      }
    }
    .padding(.horizontal, BrandMetrics.Spacing.md)
    .padding(.vertical, BrandMetrics.Spacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .brandGlass(cornerRadius: BrandMetrics.Radius.medium)
    .accessibilityElement(children: .contain)
  }

  private var separator: some View {
    Text("›")
      .font(BrandTypography.callout)
      .foregroundStyle(BrandColors.textTertiary)
  }

  private func crumb(_ text: String, color: Color) -> some View {
    Text(text)
      .font(BrandTypography.callout)
      .foregroundStyle(color)
      .lineLimit(1)
      .truncationMode(.middle)
  }
}

// MARK: - Call it snippet (T-10.5)

/// The "Call it" panel: a copyable invocation snippet in a mono block. When a
/// module exposes several entrypoints it shows the primary one with a quiet
/// picker to switch — never a wall of snippets (the refining-loop rule). The
/// Copy button writes the snippet to the pasteboard and flips to a brief
/// "Copied" confirmation (neutral — copying is not earned trust state, so it
/// stays off the accent-green vocabulary).
private struct CallItView: View {
  let snippets: [CallItSnippet]

  @State private var selectedID: CallItSnippet.ID?
  @State private var didCopy = false
  @State private var copyResetTask: Task<Void, Never>?

  private var selected: CallItSnippet {
    snippets.first { $0.id == selectedID } ?? snippets[0]
  }

  var body: some View {
    DetailSection(title: "Call it", systemImage: "curlybraces") {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
        header

        Text(selected.code)
          .font(BrandTypography.mono)
          .foregroundStyle(BrandColors.textPrimary)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(BrandMetrics.Spacing.md)
          .background(
            RoundedRectangle(cornerRadius: BrandMetrics.Radius.small, style: .continuous)
              .fill(BrandColors.backgroundSecondary)
          )
          .overlay(
            RoundedRectangle(cornerRadius: BrandMetrics.Radius.small, style: .continuous)
              .strokeBorder(BrandColors.separator)
          )
      }
    }
    .onDisappear { copyResetTask?.cancel() }
  }

  private var header: some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      if snippets.count > 1 {
        entrypointPicker
      }

      Spacer(minLength: 0)

      Button(action: copy) {
        Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
      }
      .buttonStyle(.brandSecondary)
      .help("Copy the snippet to the clipboard")
      .accessibilityLabel(didCopy ? "Copied snippet" : "Copy snippet")
    }
  }

  private var entrypointPicker: some View {
    Menu {
      ForEach(snippets) { snippet in
        Button(snippet.entrypoint.label) { selectedID = snippet.id }
      }
    } label: {
      HStack(spacing: BrandMetrics.Spacing.xs) {
        Text(selected.entrypoint.label)
          .lineLimit(1)
          .truncationMode(.middle)
        Image(systemName: "chevron.down")
      }
      .font(BrandTypography.callout)
      .foregroundStyle(BrandColors.textSecondary)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .help("Switch entrypoint")
  }

  private func copy() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(selected.code, forType: .string)

    withAnimation(BrandMotion.quick) { didCopy = true }
    copyResetTask?.cancel()
    copyResetTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.6))
      guard !Task.isCancelled else { return }
      withAnimation(BrandMotion.quick) { didCopy = false }
    }
  }
}

// MARK: - Trust verdict → badge mapping

private extension ModuleCellState {
  /// The breadcrumb chip's tinted-capsule variant for this verdict — separate
  /// from `color` (used for the plain state-line text) so the chip reads as a
  /// status badge, not a colored word.
  var badgeVariant: StatusBadge.Variant {
    switch self {
    case .agentReady:
      return .success
    case .needsApproval:
      return .warning
    case .notInToolbox:
      return .neutral
    }
  }

  var badgeSystemImage: String {
    switch self {
    case .agentReady:
      return "sparkles"
    case .needsApproval:
      return "exclamationmark.triangle"
    case .notInToolbox:
      return "circle.dashed"
    }
  }
}

// MARK: - Detail section + status (moved from the inline ModuleDetailView)

/// One status verdict — label, badge variant, glyph — for the trust readout
/// tiles and the verification rows.
struct DetailStatus {
  let label: String
  let variant: StatusBadge.Variant
  let systemImage: String
}

/// A flat glass detail card with a branded section header. Lifted out of the
/// retired inline `ModuleDetailView` so the page's sections keep their look.
struct DetailSection<Content: View>: View {
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

// MARK: - Requirement chips (T-10.6)

/// A wrapping row of neutral capsules for the requirements readout: packages
/// render as plain caption chips, env vars as mono chips (they are literal
/// identifiers). Neutral on purpose — requirements are facts, not earned trust,
/// so they stay off the accent-green vocabulary.
private struct RequirementChips: View {
  let values: [String]
  let mono: Bool

  var body: some View {
    FlowLayout(spacing: BrandMetrics.Spacing.xs) {
      ForEach(values, id: \.self) { value in
        Text(value)
          .font(mono ? BrandTypography.mono : BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
          .lineLimit(1)
          .padding(.horizontal, BrandMetrics.Spacing.sm)
          .padding(.vertical, BrandMetrics.Spacing.xs)
          .background(
            Capsule().fill(
              BrandColors.textSecondary.opacity(BrandMetrics.Control.tintedFillOpacity)
            )
          )
          .overlay(Capsule().strokeBorder(BrandColors.separator))
      }
    }
  }
}

/// A minimal flow layout: lays subviews left-to-right and wraps to the next row
/// when the proposed width runs out. Used for the requirements chips so a long
/// package list wraps instead of truncating or stretching the panel.
private struct FlowLayout: Layout {
  var spacing: CGFloat = BrandMetrics.Spacing.xs

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var rowWidth: CGFloat = 0
    var rowHeight: CGFloat = 0
    var totalHeight: CGFloat = 0
    var widestRow: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if rowWidth > 0 && rowWidth + spacing + size.width > maxWidth {
        widestRow = max(widestRow, rowWidth)
        totalHeight += rowHeight + spacing
        rowWidth = size.width
        rowHeight = size.height
      } else {
        rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
        rowHeight = max(rowHeight, size.height)
      }
    }

    widestRow = max(widestRow, rowWidth)
    totalHeight += rowHeight
    let resolvedWidth = maxWidth == .infinity ? widestRow : min(widestRow, maxWidth)
    return CGSize(width: resolvedWidth, height: totalHeight)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout Void
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > bounds.minX && x + size.width > bounds.maxX {
        x = bounds.minX
        y += rowHeight + spacing
        rowHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}
