import AppKit
import SwiftUI

@MainActor
struct BrowseView: View {
  let model: BrowseModel
  /// From the shared `MCPStatusProvider` (owned by the shell): when Cursor
  /// isn't wired up, the Agent-ready treatment flips to needs-setup copy
  /// that navigates to Settings (ux §4.5, D8).
  var mcpNeedsSetup = false
  var openBundle: (URL) -> Void = { NSWorkspace.shared.open($0) }
  var onShowSources: () -> Void = {}
  var onShowSettings: () -> Void = {}

  @State private var selectedGunkId: Int64?

  var body: some View {
    HStack(alignment: .top, spacing: BrandMetrics.Spacing.md) {
      browserPane
        .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)

      detailPane
        .frame(minWidth: 300, maxWidth: 440, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      // D12: run-completion freshness is handled by the shell, which calls
      // `BrowseModel.refresh()` when `isProcessing` flips false (T-7.6);
      // this refresh covers section re-entry.
      model.refresh()
      synchronizeSelection()
    }
    .onReceive(NotificationCenter.default.publisher(for: .gunkInserted)) { _ in
      model.refresh()
    }
    .onChange(of: model.sections) {
      synchronizeSelection()
    }
  }

  // MARK: Browser

  private var browserPane: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
      // Pinned filter bar (ux §3.2): lives outside the scroll view.
      filterBar

      if model.sections.isEmpty {
        EmptyStateView(
          "No modules yet",
          message: "Drop a folder on Sources or the Dock icon and gunk will decompose it into reusable modules."
        ) {
          Button("Go to Sources", action: onShowSources)
            .buttonStyle(.brandPrimary)
        }
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: BrandMetrics.Spacing.lg) {
            ForEach(model.sections) { section in
              sectionView(section)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.bottom, BrandMetrics.Spacing.sm)
        }
      }
    }
  }

  private var filterBar: some View {
    GlassCard(
      padding: BrandMetrics.Spacing.md,
      cornerRadius: BrandMetrics.Radius.medium,
      elevated: false
    ) {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
        Picker("Group", selection: groupBinding) {
          ForEach(BrowseGroup.allCases) { group in
            Text(group.label).tag(group)
          }
        }
        .pickerStyle(.segmented)
        .tint(BrandColors.accent)
        .frame(maxWidth: 360)

        HStack(spacing: BrandMetrics.Spacing.sm) {
          Picker("Source", selection: sourceBinding) {
            Text("All sources").tag(Int64?.none)
            ForEach(model.availableSources) { source in
              Text(source.name).tag(Int64?.some(source.id))
            }
          }
          .pickerStyle(.menu)
          .frame(maxWidth: 180)

          Picker("Tag", selection: tagBinding) {
            Text("All tags").tag(String?.none)
            ForEach(model.availableTags, id: \.self) { tag in
              Text(tag).tag(String?.some(tag))
            }
          }
          .pickerStyle(.menu)
          .frame(maxWidth: 150)

          Picker("Language", selection: languageBinding) {
            Text("All languages").tag(String?.none)
            ForEach(model.availableLanguages, id: \.self) { language in
              Text(language).tag(String?.some(language))
            }
          }
          .pickerStyle(.menu)
          .frame(maxWidth: 160)

          Picker("Approval", selection: approvalBinding) {
            ForEach(BrowseApprovalFilter.allCases) { approval in
              Text(approval.label).tag(approval)
            }
          }
          .pickerStyle(.menu)
          .frame(maxWidth: 170)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .controlSize(.small)
  }

  private func sectionView(_ section: BrowseSection) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      SectionHeader(section.tag)

      VStack(spacing: BrandMetrics.Spacing.sm) {
        ForEach(section.items) { item in
          ModuleRow(
            item: item,
            metadata: rowMetadata(for: item),
            isAgentReady: item.gunk.extractedAt != nil,
            isSelected: selectedGunkId == item.id,
            canOpenBundle: item.gunk.bundlePath != nil,
            onOpenBundle: {
              if let bundlePath = item.gunk.bundlePath {
                openBundle(URL(fileURLWithPath: bundlePath))
              }
            },
            onSelect: { selectedGunkId = item.id }
          )
        }
      }
    }
  }

  private func rowMetadata(for item: BrowseItem) -> String {
    [
      item.source.name,
      model.languageLabel(for: item),
      model.approvalLabel(for: item),
    ].joined(separator: " · ")
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

  private var sourceBinding: Binding<Int64?> {
    Binding(
      get: { model.filters.sourceId },
      set: { model.filters.sourceId = $0 }
    )
  }

  private var tagBinding: Binding<String?> {
    Binding(
      get: { model.filters.tag },
      set: { model.filters.tag = $0 }
    )
  }

  private var languageBinding: Binding<String?> {
    Binding(
      get: { model.filters.language },
      set: { model.filters.language = $0 }
    )
  }

  private var approvalBinding: Binding<BrowseApprovalFilter> {
    Binding(
      get: { model.filters.approval },
      set: { model.filters.approval = $0 }
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

// MARK: - Module row

private struct ModuleRow: View {
  let item: BrowseItem
  let metadata: String
  let isAgentReady: Bool
  let isSelected: Bool
  let canOpenBundle: Bool
  let onOpenBundle: () -> Void
  let onSelect: () -> Void

  @State private var isHovering = false

  var body: some View {
    GlassCard(
      padding: BrandMetrics.Spacing.md,
      cornerRadius: BrandMetrics.Radius.medium,
      elevated: false
    ) {
      HStack(alignment: .top, spacing: BrandMetrics.Spacing.md) {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
          Text(item.gunk.name)
            .font(BrandTypography.body.weight(.medium))
            .foregroundStyle(BrandColors.textPrimary)
            .lineLimit(1)

          if let purpose = item.gunk.purpose {
            Text(purpose)
              .font(BrandTypography.caption)
              .foregroundStyle(BrandColors.textSecondary)
              .lineLimit(2)
          }

          Text(metadata)
            .font(BrandTypography.caption)
            .foregroundStyle(BrandColors.textTertiary)
            .lineLimit(1)

          if !item.tags.isEmpty || isAgentReady {
            HStack(spacing: BrandMetrics.Spacing.xs) {
              // Compact row-level Agent-ready badge (ux §4.5 — kept unless
              // it's cut at the CP3 gate).
              if isAgentReady {
                StatusBadge("Agent-ready", variant: .success, systemImage: "sparkles")
              }

              ForEach(item.tags, id: \.self) { tag in
                TagChip(tag)
              }
            }
            .padding(.top, BrandMetrics.Spacing.xs)
          }
        }

        Spacer(minLength: BrandMetrics.Spacing.sm)

        Text((item.gunk.confidence ?? 0), format: .percent.precision(.fractionLength(0)))
          .font(BrandTypography.caption)
          .monospacedDigit()
          .foregroundStyle(BrandColors.textSecondary)

        // Rows keep *open bundle* only; re-run and delete live in the
        // detail pane (ux §3.2).
        Button(action: onOpenBundle) {
          Image(systemName: "folder")
        }
        .buttonStyle(.brandIcon)
        .disabled(!canOpenBundle)
        .help("Open bundle in Finder")
        .accessibilityLabel("Open bundle for \(item.gunk.name)")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .overlay {
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .strokeBorder(
          isSelected ? BrandColors.accent : BrandColors.textPrimary.opacity(
            isHovering ? BrandMetrics.Control.hoverHighlightOpacity : 0
          )
        )
        .allowsHitTesting(false)
    }
    .background {
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(BrandColors.accent.opacity(
          isSelected ? BrandMetrics.Control.tintedFillOpacity : 0
        ))
    }
    .contentShape(RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous))
    .onTapGesture(perform: onSelect)
    .onHover { hovering in
      withAnimation(BrandMotion.quick) {
        isHovering = hovering
      }
    }
    .animation(BrandMotion.quick, value: isSelected)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(item.gunk.name)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
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
