import AppKit
import SwiftUI

@MainActor
struct BrowseView: View {
  let model: BrowseModel
  var openBundle: (URL) -> Void = { NSWorkspace.shared.open($0) }

  var body: some View {
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
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      model.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .gunkInserted)) { _ in
      model.refresh()
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
        .help("Open bundle")

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
    .padding(.vertical, 9)
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
}
