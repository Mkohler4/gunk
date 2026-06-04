import SwiftUI

struct GunkListView: View {
  let model: GunkListModel

  var body: some View {
    Group {
      if model.gunks.isEmpty {
        ContentUnavailableView(
          "No gunks yet",
          systemImage: "folder",
          description: Text("Drop a folder above to add it.")
        )
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(model.gunks) { gunk in
              gunkRow(gunk)

              if gunk.id != model.gunks.last?.id {
                Divider()
              }
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func gunkRow(_ gunk: Gunk) -> some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text(gunk.name)
          .font(.body.weight(.medium))
          .lineLimit(1)

        Text(gunk.path)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)

        Text(Date(timeIntervalSince1970: Double(gunk.droppedAt) / 1_000), style: .relative)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      Spacer(minLength: 8)

      Button(role: .destructive) {
        Task { @MainActor in
          model.delete(id: gunk.id)
        }
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .help("Remove \(gunk.name) from gunk")
      .accessibilityLabel("Remove \(gunk.name)")
    }
    .padding(.vertical, 10)
  }
}
