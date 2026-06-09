import SwiftUI

@MainActor
struct GunkListView: View {
  let model: GunkListModel
  let processingModel: ProcessingModel?

  init(
    model: GunkListModel,
    processingModel: ProcessingModel? = nil
  ) {
    self.model = model
    self.processingModel = processingModel
  }

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
    let status = processingModel?.status(for: source) ?? .complete
    let progress = processingModel?.progress(for: source)
    let errorMessage = processingModel?.error(for: source)

    return HStack(alignment: .top, spacing: 10) {
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

        if status == .processing, let progress {
          ProgressView(value: progress)
            .progressViewStyle(.linear)
            .frame(maxWidth: 260)
            .accessibilityLabel("Import progress")
        }

        if let errorMessage {
          Text(errorMessage)
            .font(.caption2)
            .foregroundStyle(.red)
            .lineLimit(2)
            .textSelection(.enabled)
        }
      }

      Spacer(minLength: 8)

      statusBadge(status)

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

  private func statusBadge(_ status: SourceImportStatus) -> some View {
    Text(status.label)
      .font(.caption2.bold())
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(statusColor(status).opacity(0.14))
      .foregroundStyle(statusColor(status))
      .clipShape(Capsule())
      .frame(minWidth: 76, alignment: .trailing)
      .accessibilityLabel("Import status \(status.label)")
  }

  private func statusColor(_ status: SourceImportStatus) -> Color {
    switch status {
    case .queued:
      return .secondary
    case .processing:
      return .orange
    case .complete:
      return .green
    case .failed:
      return .red
    }
  }
}
