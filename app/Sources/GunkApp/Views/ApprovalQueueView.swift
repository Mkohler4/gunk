import SwiftUI

@MainActor
struct ApprovalQueueView: View {
  let model: BrowseModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Approval queue")
        .font(.headline)

      if model.approvalQueue.isEmpty {
        Text("No modules waiting for review.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        VStack(spacing: 0) {
          ForEach(model.approvalQueue) { item in
            queueRow(item)

            if item.id != model.approvalQueue.last?.id {
              Divider()
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear {
      model.refresh()
    }
  }

  private func queueRow(_ item: BrowseItem) -> some View {
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
      }

      Spacer(minLength: 8)

      Text((item.gunk.confidence ?? 0), format: .percent.precision(.fractionLength(0)))
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 42, alignment: .trailing)

      HStack(spacing: 6) {
        Button {
          model.reclassify(sourceId: item.source.id)
        } label: {
          Image(systemName: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.borderless)
        .help("Re-run decomposition for \(item.source.name)")
        .accessibilityLabel("Re-run decomposition for \(item.source.name)")

        Button {
          model.approve(gunkId: item.gunk.id)
        } label: {
          Image(systemName: "checkmark.circle")
        }
        .buttonStyle(.borderless)
        .help("Approve module")
        .accessibilityLabel("Approve \(item.gunk.name)")

        Button(role: .destructive) {
          model.reject(gunkId: item.gunk.id)
        } label: {
          Image(systemName: "xmark.circle")
        }
        .buttonStyle(.borderless)
        .help("Reject and remove module")
        .accessibilityLabel("Reject and remove \(item.gunk.name)")
      }
      .frame(width: 78, alignment: .trailing)
    }
    .padding(.vertical, 9)
  }
}
