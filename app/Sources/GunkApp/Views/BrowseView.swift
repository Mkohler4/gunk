import AppKit
import SwiftUI

@MainActor
struct BrowseView: View {
  let model: BrowseModel
  var openBundle: (URL) -> Void = { NSWorkspace.shared.open($0) }

  var body: some View {
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
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      model.refresh()
    }
    .onReceive(NotificationCenter.default.publisher(for: .gunkInserted)) { _ in
      model.refresh()
    }
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

        Text(item.source.name)
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .lineLimit(1)

        if let bundlePath = item.gunk.bundlePath {
          Text(bundlePath)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
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
}
