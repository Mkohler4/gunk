import AppKit
import SwiftUI

@MainActor
struct BrowseView: View {
  let model: BrowseModel
  var openBundle: (URL) -> Void = { NSWorkspace.shared.open($0) }

  @State private var selectedGunkId: Int64?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      browserPane
        .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)

      Divider()

      detailPane
        .frame(minWidth: 300, maxWidth: 440, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      model.refresh()
      synchronizeSelection()
    }
    .onReceive(NotificationCenter.default.publisher(for: .gunkInserted)) { _ in
      model.refresh()
      synchronizeSelection()
    }
    .onChange(of: model.sections) {
      synchronizeSelection()
    }
  }

  private var browserPane: some View {
    VStack(alignment: .leading, spacing: 12) {
      filterBar

      Group {
        if model.sections.isEmpty {
          ContentUnavailableView("No modules", systemImage: "square.grid.2x2")
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
              ForEach(model.sections) { section in
                sectionView(section)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var detailPane: some View {
    if let selectedGunkId,
       let detail = model.detail(for: selectedGunkId) {
      ModuleDetailView(detail: detail, openBundle: openBundle)
    } else {
      ContentUnavailableView(
        "Select a module",
        systemImage: "sidebar.right",
        description: Text("Open a module to inspect its files, bundle, and runability signals.")
      )
    }
  }

  private var filterBar: some View {
    VStack(alignment: .leading, spacing: 8) {
      Picker("Group", selection: groupBinding) {
        ForEach(BrowseGroup.allCases) { group in
          Text(group.label).tag(group)
        }
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 360)

      HStack(spacing: 10) {
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
    .controlSize(.small)
  }

  private func sectionView(_ section: BrowseSection) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(section.tag)
        .font(.headline)

      VStack(spacing: 0) {
        ForEach(section.items) { item in
          moduleRow(item)

          if item.id != section.items.last?.id {
            Divider()
          }
        }
      }
    }
  }

  private func moduleRow(_ item: BrowseItem) -> some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text(item.gunk.name)
          .font(.body.weight(.medium))
          .lineLimit(1)

        if let purpose = item.gunk.purpose {
          Text(purpose)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        HStack(spacing: 6) {
          metadataText(item.source.name)
          metadataText(model.languageLabel(for: item))
          metadataText(model.approvalLabel(for: item))
          metadataText(model.extractionLabel(for: item))
        }

        if let bundlePath = item.gunk.bundlePath {
          Text(bundlePath)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
        }

        tagRow(item.tags.isEmpty ? [BrowseModel.untaggedSection] : item.tags)
      }

      Spacer(minLength: 8)

      Text((item.gunk.confidence ?? 0), format: .percent.precision(.fractionLength(0)))
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 42, alignment: .trailing)

      HStack(spacing: 6) {
        Button {
          if let bundlePath = item.gunk.bundlePath {
            openBundle(URL(fileURLWithPath: bundlePath))
          }
        } label: {
          Image(systemName: "folder")
        }
        .buttonStyle(.borderless)
        .disabled(item.gunk.bundlePath == nil)
        .help("Open bundle in Finder")

        Button {
          model.reclassify(sourceId: item.source.id)
        } label: {
          Image(systemName: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.borderless)
        .help("Re-classify source")

        Button(role: .destructive) {
          model.delete(gunkId: item.gunk.id)
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .help("Delete module")
      }
      .frame(width: 78, alignment: .trailing)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 9)
    .background(
      selectedGunkId == item.id ? Color.accentColor.opacity(0.10) : Color.clear
    )
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .contentShape(Rectangle())
    .onTapGesture {
      selectedGunkId = item.id
    }
  }

  private func metadataText(_ text: String) -> some View {
    Text(text)
      .font(.caption2)
      .foregroundStyle(.tertiary)
      .lineLimit(1)
  }

  private func tagRow(_ tags: [String]) -> some View {
    HStack(spacing: 5) {
      ForEach(tags, id: \.self) { tag in
        Text(tag)
          .font(.caption2)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.secondary.opacity(0.12))
          .clipShape(Capsule())
      }
    }
  }

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

  private func synchronizeSelection() {
    let visibleItems = model.sections.flatMap(\.items)
    if let selectedGunkId,
       visibleItems.contains(where: { $0.id == selectedGunkId }) {
      return
    }

    selectedGunkId = visibleItems.first?.id
  }
}

private struct ModuleDetailView: View {
  let detail: BrowseModuleDetail
  let openBundle: (URL) -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header
        runabilitySection
        bundleSection
        filesSection
        sharedDependenciesSection
        entrypointsSection
        verificationDetailsSection
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(detail.item.gunk.name)
        .font(.title3.bold())
        .lineLimit(2)

      if let purpose = detail.item.gunk.purpose {
        Text(purpose)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 6) {
        pill(detail.item.source.name, color: .secondary)
        pill(detail.item.gunk.language ?? "Unknown language", color: .secondary)
        pill(
          (detail.item.gunk.confidence ?? 0).formatted(.percent.precision(.fractionLength(0))),
          color: .secondary
        )
      }
    }
  }

  private var runabilitySection: some View {
    VStack(alignment: .leading, spacing: 10) {
      DetailSectionHeader(title: "Runability", systemImage: "checkmark.seal")

      VStack(alignment: .leading, spacing: 5) {
        statusRow(
          title: "Self-contained for AI reuse",
          value: selfContainmentStatus.label,
          color: selfContainmentStatus.color,
          systemImage: selfContainmentStatus.systemImage
        )
        Text("Checks whether module-owned imports stay inside the bundle and claimed entrypoints are present.")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 5) {
        statusRow(
          title: "Standalone runnable project",
          value: buildStatus.label,
          color: buildStatus.color,
          systemImage: buildStatus.systemImage
        )
        Text("Separate from self-containment: many gunks are reusable feature or library slices that still need a host project, installed packages, or runtime configuration.")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var bundleSection: some View {
    DetailSection(title: "Bundle path", systemImage: "folder") {
      if let bundlePath = detail.bundlePath {
        Text(bundlePath)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .lineLimit(3)
          .truncationMode(.middle)

        Button {
          openBundle(URL(fileURLWithPath: bundlePath))
        } label: {
          Label("Open in Finder", systemImage: "folder")
        }
        .controlSize(.small)
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
            .font(.caption.bold())
          pathList(selfContainment.danglingImports.map(danglingImportLabel))
        }

        if !selfContainment.missingEntrypoints.isEmpty {
          Text("Missing entrypoints")
            .font(.caption.bold())
          pathList(selfContainment.missingEntrypoints.map(missingEntrypointLabel))
        }
      }
    }

    if let buildVerification = detail.buildVerification {
      DetailSection(title: "Build verification", systemImage: "hammer") {
        if let command = buildVerification.command {
          Text(command)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }

        Text(buildVerification.log)
          .font(.caption2.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .lineLimit(8)
      }
    }
  }

  private func statusRow(
    title: String,
    value: String,
    color: Color,
    systemImage: String
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Label(title, systemImage: systemImage)
        .font(.caption.weight(.medium))
      Spacer(minLength: 8)
      Text(value)
        .font(.caption2.bold())
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.14))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
  }

  private func pathList(_ values: [String]) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(values, id: \.self) { value in
        Text(value)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .lineLimit(2)
          .truncationMode(.middle)
      }
    }
  }

  private func emptyText(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.tertiary)
  }

  private func pill(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.caption2)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.12))
      .clipShape(Capsule())
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
      return DetailStatus(label: "Not verified", color: .secondary, systemImage: "questionmark.circle")
    }

    if selfContainment.passed {
      return DetailStatus(label: "Passed", color: .green, systemImage: "checkmark.circle")
    }

    return DetailStatus(label: "Needs attention", color: .orange, systemImage: "exclamationmark.triangle")
  }

  private var buildStatus: DetailStatus {
    guard let buildVerification = detail.buildVerification else {
      return DetailStatus(label: "Not verified", color: .secondary, systemImage: "questionmark.circle")
    }

    if buildVerification.skipped {
      return DetailStatus(label: "Skipped", color: .secondary, systemImage: "minus.circle")
    }

    if buildVerification.built {
      return DetailStatus(label: "Passed", color: .green, systemImage: "checkmark.circle")
    }

    return DetailStatus(label: "Failed", color: .red, systemImage: "xmark.circle")
  }
}

private struct DetailStatus {
  let label: String
  let color: Color
  let systemImage: String
}

private struct DetailSectionHeader: View {
  let title: String
  let systemImage: String

  var body: some View {
    Label(title, systemImage: systemImage)
      .font(.headline)
  }
}

private struct DetailSection<Content: View>: View {
  let title: String
  let systemImage: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      DetailSectionHeader(title: title, systemImage: systemImage)
      content
    }
  }
}
