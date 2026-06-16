import SwiftUI

/// Drives the smoke-run console (T-10.7): the developer's "Try it" door on the
/// module page. Owns the per-page run state — never-tried, first-run consent,
/// running/streaming, and the resting receipt — over the `BrowseModel`
/// orchestration (which builds the runner input, executes the sandboxed run,
/// and persists the receipt). UI state only; the durable proof lives in the
/// store (T-10.3).
@MainActor
@Observable
final class RunConsoleModel {
  /// The console's transient phase. The *resting* states (never-tried vs. last
  /// receipt) are distinguished by `receipt` while `phase == .idle`.
  enum Phase: Equatable {
    case idle
    case awaitingConsent
    case running
  }

  private let model: BrowseModel
  let detail: BrowseModuleDetail

  private(set) var phase: Phase = .idle
  /// The most recent receipt — loaded from the store on appear, replaced by a
  /// just-finished run. Drives the resting receipt line + demoted disclosure.
  private(set) var receipt: SmokeRunRecord?
  /// Incremental stdout/stderr for the live terminal; retained after a run so
  /// the demoted disclosure can show the raw log of the run just completed.
  private(set) var liveLog: String = ""
  /// When the active run started, for the elapsed indicator.
  private(set) var runStartedAt: Date?

  /// Dev-only screenshot override (see `applyDebugOverride`): forces the
  /// classification so the neutral "not runnable here" state can be staged.
  private var runnabilityOverride: Runnability?

  private var runTask: Task<Void, Never>?

  init(model: BrowseModel, detail: BrowseModuleDetail) {
    self.model = model
    self.detail = detail
    self.receipt = model.lastSmokeRun(for: detail.item.gunk.id)
    applyDebugOverride()
  }

  // MARK: Derived state

  var runnability: Runnability {
    runnabilityOverride ?? model.runnability(for: detail)
  }

  var isRunnableHere: Bool {
    runnability == .terminalRunnable
  }

  var isRunning: Bool {
    phase == .running
  }

  var awaitingConsent: Bool {
    phase == .awaitingConsent
  }

  /// The command the run will (or did) execute, for the consent treatment.
  var command: String? {
    model.resolvedRunCommand(for: detail)
  }

  /// The working directory promise: a *throwaway copy* of the bundle, never the
  /// developer's source (ADR-0016). We show the bundle's name, not its path.
  var bundleName: String? {
    detail.bundlePath.map { URL(fileURLWithPath: $0).lastPathComponent }
  }

  // MARK: Intents

  /// The single "Try it" entry point. Asks for first-run consent once per
  /// module (inferred from any prior receipt), then runs.
  func tryIt() {
    guard isRunnableHere, !isRunning else {
      return
    }

    if model.hasRunBefore(gunkId: detail.item.gunk.id) {
      run()
    } else {
      phase = .awaitingConsent
    }
  }

  func confirmConsent() {
    guard phase == .awaitingConsent else {
      return
    }
    run()
  }

  func cancelConsent() {
    phase = .idle
  }

  private func run() {
    guard !isRunning else {
      return
    }

    liveLog = ""
    runStartedAt = Date()
    phase = .running

    runTask = Task { [weak self] in
      guard let self else {
        return
      }

      let record = await self.model.runSmokeTest(for: self.detail) { [weak self] event in
        guard let self else {
          return
        }
        switch event {
        case .started:
          break
        case .stdout(let text):
          self.liveLog += text
        case .stderr(let text):
          self.liveLog += text
        case .finished:
          break
        }
      }

      if let record {
        self.receipt = record
      }
      self.runStartedAt = nil
      self.phase = .idle
    }
  }

  // MARK: Debug staging (screenshots)

  /// Dev-only screenshot hook (same family as `GUNK_DEBUG_MODULE_PAGE`): stages
  /// a console state at launch so every CP-F state can be captured without live
  /// execution. Pair with `GUNK_DEBUG_MODULE_PAGE=first|<id>` to open the page.
  /// Values: `nevertried`, `consent`, `running`, `passed`, `failed`,
  /// `unrunnable`.
  private func applyDebugOverride() {
    guard let value = ProcessInfo.processInfo.environment["GUNK_DEBUG_RUN_CONSOLE"] else {
      return
    }

    let gunkId = detail.item.gunk.id
    let command = command ?? "python3 parser.py --in sample.epub"

    switch value {
    case "nevertried":
      runnabilityOverride = .terminalRunnable
      receipt = nil
    case "consent":
      runnabilityOverride = .terminalRunnable
      phase = .awaitingConsent
    case "running":
      runnabilityOverride = .terminalRunnable
      phase = .running
      runStartedAt = Date()
      liveLog = "$ \(command)\nParsing EPUB…\nparsed 12 chapters\n"
    case "passed":
      runnabilityOverride = .terminalRunnable
      liveLog = "parsed 12 chapters\nwrote chapters.json\n"
      receipt = Self.stagedReceipt(
        gunkId: gunkId, command: command, runnability: .terminalRunnable,
        exitCode: 0, passed: true, log: liveLog, durationMs: 1800
      )
    case "failed":
      runnabilityOverride = .terminalRunnable
      liveLog = "Traceback (most recent call last):\n  File \"parser.py\", line 42\nValueError: corrupt header\n"
      receipt = Self.stagedReceipt(
        gunkId: gunkId, command: command, runnability: .terminalRunnable,
        exitCode: 3, passed: false, log: liveLog, durationMs: 300
      )
    case "unrunnable":
      runnabilityOverride = .needsNetwork
    default:
      break
    }
  }

  private static func stagedReceipt(
    gunkId: Int64,
    command: String,
    runnability: Runnability,
    exitCode: Int32?,
    passed: Bool?,
    log: String,
    durationMs: Int
  ) -> SmokeRunRecord {
    SmokeRunRecord(
      id: -1,
      gunkId: gunkId,
      exampleId: nil,
      command: command,
      runnability: runnability,
      origin: .human,
      exitCode: exitCode,
      passed: passed,
      timedOut: false,
      durationMs: durationMs,
      outputArtifactPath: nil,
      log: log,
      verdict: nil,
      createdAt: 1_700_000_000
    )
  }
}

/// The smoke-run console section on the module page (T-10.7). It renders the
/// CP-F run states — never-tried, first-run consent, running/streaming, passed
/// (earned green), failed (red), and the resting receipt with the terminal +
/// raw command **demoted** to a collapsed disclosure — plus the neutral
/// "runnable here: not yet" treatment for modules the sandbox can't fairly run.
/// This is the *smoke run* only; it never merges with the `view run →`
/// extraction inspector (the two-surfaces rule).
struct RunConsoleView: View {
  @State var console: RunConsoleModel
  /// Expansion of the `>_ Command & raw log` disclosure. Collapsed by default
  /// per the receipt-first rule.
  @State private var showRawLog = false

  init(model: BrowseModel, detail: BrowseModuleDetail) {
    _console = State(initialValue: RunConsoleModel(model: model, detail: detail))
  }

  var body: some View {
    DetailSection(title: "Try it", systemImage: "play.circle") {
      if !console.isRunning, !console.isRunnableHere {
        notRunnableHere(console.runnability)
      } else {
        VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
          consoleHeader

          if console.awaitingConsent {
            consentTreatment
          } else if console.isRunning {
            liveTerminal
          } else if let receipt = console.receipt {
            restingReceipt(receipt)
          } else {
            neverTried
          }
        }
      }
    }
  }

  // MARK: Header

  private var consoleHeader: some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      Text(">_ run console")
        .font(BrandTypography.mono)
        .foregroundStyle(BrandColors.textTertiary)

      if let command = console.command {
        Text(command)
          .font(BrandTypography.mono)
          .foregroundStyle(BrandColors.textSecondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer(minLength: BrandMetrics.Spacing.sm)

      statusChip
    }
  }

  @ViewBuilder
  private var statusChip: some View {
    if console.isRunning {
      HStack(spacing: BrandMetrics.Spacing.xs) {
        ProgressView()
          .controlSize(.small)
        Text("Running")
          .font(BrandTypography.callout)
          .foregroundStyle(BrandColors.textSecondary)
      }
    } else if console.awaitingConsent {
      StatusBadge("Ready", variant: .neutral, systemImage: "hand.raised")
    } else if let receipt = console.receipt {
      switch outcome(of: receipt) {
      case .passed:
        StatusBadge("Passed", variant: .success, systemImage: "checkmark.circle")
      case .failed:
        StatusBadge("Failed", variant: .danger, systemImage: "xmark.circle")
      case .couldNotRun, .notRunnable:
        StatusBadge("Not run", variant: .neutral, systemImage: "minus.circle")
      }
    } else {
      StatusBadge("Idle", variant: .neutral, systemImage: "circle.dashed")
    }
  }

  // MARK: Never tried

  private var neverTried: some View {
    HStack(spacing: BrandMetrics.Spacing.md) {
      Text("Never tried. Run the entrypoint once in a sandbox to see what it does.")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 0)

      Button(action: console.tryIt) {
        Label("Try it", systemImage: "play.fill")
      }
      .buttonStyle(.brandPrimary)
      .help("Run the module's entrypoint in a sandbox")
    }
  }

  // MARK: First-run consent

  private var consentTreatment: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      Text("First run — here's exactly what will happen")
        .font(BrandTypography.callout.weight(.semibold))
        .foregroundStyle(BrandColors.textPrimary)

      if let command = console.command {
        terminalBlock {
          Text("$ \(command)")
            .font(BrandTypography.mono)
            .foregroundStyle(BrandColors.textPrimary)
            .textSelection(.enabled)
        }
      }

      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
        consentRow("Working directory", "a throwaway copy of \(console.bundleName ?? "the bundle") — your source is never run in place")
        consentRow("Network", "off — the run cannot reach the internet")
        consentRow("Writes", "confined to the run directory")
        consentRow("Timeout", "the run is hard-stopped after 30s")
        consentRow("Secrets", "your environment is never passed in")
      }

      HStack(spacing: BrandMetrics.Spacing.sm) {
        Button(action: console.confirmConsent) {
          Label("Run", systemImage: "play.fill")
        }
        .buttonStyle(.brandPrimary)
        .help("Run the entrypoint in the sandbox")

        Button(action: console.cancelConsent) {
          Text("Cancel")
        }
        .buttonStyle(.brandSecondary)
      }
      .padding(.top, BrandMetrics.Spacing.xs)
    }
  }

  private func consentRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.sm) {
      Text(label)
        .font(BrandTypography.caption.weight(.semibold))
        .foregroundStyle(BrandColors.textTertiary)
        .frame(width: 120, alignment: .leading)

      Text(value)
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: Running / streaming

  private var liveTerminal: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      terminalBlock {
        ScrollViewReader { proxy in
          ScrollView {
            Text(console.liveLog.isEmpty ? "…" : console.liveLog)
              .font(BrandTypography.mono)
              .foregroundStyle(BrandColors.textPrimary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .textSelection(.enabled)
              .id(Self.terminalTailID)
          }
          .frame(height: Self.terminalHeight)
          .onChange(of: console.liveLog) { _, _ in
            withAnimation(BrandMotion.quick) {
              proxy.scrollTo(Self.terminalTailID, anchor: .bottom)
            }
          }
        }
      }

      TimelineView(.periodic(from: .now, by: 0.1)) { context in
        let elapsed = console.runStartedAt.map { context.date.timeIntervalSince($0) } ?? 0
        HStack(spacing: BrandMetrics.Spacing.xs) {
          ProgressView()
            .controlSize(.small)
          Text("Running… \(elapsed.formatted(.number.precision(.fractionLength(1))))s")
            .font(BrandTypography.caption)
            .foregroundStyle(BrandColors.textSecondary)
        }
      }
    }
  }

  // MARK: Resting receipt

  @ViewBuilder
  private func restingReceipt(_ receipt: SmokeRunRecord) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      HStack(spacing: BrandMetrics.Spacing.md) {
        Text(receiptLine(receipt))
          .font(BrandTypography.callout.weight(.semibold))
          .foregroundStyle(receiptColor(receipt))

        Spacer(minLength: 0)

        Button(action: console.tryIt) {
          Label("Run again", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.brandSecondary)
        .help("Run the entrypoint again in a sandbox")
      }

      rawLogDisclosure(receipt)
    }
  }

  /// The demoted disclosure (`>_ Command & raw log`), collapsed by default per
  /// the receipt-first rule. Holds the raw command and the captured terminal
  /// output — evidence, not the headline.
  private func rawLogDisclosure(_ receipt: SmokeRunRecord) -> some View {
    DisclosureGroup(isExpanded: $showRawLog) {
      VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
        if let command = receipt.command {
          Text("$ \(command)")
            .font(BrandTypography.mono)
            .foregroundStyle(BrandColors.textSecondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        let log = console.liveLog.isEmpty ? receipt.log : console.liveLog
        terminalBlock {
          ScrollView {
            Text(log.isEmpty ? "(no output)" : log)
              .font(BrandTypography.mono)
              .foregroundStyle(BrandColors.textPrimary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .textSelection(.enabled)
          }
          .frame(height: Self.terminalHeight)
        }
      }
      .padding(.top, BrandMetrics.Spacing.xs)
    } label: {
      Text(">_ Command & raw log")
        .font(BrandTypography.mono)
        .foregroundStyle(BrandColors.textTertiary)
    }
    .tint(BrandColors.textTertiary)
  }

  // MARK: Not runnable here (neutral, never red)

  private func notRunnableHere(_ runnability: Runnability) -> some View {
    let copy = Self.notRunnableCopy(runnability)
    return VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      StatusBadge(copy.title, variant: .neutral, systemImage: copy.systemImage)

      Text(copy.detail)
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)

      Text("The sandbox is the wrong room for this proof — use Call it above to run it where it belongs.")
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: Shared terminal chrome

  private func terminalBlock<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .padding(BrandMetrics.Spacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.small, style: .continuous)
          .fill(BrandColors.backgroundPrimary)
      )
      .overlay(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.small, style: .continuous)
          .strokeBorder(BrandColors.separator)
      )
  }

  // MARK: Derivations

  /// The honest outcome of a persisted receipt. A run that was classified
  /// runnable but never actually executed (staging/sandbox refusal —
  /// `exitCode == nil`, not timed out) is **not** a red failure; it reads as a
  /// neutral "couldn't run here".
  private enum Outcome {
    case passed
    case failed
    case couldNotRun
    case notRunnable(Runnability)
  }

  private func outcome(of receipt: SmokeRunRecord) -> Outcome {
    guard receipt.runnability == .terminalRunnable else {
      return .notRunnable(receipt.runnability)
    }
    if receipt.passed == true {
      return .passed
    }
    if receipt.timedOut || receipt.exitCode != nil {
      return .failed
    }
    return .couldNotRun
  }

  private func receiptLine(_ receipt: SmokeRunRecord) -> String {
    switch outcome(of: receipt) {
    case .passed:
      return "Last tried: passed · \(durationLabel(receipt.durationMs))"
    case .failed:
      if receipt.timedOut {
        return "Last tried: timed out · \(durationLabel(receipt.durationMs))"
      }
      return "Last tried: failed · \(durationLabel(receipt.durationMs))"
    case .couldNotRun:
      return "Last tried: couldn't run here"
    case .notRunnable(let runnability):
      return Self.notRunnableCopy(runnability).title
    }
  }

  private func receiptColor(_ receipt: SmokeRunRecord) -> Color {
    switch outcome(of: receipt) {
    case .passed:
      return BrandColors.accent
    case .failed:
      return BrandColors.danger
    case .couldNotRun, .notRunnable:
      return BrandColors.textSecondary
    }
  }

  private func durationLabel(_ ms: Int) -> String {
    let seconds = Double(ms) / 1000
    return "\(seconds.formatted(.number.precision(.fractionLength(1))))s"
  }

  private static func notRunnableCopy(_ runnability: Runnability) -> (title: String, detail: String, systemImage: String) {
    switch runnability {
    case .needsNetwork:
      return (
        "Runnable here: not yet — needs the network",
        "This module's job is to call out to a live service, and the sandbox runs offline.",
        "network.slash"
      )
    case .needsSecrets:
      return (
        "Runnable here: not yet — needs secrets",
        "This module needs credentials that aren't present in the sandbox.",
        "key"
      )
    case .interactiveStdin:
      return (
        "Runnable here: not yet — wants interactive input",
        "This is a prompt-driven CLI; the one-shot runner can't answer its prompts.",
        "keyboard"
      )
    case .longRunning:
      return (
        "Runnable here: not yet — long-running",
        "This looks like a server, watcher, or TUI that doesn't terminate, so the timeout isn't a fair test.",
        "infinity"
      )
    case .uiModule:
      return (
        "Runnable here: not yet — UI module",
        "Output is a UI surface. In-browser launch is coming in a later phase.",
        "macwindow"
      )
    case .cannotDetermine:
      return (
        "Runnable here: not yet — can't tell how to run this",
        "gunk couldn't confidently derive a command to run, so it won't guess.",
        "questionmark.circle"
      )
    case .terminalRunnable:
      return (
        "Runnable",
        "This module runs as a one-shot terminal entrypoint.",
        "terminal"
      )
    }
  }

  private static let terminalHeight: CGFloat = 200
  private static let terminalTailID = "run-console-terminal-tail"
}
