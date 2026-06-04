import SwiftUI

struct GunkListView: View {
  let model: GunkListModel

  var body: some View {
    Group {
      if model.sources.isEmpty {
        ContentUnavailableView(
          "No gunks yet",
          systemImage: "folder",
          description: Text("Drop a folder above to add it.")
        )
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(model.sources) { source in
              sourceRow(source)

              if source.id != model.sources.last?.id {
                Divider()
              }
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func sourceRow(_ source: Source) -> some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text(source.name)
          .font(.body.weight(.medium))
          .lineLimit(1)

        Text(source.path)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)

        Text(Date(timeIntervalSince1970: Double(source.droppedAt) / 1_000), style: .relative)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      Spacer(minLength: 8)

      Button(role: .destructive) {
        Task { @MainActor in
          model.delete(id: source.id)
        }
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .help("Remove \(source.name) from gunk")
      .accessibilityLabel("Remove \(source.name)")
    }
    .padding(.vertical, 10)
  }
}
