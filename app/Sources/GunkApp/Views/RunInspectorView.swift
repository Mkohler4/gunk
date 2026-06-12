import SwiftUI

// MARK: - Inspector context

/// Where the run inspector was summoned from (T-8.6): run traces stopped
/// being a top-level destination, so every entry point states what the
/// inspector should land on.
enum RunInspectorContext: Identifiable, Equatable {
  /// Plain "show me the runs" — most recent run selected.
  case all
  /// From a source row or module detail: most recent run for that source.
  case source(Int64)
  /// From the run-failed status element: most recent failed run, so the
  /// failure is diagnosable in one click.
  case mostRecentFailure

  var id: String {
    switch self {
    case .all:
      return "all"
    case .source(let sourceId):
      return "source-\(sourceId)"
    case .mostRecentFailure:
      return "failure"
    }
  }

  /// The run a freshly opened inspector selects. Traces arrive newest-first
  /// from `RunTraceStore`; every context falls back to the most recent run
  /// rather than opening on nothing.
  func initialRunId(in traces: [RunTrace]) -> String? {
    switch self {
    case .all:
      return traces.first?.runId
    case .source(let sourceId):
      return (traces.first { $0.sourceId == sourceId } ?? traces.first)?.runId
    case .mostRecentFailure:
      return (traces.first { $0.status == "failed" } ?? traces.first)?.runId
    }
  }
}

// MARK: - Human formatting

/// Trace numbers formatted for humans (T-8.6): durations as seconds, not
/// milliseconds; timestamps carry the date only when the run wasn't today.
enum RunTraceFormat {
  static func duration(ms: Double) -> String {
    String(format: "%.1fs", ms / 1000)
  }

  /// Whether a timestamp needs its date spelled out — only when the run
  /// didn't happen today.
  static func includesDate(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
    !calendar.isDate(date, inSameDayAs: now)
  }

  static func timestamp(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
    if includesDate(date, now: now, calendar: calendar) {
      return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
    return date.formatted(.dateTime.hour().minute())
  }
}

// MARK: - Inspector

/// The extraction-run inspector (T-8.6, refactored from the old Runs tab):
/// the per-run traces the engine writes to `~/.gunk/runs` — every run, its
/// stages with timings/counts, and the accept/approve/reject summary —
/// presented as a sheet from the places users actually are (sources panel,
/// module detail, the run-failed status element) instead of a top-level
/// destination. Content sits on solid surfaces; only the sheet container is
/// system chrome.
@MainActor
struct RunInspectorView: View {
  private let traceStore: RunTraceStore
  private let context: RunInspectorContext
  private let processingModel: ProcessingModel?
  private let onClose: () -> Void

  @State private var traces: [RunTrace] = []
  @State private var selectedRunId: String?

  /// While a run is active and the inspector is open, traces refresh on
  /// this cadence (the brief's 2–3s) — the old tab never refreshed mid-run.
  private static let autoRefreshInterval: Duration = .milliseconds(2500)

  init(
    context: RunInspectorContext = .all,
    traceStore: RunTraceStore = RunTraceStore(),
    processingModel: ProcessingModel? = nil,
    onClose: @escaping () -> Void = {}
  ) {
    self.context = context
    self.traceStore = traceStore
    self.processingModel = processingModel
    self.onClose = onClose
  }

  var body: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
      header

      if traces.isEmpty {
        EmptyStateView(
          "No runs yet",
          message: "Drop a folder to start a run; its trace lands here."
        )
      } else {
        HStack(alignment: .top, spacing: BrandMetrics.Spacing.md) {
          runList
            .frame(width: Self.listWidth)

          detail
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
    }
    .padding(BrandMetrics.Spacing.lg)
    .frame(minWidth: 640, idealWidth: 760, minHeight: 440, idealHeight: 560)
    .background(BrandColors.backgroundPrimary)
    .onAppear(perform: initialLoad)
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: Self.autoRefreshInterval)
        if processingModel?.isProcessing == true {
          reload()
        }
      }
    }
  }

  private static let listWidth: CGFloat = 220

  // MARK: Header

  private var header: some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      Text("Runs (\(traces.count))")
        .font(BrandTypography.headline)
        .foregroundStyle(BrandColors.textPrimary)

      if processingModel?.isProcessing == true {
        Text("Run in progress — refreshing")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textSecondary)
      }

      Spacer(minLength: BrandMetrics.Spacing.sm)

      Button {
        reload()
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.brandIcon)
      .help("Refresh runs")

      Button("Done", action: onClose)
        .buttonStyle(.brandSecondary)
    }
  }

  // MARK: Run list

  private var runList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
          ForEach(traces) { trace in
            runRow(trace)
              .id(trace.runId)
          }
        }
      }
      .onAppear {
        // The context may select a run far down the list (an older failure,
        // a specific source); land with it in view.
        if let selectedRunId {
          proxy.scrollTo(selectedRunId, anchor: .center)
        }
      }
    }
  }

  private func runRow(_ trace: RunTrace) -> some View {
    let isSelected = trace.runId == selectedRunId

    return Button {
      selectedRunId = trace.runId
    } label: {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        Text(trace.sourceName)
          .font(BrandTypography.body.weight(.medium))
          .foregroundStyle(BrandColors.textPrimary)
          .lineLimit(1)

        HStack(spacing: BrandMetrics.Spacing.xs) {
          statusBadge(trace.status)
          Text(RunTraceFormat.timestamp(trace.startedAt))
            .font(BrandTypography.caption)
            .monospacedDigit()
            .foregroundStyle(BrandColors.textSecondary)
        }
      }
      .padding(BrandMetrics.Spacing.sm)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
          .fill(
            isSelected
              ? BrandColors.accent.opacity(BrandMetrics.Control.tintedFillOpacity)
              : BrandColors.backgroundSecondary
          )
      )
      .overlay {
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
          .strokeBorder(BrandColors.accent.opacity(isSelected ? 1 : 0))
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(trace.sourceName), \(trace.status), \(RunTraceFormat.timestamp(trace.startedAt))")
  }

  // MARK: Detail

  @ViewBuilder
  private var detail: some View {
    if let trace = selectedTrace {
      ScrollView {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
          VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
            Text(trace.sourceName)
              .font(BrandTypography.headline)
              .foregroundStyle(BrandColors.textPrimary)

            Text("\(trace.provider) · \(trace.model)")
              .font(BrandTypography.caption)
              .foregroundStyle(BrandColors.textSecondary)

            HStack(spacing: BrandMetrics.Spacing.sm) {
              statusBadge(trace.status)

              if let durationMs = trace.durationMs {
                Text(RunTraceFormat.duration(ms: durationMs))
                  .font(BrandTypography.caption)
                  .monospacedDigit()
                  .foregroundStyle(BrandColors.textSecondary)
              }

              Text("Started \(RunTraceFormat.timestamp(trace.startedAt))")
                .font(BrandTypography.caption)
                .monospacedDigit()
                .foregroundStyle(BrandColors.textSecondary)
            }
          }

          // The diagnosable moment: a failed run's error text, right under
          // the header, selectable for pasting into an issue or a prompt.
          if let error = trace.error {
            Text(error)
              .font(BrandTypography.caption)
              .foregroundStyle(BrandColors.danger)
              .textSelection(.enabled)
          }

          summaryRow(trace.summary)

          Divider()

          Text("Stages")
            .font(BrandTypography.body.weight(.semibold))
            .foregroundStyle(BrandColors.textPrimary)

          ForEach(trace.stages) { stage in
            stageRow(stage)
          }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.bottom, BrandMetrics.Spacing.sm)
      }
    } else {
      Text("Select a run to inspect its stages.")
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func summaryRow(_ summary: RunTrace.Summary) -> some View {
    HStack(spacing: BrandMetrics.Spacing.lg) {
      countPill("Accepted", summary.accepted, color: BrandColors.success)
      countPill("Needs approval", summary.needsApproval, color: BrandColors.warning)
      countPill("Rejected", summary.rejected, color: BrandColors.danger)
    }
  }

  private func stageRow(_ stage: RunTrace.Stage) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      HStack {
        Text(stage.stage)
          .font(BrandTypography.mono)
          .foregroundStyle(BrandColors.textPrimary)

        Spacer(minLength: BrandMetrics.Spacing.sm)

        Text(RunTraceFormat.duration(ms: stage.durationMs))
          .font(BrandTypography.caption)
          .monospacedDigit()
          .foregroundStyle(BrandColors.textSecondary)
      }

      if !stage.counts.isEmpty {
        Text(
          stage.counts
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "  ")
        )
        .font(BrandTypography.mono)
        .foregroundStyle(BrandColors.textSecondary)
      }

      if let error = stage.error {
        Text(error)
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.danger)
          .textSelection(.enabled)
      }
    }
    .padding(BrandMetrics.Spacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.medium, style: .continuous)
        .fill(
          stage.status == "error"
            ? BrandColors.danger.opacity(BrandMetrics.Control.tintedFillOpacity)
            : BrandColors.backgroundSecondary
        )
    )
  }

  private func countPill(_ label: String, _ value: Int, color: Color) -> some View {
    VStack(spacing: BrandMetrics.Spacing.xs) {
      Text("\(value)")
        .font(BrandTypography.headline)
        .monospacedDigit()
        .foregroundStyle(color)
      Text(label)
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textSecondary)
    }
  }

  private func statusBadge(_ status: String) -> some View {
    let variant: StatusBadge.Variant
    let label: String
    switch status {
    case "succeeded":
      variant = .success
      label = "Succeeded"
    case "failed":
      variant = .danger
      label = "Failed"
    default:
      variant = .warning
      label = status.capitalized
    }

    return StatusBadge(label, variant: variant)
  }

  private var selectedTrace: RunTrace? {
    guard let selectedRunId else {
      return traces.first
    }
    return traces.first { $0.runId == selectedRunId } ?? traces.first
  }

  private func initialLoad() {
    traces = traceStore.recentTraces()
    selectedRunId = context.initialRunId(in: traces)
  }

  /// Refresh keeps the user's selection if its run still exists; a vanished
  /// selection falls back to the context rule rather than going blank.
  private func reload() {
    traces = traceStore.recentTraces()
    if let selectedRunId, traces.contains(where: { $0.runId == selectedRunId }) {
      return
    }
    selectedRunId = context.initialRunId(in: traces)
  }
}
