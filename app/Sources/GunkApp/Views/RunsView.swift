import SwiftUI

/// Debug panel that surfaces the per-run traces the engine writes to
/// `~/.gunk/runs`. This is the "see what's going on" view: every run, its
/// stages with timings/counts, and the accept/approve/reject summary.
@MainActor
struct RunsView: View {
  private let traceStore: RunTraceStore

  @State private var traces: [RunTrace] = []
  @State private var selectedRunId: String?

  init(traceStore: RunTraceStore = RunTraceStore()) {
    self.traceStore = traceStore
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      runList
        .frame(width: 180)

      Divider()

      detail
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onAppear(perform: reload)
  }

  private var runList: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Runs")
          .font(.headline)
        Spacer()
        Button(action: reload) {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .help("Refresh")
      }

      if traces.isEmpty {
        Text("No runs yet. Drop a folder to start.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        List(traces, selection: $selectedRunId) { trace in
          VStack(alignment: .leading, spacing: 2) {
            Text(trace.sourceName)
              .font(.subheadline)
              .lineLimit(1)
            HStack(spacing: 6) {
              statusBadge(trace.status)
              Text(trace.startedAt, format: .dateTime.hour().minute().second())
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
          .tag(trace.runId)
        }
        .listStyle(.sidebar)
      }
    }
  }

  @ViewBuilder
  private var detail: some View {
    if let trace = selectedTrace {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text(trace.sourceName)
              .font(.title3.bold())
            Text("\(trace.provider) · \(trace.model)")
              .font(.caption)
              .foregroundStyle(.secondary)
            HStack(spacing: 8) {
              statusBadge(trace.status)
              if let durationMs = trace.durationMs {
                Text("\(Int(durationMs)) ms")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }

          if let error = trace.error {
            Text(error)
              .font(.caption)
              .foregroundStyle(.red)
          }

          summaryRow(trace.summary)

          Divider()

          Text("Stages")
            .font(.headline)
          ForEach(trace.stages) { stage in
            stageRow(stage)
          }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    } else {
      Text("Select a run to inspect its stages.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func summaryRow(_ summary: RunTrace.Summary) -> some View {
    HStack(spacing: 16) {
      countPill("Accepted", summary.accepted, color: .green)
      countPill("Needs approval", summary.needsApproval, color: .orange)
      countPill("Rejected", summary.rejected, color: .red)
    }
  }

  private func stageRow(_ stage: RunTrace.Stage) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(stage.stage)
          .font(.subheadline.monospaced())
        Spacer()
        Text("\(Int(stage.durationMs)) ms")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      if !stage.counts.isEmpty {
        Text(stage.counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "  "))
          .font(.caption2.monospaced())
          .foregroundStyle(.secondary)
      }
      if let error = stage.error {
        Text(error)
          .font(.caption2)
          .foregroundStyle(.red)
      }
    }
    .padding(8)
    .background(stage.status == "error" ? Color.red.opacity(0.08) : Color.secondary.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private func countPill(_ label: String, _ value: Int, color: Color) -> some View {
    VStack(spacing: 2) {
      Text("\(value)")
        .font(.headline)
        .foregroundStyle(color)
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }

  private func statusBadge(_ status: String) -> some View {
    let color: Color
    switch status {
    case "succeeded":
      color = .green
    case "failed":
      color = .red
    default:
      color = .orange
    }

    return Text(status)
      .font(.caption2.bold())
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.15))
      .foregroundStyle(color)
      .clipShape(Capsule())
  }

  private var selectedTrace: RunTrace? {
    guard let selectedRunId else { return traces.first }
    return traces.first { $0.runId == selectedRunId } ?? traces.first
  }

  private func reload() {
    traces = traceStore.recentTraces()
    if selectedRunId == nil {
      selectedRunId = traces.first?.runId
    }
  }
}
