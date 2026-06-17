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

  /// Fixed width of the coverage-ledger column; the run console takes the rest.
  private static let ledgerWidth: CGFloat = 300

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
    return ScrollView {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
        titleRow(detail)
        agentReadyLine(detail)
        reviewSection(detail)
        if detail.bundlePath != nil {
          stage(detail)
        }
        HowThisWorksView(model: model, detail: detail)
        footerActions(detail)
        advancedFooter(detail)
      }
      // Fill the window: the page stretches to whatever width the resized
      // window gives it (the run console grows, the ledger keeps its rail), so
      // resizing actually reflows the page instead of leaving a dead margin.
      .frame(maxWidth: .infinity, alignment: .topLeading)
      .padding(.horizontal, BrandMetrics.Spacing.lg)
      .padding(.bottom, BrandMetrics.Spacing.xl)
      .padding(.top, BrandMetrics.Spacing.sm)
      // Approve feedback in place: the review block leaves and the Agent-ready
      // line lands its success state on the same surface (carried over from
      // the inline pane unchanged).
      .animation(BrandMotion.settle, value: needsApproval(detail))
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      // Full-bleed: the header is a glass strip fused to the top edge, not a
      // floating bordered card. Its own content padding aligns the crumb with
      // the page body; scrolled content reads through the glass beneath it.
      ModulePageBreadcrumb(
        sourceName: detail.item.source.name,
        moduleName: detail.item.gunk.name,
        readyToConnect: model.coverageState(for: detail.item.gunk.id).readyToConnect,
        onBack: onBack
      )
    }
  }

  // MARK: Title row (slim — does not compete with the console)

  /// The module-run-v2 slim title row: name + purpose on the left, a quiet
  /// `<language> capability` badge on the right. The trust verdict lives on the
  /// breadcrumb chip (and the ledger sign-off), so the page top no longer
  /// repeats it as a separate state line.
  private func titleRow(_ detail: BrowseModuleDetail) -> some View {
    HStack(alignment: .bottom, spacing: BrandMetrics.Spacing.md) {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        Text(detail.item.gunk.name)
          .font(BrandTypography.title)
          .foregroundStyle(BrandColors.textPrimary)
          .lineLimit(2)

        if let purpose = detail.item.gunk.purpose {
          Text(purpose)
            .font(BrandTypography.body)
            .foregroundStyle(BrandColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Spacer(minLength: 0)

      if let language = detail.item.gunk.language {
        HStack(spacing: BrandMetrics.Spacing.xs) {
          Text(language)
            .foregroundStyle(BrandColors.Provider.openAI)
          Text("capability")
            .foregroundStyle(BrandColors.textTertiary)
        }
        .font(BrandTypography.caption.weight(.semibold))
        .fixedSize()
      }
    }
  }

  // MARK: The stage (run console hero + coverage ledger)

  /// The page hero: the run console (module-run-v2, `RunConsoleStageView`) takes
  /// the lead column, the coverage ledger the trailing rail. One object, one
  /// focus — the developer runs, judges, and reads coverage without leaving it.
  private func stage(_ detail: BrowseModuleDetail) -> some View {
    HStack(alignment: .top, spacing: BrandMetrics.Spacing.xl) {
      RunConsoleStageView(model: model, detail: detail)
        .id(detail.item.gunk.id)
        .frame(maxWidth: .infinity, alignment: .top)

      CoverageLedgerView(model: model, gunkId: detail.item.gunk.id)
        .frame(width: Self.ledgerWidth, alignment: .top)
    }
  }

  // MARK: Advanced footer (module details, fully demoted)

  /// Everything that used to crowd the page — provenance, the trust readout,
  /// requirements, the "Call it" snippet, files, entrypoints, bundle path, and
  /// the verification details — collapses into one quiet disclosure
  /// (module-run-v2). Closed by default; the proof loop is the spine, the
  /// details are there *if you want them*.
  private func advancedFooter(_ detail: BrowseModuleDetail) -> some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
        provenanceLine(detail)
        callItSection(detail)
        trustReadout(detail)
        requirementsSection(detail)
        filesSection(detail)
        entrypointsSection(detail)
        bundleSection(detail)
        verificationDetailsSection(detail)
      }
      .padding(.top, BrandMetrics.Spacing.md)
    } label: {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        Image(systemName: "gearshape")
          .foregroundStyle(BrandColors.textTertiary)
        Text("Advanced — provenance, requirements, files & how it was extracted")
          .font(BrandTypography.callout)
          .foregroundStyle(BrandColors.textTertiary)
        Spacer(minLength: 0)
      }
    }
    .tint(BrandColors.textTertiary)
    .padding(.top, BrandMetrics.Spacing.sm)
    .overlay(alignment: .top) {
      Rectangle().fill(BrandColors.separator).frame(height: 1)
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

/// The module page's breadcrumb bar (module-run-v2 `.bar`) — a full-bleed glass
/// header strip fused to the top of the page (no bordered box, no separating
/// rule). A taller bar carrying the `‹ Library` back chip, the
/// `<source> › <module>` trail, and an always-on trailing **bar state** —
/// `Ready to connect` (green) once coverage earns it, `In review` (amber) until
/// then — mirroring the design's `.bar-state`.
private struct ModulePageBreadcrumb: View {
  let sourceName: String
  let moduleName: String
  /// Drives the trailing bar state (green/amber) — the coverage sign-off, not
  /// the trust verdict, exactly as the v2 design's `.bar-state` reads.
  let readyToConnect: Bool
  let onBack: () -> Void

  /// The bar's content height, before padding — keeps the glass bar tall enough
  /// to read as the design's 54px control strip rather than a thin link row.
  private static let barContentHeight: CGFloat = 30

  var body: some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      backChip

      separator
      crumb(sourceName, color: BrandColors.textTertiary, weight: .regular)
      separator
      crumb(moduleName, color: BrandColors.textPrimary, weight: .semibold)

      Spacer(minLength: BrandMetrics.Spacing.sm)

      barState
    }
    .frame(minHeight: Self.barContentHeight)
    .padding(.horizontal, BrandMetrics.Spacing.lg)
    .padding(.vertical, BrandMetrics.Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    // No box, no separating rule: a borderless, shadowless glass strip (the
    // "glass neomorphic" header) rather than a bordered card.
    .headerGlass()
    .accessibilityElement(children: .contain)
  }

  /// The back affordance as a subtle pill chip (design `.back`): a quiet white
  /// fill + hairline, white text — not an accent-green link.
  private var backChip: some View {
    Button(action: onBack) {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        Image(systemName: "chevron.backward")
        Text("Library")
      }
      .font(BrandTypography.callout.weight(.semibold))
      .foregroundStyle(BrandColors.textPrimary)
      .padding(.horizontal, BrandMetrics.Spacing.md)
      .padding(.vertical, BrandMetrics.Spacing.sm)
      .background(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.small, style: .continuous)
          .fill(Color.white.opacity(0.06))
      )
      .overlay(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.small, style: .continuous)
          .strokeBorder(Color.white.opacity(0.09))
      )
    }
    .buttonStyle(.plain)
    .help("Back to the Library")
    .accessibilityLabel("Back to the Library")
  }

  /// The always-on trailing state: a colored dot + label (design `.bar-state`).
  private var barState: some View {
    let color = readyToConnect ? BrandColors.accent : BrandColors.warning
    return HStack(spacing: BrandMetrics.Spacing.xs) {
      Circle()
        .fill(color)
        .frame(width: 8, height: 8)
      Text(readyToConnect ? "Ready to connect" : "In review")
        .font(BrandTypography.callout.weight(.semibold))
        .foregroundStyle(color)
    }
    .fixedSize()
  }

  private var separator: some View {
    Text("›")
      .font(BrandTypography.callout)
      .foregroundStyle(BrandColors.textTertiary)
  }

  private func crumb(_ text: String, color: Color, weight: Font.Weight) -> some View {
    Text(text)
      .font(BrandTypography.callout.weight(weight))
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

// MARK: - How this works (T-10.14)

/// The single quiet "How this works" disclosure: the long-form, AI-written
/// analysis of the module's design (data flow, key functions, what it touches,
/// its limits — the long form of the T-10.8 input signature). Closed by
/// default; opening reads the cached analysis (`BrowseModel.analysis(for:)`),
/// so it is instant and never triggers a live model call. Older/unanalyzed
/// modules show a quiet "not analyzed yet" with a single on-demand "Analyze"
/// action — a model is never auto-summoned on open. Lives inside the page (no
/// modal, no chatbot); mono is used **only** for the code references inside it.
private struct HowThisWorksView: View {
  let model: BrowseModel
  let detail: BrowseModuleDetail

  /// The screenshot hook (`GUNK_DEBUG_HOW_IT_WORKS=open|missing|closed`), read
  /// once so the open/missing states can be captured without a real model call
  /// or a seeded store row. Absent in normal runs.
  private enum DebugState: String {
    case open
    case missing
    case closed
  }

  private let debugState: DebugState?
  @State private var isExpanded: Bool

  init(model: BrowseModel, detail: BrowseModuleDetail) {
    self.model = model
    self.detail = detail
    let debug = ProcessInfo.processInfo.environment["GUNK_DEBUG_HOW_IT_WORKS"]
      .flatMap(DebugState.init(rawValue:))
    self.debugState = debug
    // Stage the open/missing states expanded for the screenshot hook; closed by
    // default otherwise (the disclosure is a quiet, opt-in affordance).
    _isExpanded = State(initialValue: debug == .open || debug == .missing)
  }

  /// The analysis to render: the debug sample when the `open` hook is set,
  /// otherwise the real cache. `missing` forces the not-analyzed branch.
  private var analysis: ModuleAnalysis? {
    if debugState == .missing {
      return nil
    }
    if debugState == .open {
      return .sample
    }
    return model.analysis(for: detail.item.gunk.id)
  }

  private var isAnalyzing: Bool {
    model.isAnalyzing(detail.item.gunk.id)
  }

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      Group {
        if let analysis {
          analysisBody(analysis)
        } else {
          notAnalyzed
        }
      }
      .padding(.top, BrandMetrics.Spacing.md)
    } label: {
      HStack(spacing: BrandMetrics.Spacing.sm) {
        Image(systemName: "wand.and.stars")
          .foregroundStyle(BrandColors.textTertiary)
        Text("How this works")
          .font(BrandTypography.callout)
          .foregroundStyle(BrandColors.textTertiary)
        Spacer(minLength: 0)
      }
    }
    .tint(BrandColors.textTertiary)
    .padding(.top, BrandMetrics.Spacing.sm)
    .overlay(alignment: .top) {
      Rectangle().fill(BrandColors.separator).frame(height: 1)
    }
  }

  // MARK: Analysed

  private func analysisBody(_ analysis: ModuleAnalysis) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
      if !analysis.content.summary.isEmpty {
        Text(analysis.content.summary)
          .font(BrandTypography.body)
          .foregroundStyle(BrandColors.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if !analysis.content.dataFlow.isEmpty {
        section("Data flow") {
          VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
            ForEach(Array(analysis.content.dataFlow.enumerated()), id: \.offset) { index, step in
              HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.sm) {
                Text("\(index + 1).")
                  .font(BrandTypography.caption.weight(.semibold))
                  .foregroundStyle(BrandColors.textTertiary)
                Text(step)
                  .font(BrandTypography.callout)
                  .foregroundStyle(BrandColors.textSecondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
        }
      }

      if !analysis.content.keyFunctions.isEmpty {
        section("Key functions") {
          VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
            ForEach(Array(analysis.content.keyFunctions.enumerated()), id: \.offset) { _, function in
              VStack(alignment: .leading, spacing: 2) {
                // Mono only here — these are code references.
                Text(function.name)
                  .font(BrandTypography.mono)
                  .foregroundStyle(BrandColors.textPrimary)
                  .textSelection(.enabled)
                if !function.role.isEmpty {
                  Text(function.role)
                    .font(BrandTypography.caption)
                    .foregroundStyle(BrandColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
            }
          }
        }
      }

      if !analysis.content.touches.isEmpty {
        section("What it touches") {
          bulletList(analysis.content.touches)
        }
      }

      if !analysis.content.limits.isEmpty {
        section("Known limits") {
          bulletList(analysis.content.limits)
        }
      }

      analyzedFooter(analysis)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The honesty footer — which model wrote it. Quiet (tertiary); the analysis
  /// is a convenience, not earned trust, so it stays off the accent vocabulary.
  @ViewBuilder
  private func analyzedFooter(_ analysis: ModuleAnalysis) -> some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      if let model = analysis.model, !model.isEmpty {
        Text("Analyzed with \(model)")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textTertiary)
      }
      Spacer(minLength: 0)
      Button("Re-analyze", action: analyze)
        .buttonStyle(.plain)
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textTertiary)
        .disabled(isAnalyzing)
        .help("Generate the analysis again")
    }
    .padding(.top, BrandMetrics.Spacing.xs)
  }

  // MARK: Not analysed

  private var notAnalyzed: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      if isAnalyzing {
        HStack(spacing: BrandMetrics.Spacing.sm) {
          ProgressView().controlSize(.small)
          Text("Analyzing…")
            .font(BrandTypography.callout)
            .foregroundStyle(BrandColors.textSecondary)
        }
      } else {
        Text("Not analyzed yet.")
          .font(BrandTypography.callout)
          .foregroundStyle(BrandColors.textSecondary)
        Text("Generate a short, AI-written walkthrough of how this module is built.")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textTertiary)
          .fixedSize(horizontal: false, vertical: true)
        Button(action: analyze) {
          Label("Analyze this module", systemImage: "wand.and.stars")
        }
        .buttonStyle(.brandSecondary)
        .help("Generate the \"How this works\" analysis")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func analyze() {
    // Debug states are static screenshots — never fire a real model call.
    guard debugState == nil else { return }
    Task { await model.generateAnalysis(for: detail) }
  }

  // MARK: Building blocks

  private func section<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      Text(title)
        .font(BrandTypography.caption.weight(.semibold))
        .foregroundStyle(BrandColors.textTertiary)
      content()
    }
  }

  private func bulletList(_ values: [String]) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      ForEach(Array(values.enumerated()), id: \.offset) { _, value in
        HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.sm) {
          Text("•")
            .font(BrandTypography.callout)
            .foregroundStyle(BrandColors.textTertiary)
          Text(value)
            .font(BrandTypography.callout)
            .foregroundStyle(BrandColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
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
