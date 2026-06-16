import AppKit
import SwiftUI

/// The console's own near-black world — deeper than the page graphite, a
/// distinct "terminal" surface (the module-run-v2 `--con*` palette). These are
/// art values local to the console (like the provider badge colors), not
/// semantic page tokens, so they live here rather than in `BrandColors`.
enum ConsolePalette {
  /// `--con`: the console surface, deeper than the page.
  static let surface = Color(hex: 0x0C0C0E)
  /// `--con-hi`: a half-step lift for inset blocks inside the console.
  static let surfaceHigh = Color(hex: 0x131316)
  /// `--con-line`: hairlines inside the console world.
  static let line = Color.white.opacity(0.06)
  /// `--sky`: the running/streaming accent (never green — running is not earned).
  static let sky = Color(hex: 0x7FB6E8)
  /// `--violet`: the "yours" provenance tag on developer-brought inputs.
  static let violet = Color(hex: 0xB79BE0)
}

/// The intents the console toolbar offers — the "verbs" that frame a run
/// (module-run-v2). Each maps to a coverage class so a judged run lands in the
/// right ledger axis.
enum RunIntent: String, CaseIterable, Identifiable {
  case example
  case mine
  case breakIt

  var id: String { rawValue }

  var label: String {
    switch self {
    case .example: return "Shipped example"
    case .mine: return "My own input"
    case .breakIt: return "Try to break it"
    }
  }

  var systemImage: String {
    switch self {
    case .example: return "bolt.fill"
    case .mine: return "person"
    case .breakIt: return "shield"
    }
  }

  /// The accent the selected tab + run button take. Example earns green (the
  /// shipped happy path), break warns amber (adversarial), mine is neutral.
  var accent: Color {
    switch self {
    case .example: return BrandColors.accent
    case .mine: return BrandColors.textPrimary
    case .breakIt: return BrandColors.warning
    }
  }

  var coverageClass: ExampleInputClass {
    switch self {
    case .example: return .happy
    case .mine: return .yours
    case .breakIt: return .adversarial
    }
  }
}

/// The module-run-v2 **run console** — the page hero. A deep, self-contained
/// terminal world: a status bar, the intent toolbar (the verbs that frame a
/// run), the command line + streamed output + a before/after proof inside the
/// body, and a single action zone in the footer that cycles Run → verdict.
///
/// The actual sandboxed execution + receipt persistence is the (already built)
/// `RunConsoleModel` engine; this view is the v2 presentation over it. The
/// proof diff, the developer verdict, and the correction loop are the visual
/// **outline** here — the artifact rendering (T-10.9) and the capture-and-queue
/// wiring land on this shell later in the phase.
struct RunConsoleStageView: View {
  @State var console: RunConsoleModel
  let model: BrowseModel

  @State private var intent: RunIntent = .example
  /// A run finished and its result + verdict are showing (until the developer
  /// judges it or switches intent). Driven off `console.runsCompleted`.
  @State private var showingResult = false
  @State private var lastRunCount = 0
  /// The "Not quite" correction panel is open.
  @State private var correcting = false
  @State private var expectedText = ""
  @State private var noteText = ""
  /// The fail-path "known limit" was recorded for this run.
  @State private var recordedLimit = false
  /// A brief inline confirmation after a verdict/save.
  @State private var confirmation: String?

  init(model: BrowseModel, detail: BrowseModuleDetail) {
    _console = State(initialValue: RunConsoleModel(model: model, detail: detail))
    self.model = model
  }

  // MARK: Result state

  private enum ResultKind { case pass, fail }

  /// The console's display phase, folding the engine phase with local result UI.
  private var resultKind: ResultKind? {
    guard showingResult, !console.isRunning, !console.awaitingConsent else {
      return nil
    }
    if let receipt = console.receipt, receipt.passed == false {
      return .fail
    }
    return .pass
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      statusBar
      Divider().overlay(ConsolePalette.line)
      intentToolbar
      Divider().overlay(ConsolePalette.line)
      body(for: console.runnability)
    }
    .background(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous)
        .fill(ConsolePalette.surface)
    )
    .overlay(
      RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous)
        .strokeBorder(Color.white.opacity(0.08))
    )
    .clipShape(RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous))
    .onChange(of: console.runsCompleted) { _, newValue in
      guard newValue != lastRunCount else { return }
      lastRunCount = newValue
      withAnimation(BrandMotion.settle) {
        showingResult = true
        correcting = false
        recordedLimit = false
      }
    }
  }

  // MARK: Status bar

  private var statusBar: some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      Image(systemName: "terminal")
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.textTertiary)
      Text("run console")
        .font(BrandTypography.callout.weight(.semibold))
        .foregroundStyle(BrandColors.textPrimary)
      Circle()
        .fill(BrandColors.textTertiary)
        .frame(width: 4, height: 4)
      Text(entryLabel)
        .font(BrandTypography.mono)
        .foregroundStyle(BrandColors.textTertiary)
        .lineLimit(1)
        .truncationMode(.middle)

      Spacer(minLength: BrandMetrics.Spacing.sm)

      statusChip
    }
    .padding(.horizontal, BrandMetrics.Spacing.md)
    .padding(.vertical, BrandMetrics.Spacing.md)
  }

  @ViewBuilder
  private var statusChip: some View {
    if console.isRunning {
      consoleChip(ConsolePalette.sky) {
        ProgressView().controlSize(.small).tint(ConsolePalette.sky)
        Text("Running")
      }
    } else if let kind = resultKind {
      switch kind {
      case .pass:
        consoleChip(BrandColors.accent) {
          Image(systemName: "checkmark"); Text("exit 0")
        }
      case .fail:
        consoleChip(BrandColors.danger) {
          Image(systemName: "xmark"); Text("exit 1")
        }
      }
    } else {
      consoleChip(BrandColors.textTertiary) {
        Image(systemName: "terminal"); Text("Idle")
      }
    }
  }

  private func consoleChip<Content: View>(_ color: Color, @ViewBuilder _ content: () -> Content) -> some View {
    HStack(spacing: BrandMetrics.Spacing.xs) {
      content()
    }
    .font(BrandTypography.caption.weight(.semibold))
    .foregroundStyle(color)
    .padding(.horizontal, BrandMetrics.Spacing.sm)
    .padding(.vertical, BrandMetrics.Spacing.xs)
    .background(Capsule().fill(color.opacity(0.16)))
  }

  // MARK: Intent toolbar

  private var intentToolbar: some View {
    HStack(spacing: BrandMetrics.Spacing.xs) {
      ForEach(RunIntent.allCases) { option in
        intentTab(option)
      }

      Spacer(minLength: 0)

      if intent == .mine {
        Button(action: chooseOwnInput) {
          HStack(spacing: BrandMetrics.Spacing.xs) {
            Image(systemName: "doc")
            Text("Choose file…")
          }
          .font(BrandTypography.callout.weight(.semibold))
          .foregroundStyle(BrandColors.textTertiary)
          .padding(.horizontal, BrandMetrics.Spacing.sm)
          .padding(.vertical, BrandMetrics.Spacing.xs)
        }
        .buttonStyle(.plain)
        .help("Pick a file to run the module on your own input")
      }
    }
    .padding(.horizontal, BrandMetrics.Spacing.sm)
    .padding(.vertical, BrandMetrics.Spacing.sm)
  }

  private func intentTab(_ option: RunIntent) -> some View {
    let on = intent == option
    return Button {
      withAnimation(BrandMotion.quick) {
        intent = option
        showingResult = false
        correcting = false
        recordedLimit = false
        confirmation = nil
      }
    } label: {
      HStack(spacing: BrandMetrics.Spacing.xs) {
        Image(systemName: option.systemImage)
        Text(option.label)
      }
      .font(BrandTypography.callout.weight(.semibold))
      .foregroundStyle(on ? option.accent : BrandColors.textTertiary)
      .padding(.horizontal, BrandMetrics.Spacing.sm)
      .padding(.vertical, BrandMetrics.Spacing.xs)
      .background(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.small, style: .continuous)
          .fill(Color.white.opacity(on ? 0.07 : 0))
      )
    }
    .buttonStyle(.plain)
  }

  // MARK: Body

  @ViewBuilder
  private func body(for runnability: Runnability) -> some View {
    if !console.isRunnableHere {
      notRunnableHere(runnability)
        .padding(BrandMetrics.Spacing.lg)
    } else {
      VStack(alignment: .leading, spacing: 0) {
        consoleBody
          .padding(BrandMetrics.Spacing.lg)
        Divider().overlay(ConsolePalette.line)
        consoleFooter
          .padding(BrandMetrics.Spacing.md)
          .background(Color.white.opacity(0.015))
      }
    }
  }

  @ViewBuilder
  private var consoleBody: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.md) {
      commandLine
      if console.awaitingConsent {
        consentRows
      } else if console.isRunning {
        streamingOutput
      } else if let kind = resultKind {
        switch kind {
        case .pass:
          passOutput
          proofDiff
          if correcting { correctionPanel }
        case .fail:
          failOutput
        }
      } else {
        idleHint
      }
    }
    .frame(minHeight: 240, alignment: .topLeading)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var commandLine: some View {
    HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.sm) {
      Text("$")
        .foregroundStyle(BrandColors.accent)
      Text(commandText)
        .foregroundStyle(BrandColors.textPrimary)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .font(BrandTypography.mono)
  }

  private var idleHint: some View {
    HStack(alignment: .top, spacing: BrandMetrics.Spacing.sm) {
      Image(systemName: "terminal")
        .foregroundStyle(BrandColors.textTertiary)
      Text(hintText)
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(.top, BrandMetrics.Spacing.md)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(ConsolePalette.line)
        .frame(height: 1)
    }
  }

  private var hintText: String {
    switch intent {
    case .example:
      return "Start here. Confirms the capability works at all before you trust it with your own files. Output streams here, then you judge it."
    case .mine:
      return "The honest test. Does it hold up on input the author never saw? Output streams here, then you judge it."
    case .breakIt:
      return "Characterize the edge. Find where it breaks so the limit is documented, not discovered later. Output streams here, then you judge it."
    }
  }

  // MARK: Output

  private var streamingOutput: some View {
    terminalBlock {
      ScrollViewReader { proxy in
        ScrollView {
          Text(console.liveLog.isEmpty ? "…" : console.liveLog)
            .font(BrandTypography.mono)
            .foregroundStyle(BrandColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .id(Self.tailID)
        }
        .frame(height: 150)
        .onChange(of: console.liveLog) { _, _ in
          withAnimation(BrandMotion.quick) { proxy.scrollTo(Self.tailID, anchor: .bottom) }
        }
      }
    }
  }

  private var passOutput: some View {
    let log = console.liveLog.isEmpty ? (console.receipt?.log ?? "") : console.liveLog
    return VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      if log.isEmpty {
        outputLine("→ ran clean · exit 0", color: BrandColors.accent)
      } else {
        Text(log)
          .font(BrandTypography.mono)
          .foregroundStyle(BrandColors.textSecondary)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private var failOutput: some View {
    let log = console.liveLog.isEmpty ? (console.receipt?.log ?? "") : console.liveLog
    return VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      if log.isEmpty {
        outputLine("✗ the entrypoint raised on this input", color: BrandColors.danger)
      } else {
        Text(log)
          .font(BrandTypography.mono)
          .foregroundStyle(BrandColors.danger)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func outputLine(_ text: String, color: Color) -> some View {
    Text(text)
      .font(BrandTypography.mono)
      .foregroundStyle(color)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The before/after **Proof card**, rendered inside the console as terminal
  /// text rather than boxes (module-run-v2). The faithful artifact rendering
  /// per output kind (markdown / JSON / audio) is T-10.9 — this is the outline.
  private var proofDiff: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      HStack(spacing: BrandMetrics.Spacing.xs) {
        Text("INPUT")
        Image(systemName: "arrow.right")
        Text("OUTPUT")
      }
      .font(BrandTypography.caption.weight(.semibold))
      .foregroundStyle(BrandColors.textTertiary)

      HStack(alignment: .top, spacing: 0) {
        diffColumn(
          label: "input",
          labelColor: BrandColors.textTertiary,
          icon: "doc",
          body: "<h2>I</h2>\n<p>It was a bright cold day in April, and the clocks were striking thirteen.</p>",
          bodyColor: BrandColors.textTertiary
        )
        .overlay(alignment: .trailing) {
          Rectangle().fill(ConsolePalette.line).frame(width: 1)
        }

        diffColumn(
          label: "chapter-01.md",
          labelColor: BrandColors.accent,
          icon: "checkmark",
          body: "# Chapter 1\n\nIt was a bright cold day in April, and the\nclocks were striking thirteen.",
          bodyColor: BrandColors.textSecondary
        )
      }
    }
    .padding(.top, BrandMetrics.Spacing.md)
    .overlay(alignment: .top) {
      Rectangle().fill(ConsolePalette.line).frame(height: 1)
    }
  }

  private func diffColumn(
    label: String,
    labelColor: Color,
    icon: String,
    body: String,
    bodyColor: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      HStack(spacing: BrandMetrics.Spacing.xs) {
        Image(systemName: icon)
        Text(label)
      }
      .font(BrandTypography.caption.weight(.semibold))
      .foregroundStyle(labelColor)

      Text(body)
        .font(BrandTypography.mono)
        .foregroundStyle(bodyColor)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, BrandMetrics.Spacing.md)
  }

  // MARK: Consent (first run)

  private var consentRows: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      Text("First run — here's exactly what will happen")
        .font(BrandTypography.callout.weight(.semibold))
        .foregroundStyle(BrandColors.textPrimary)
        .padding(.top, BrandMetrics.Spacing.sm)

      consentRow("Working directory", "a throwaway copy of \(console.bundleName ?? "the bundle") — your source is never run in place")
      consentRow("Network", "off — the run cannot reach the internet")
      consentRow("Writes", "confined to the run directory")
      consentRow("Timeout", "the run is hard-stopped after 30s")
      consentRow("Secrets", "your environment is never passed in")
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

  // MARK: Correction loop ("Not quite" → pin a failing check)

  private var correctionPanel: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      HStack(spacing: BrandMetrics.Spacing.xs) {
        Image(systemName: "pencil")
        Text("What did you expect instead?")
      }
      .font(BrandTypography.callout.weight(.semibold))
      .foregroundStyle(BrandColors.textPrimary)

      Text("This becomes a failing check — a regression the capability must satisfy before it can be trusted. Show the output you wanted, or just describe what was wrong.")
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textTertiary)
        .fixedSize(horizontal: false, vertical: true)

      TextEditor(text: $expectedText)
        .font(BrandTypography.mono)
        .scrollContentBackground(.hidden)
        .frame(height: 72)
        .padding(BrandMetrics.Spacing.sm)
        .background(
          RoundedRectangle(cornerRadius: BrandMetrics.Radius.small, style: .continuous)
            .fill(Color.black.opacity(0.4))
        )
        .overlay(
          RoundedRectangle(cornerRadius: BrandMetrics.Radius.small, style: .continuous)
            .strokeBorder(ConsolePalette.line)
        )

      TextField("One line: what's wrong? (e.g. 'drops footnotes')", text: $noteText)
        .textFieldStyle(.plain)
        .font(BrandTypography.callout)
        .padding(BrandMetrics.Spacing.sm)
        .background(
          RoundedRectangle(cornerRadius: BrandMetrics.Radius.small, style: .continuous)
            .fill(Color.black.opacity(0.4))
        )
        .overlay(
          RoundedRectangle(cornerRadius: BrandMetrics.Radius.small, style: .continuous)
            .strokeBorder(ConsolePalette.line)
        )

      HStack(spacing: BrandMetrics.Spacing.sm) {
        Button(action: pinFailing) {
          Text("Pin as failing check")
        }
        .buttonStyle(.brandPrimary)

        Button("Cancel") {
          withAnimation(BrandMotion.quick) { correcting = false }
        }
        .buttonStyle(.brandSecondary)
      }
    }
    .padding(.top, BrandMetrics.Spacing.md)
    .overlay(alignment: .top) {
      Rectangle().fill(ConsolePalette.line).frame(height: 1)
    }
  }

  // MARK: Footer (the single action zone)

  @ViewBuilder
  private var consoleFooter: some View {
    if console.awaitingConsent {
      footerRow(note: "Review the sandbox promise above, then run.") {
        HStack(spacing: BrandMetrics.Spacing.sm) {
          Button("Cancel", action: console.cancelConsent)
            .buttonStyle(.brandSecondary)
          runButton(title: "Run", action: console.confirmConsent)
        }
      }
    } else if console.isRunning {
      footerRow(note: "Executing in the module sandbox…") {
        HStack(spacing: BrandMetrics.Spacing.xs) {
          ProgressView().controlSize(.small)
          Text("Running").font(BrandTypography.callout).foregroundStyle(BrandColors.textSecondary)
        }
      }
    } else if let kind = resultKind, !correcting {
      verdictFooter(kind)
    } else if correcting {
      footerRow(note: "Describe the expected output above, then pin it as a failing check.") { EmptyView() }
    } else {
      footerRow(note: intent == .breakIt ? "Adversarial run. Hit run to execute the command above." : "Ready. Hit run to execute the command above.") {
        runButton(title: intent == .breakIt ? "Run adversarial" : "Run it", action: run)
      }
    }
  }

  @ViewBuilder
  private func verdictFooter(_ kind: ResultKind) -> some View {
    if let confirmation {
      footerRow(note: confirmation) { EmptyView() }
    } else {
      switch kind {
      case .pass:
        footerRow(
          note: "Is this output right? You ran it — now you judge it. This is the call only you can make.",
          emphasize: true
        ) {
          HStack(spacing: BrandMetrics.Spacing.sm) {
            Button(action: judgeRight) {
              HStack(spacing: BrandMetrics.Spacing.xs) { Image(systemName: "checkmark"); Text("Looks right") }
            }
            .buttonStyle(.brandPrimary)

            Button(action: { withAnimation(BrandMotion.quick) { correcting = true } }) {
              HStack(spacing: BrandMetrics.Spacing.xs) { Image(systemName: "xmark"); Text("Not quite") }
            }
            .buttonStyle(.brandSecondary)
          }
        }
      case .fail:
        footerRow(
          note: "It raised on this input. A defensible boundary — but it should be a documented limit, not a surprise in production.",
          emphasize: true
        ) {
          if recordedLimit {
            StatusBadge("Recorded", variant: .warning, systemImage: "checkmark")
          } else {
            Button(action: recordLimit) {
              HStack(spacing: BrandMetrics.Spacing.xs) { Image(systemName: "shield"); Text("Record as known limit") }
            }
            .buttonStyle(.brandPrimary)
          }
        }
      }
    }
  }

  private func footerRow<Trailing: View>(
    note: String,
    emphasize: Bool = false,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack(alignment: .center, spacing: BrandMetrics.Spacing.md) {
      Text(note)
        .font(emphasize ? BrandTypography.callout : BrandTypography.caption)
        .foregroundStyle(emphasize ? BrandColors.textSecondary : BrandColors.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      trailing()
    }
    .frame(minHeight: 36)
  }

  private func runButton(title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: BrandMetrics.Spacing.xs) {
        Image(systemName: "play.fill")
        Text(title)
      }
    }
    .buttonStyle(.brandPrimary)
    .disabled(console.hasBlockingValidation)
    .help("Run the module's entrypoint in the sandbox")
  }

  // MARK: Not runnable here (neutral — never red)

  private func notRunnableHere(_ runnability: Runnability) -> some View {
    let copy = Self.notRunnableCopy(runnability)
    return VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      StatusBadge(copy.title, variant: .neutral, systemImage: copy.systemImage)
      Text(copy.detail)
        .font(BrandTypography.callout)
        .foregroundStyle(BrandColors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      Text("The sandbox is the wrong room for this proof — use Call it (in Advanced) to run it where it belongs.")
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: Shared chrome

  private func terminalBlock<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .padding(BrandMetrics.Spacing.md)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.small, style: .continuous)
          .fill(Color.black.opacity(0.35))
      )
      .overlay(
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.small, style: .continuous)
          .strokeBorder(ConsolePalette.line)
      )
  }

  // MARK: Actions

  private func run() {
    confirmation = nil
    console.tryIt()
  }

  private func judgeRight() {
    console.saveAsExample(name: defaultExampleName)
    withAnimation(BrandMotion.quick) {
      confirmation = "Saved as a \(intent.coverageClass.label) check — re-runs on every change."
    }
  }

  private func pinFailing() {
    let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    model.saveExample(
      for: console.detail,
      name: defaultExampleName,
      input: console.command ?? entryLabel,
      inputClass: intent == .breakIt ? .adversarial : .edge,
      verdict: .wrong
    )
    withAnimation(BrandMotion.quick) {
      correcting = false
      confirmation = note.isEmpty
        ? "Pinned as a failing check — now blocking sign-off until it's fixed."
        : "Pinned: “\(note)” — now blocking sign-off until it's fixed."
    }
  }

  private func recordLimit() {
    model.saveExample(
      for: console.detail,
      name: "Known limit",
      input: console.command ?? entryLabel,
      inputClass: .adversarial
    )
    withAnimation(BrandMotion.quick) { recordedLimit = true }
  }

  private func chooseOwnInput() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url,
       let field = console.activeSignature.fields.first(where: { if case .file = $0.kind { return true } else { return false } }) {
      console.setFile(url, for: field)
    }
  }

  // MARK: Derivations

  private var entryLabel: String {
    console.detail.entrypoints.first?.label ?? "entrypoint"
  }

  private var commandText: String {
    console.command ?? "gunk run \(entryLabel)"
  }

  private var defaultExampleName: String {
    let base = (console.command.flatMap { URL(fileURLWithPath: $0).lastPathComponent }) ?? entryLabel
    return "\(intent.label) · \(base)"
  }

  private static func notRunnableCopy(_ runnability: Runnability) -> (title: String, detail: String, systemImage: String) {
    switch runnability {
    case .needsNetwork:
      return ("Runnable here: not yet — needs the network", "This module's job is to call out to a live service, and the sandbox runs offline.", "network.slash")
    case .needsSecrets:
      return ("Runnable here: not yet — needs secrets", "This module needs credentials that aren't present in the sandbox.", "key")
    case .interactiveStdin:
      return ("Runnable here: not yet — wants interactive input", "This is a prompt-driven CLI; the one-shot runner can't answer its prompts.", "keyboard")
    case .longRunning:
      return ("Runnable here: not yet — long-running", "This looks like a server, watcher, or TUI that doesn't terminate, so the timeout isn't a fair test.", "infinity")
    case .uiModule:
      return ("Runnable here: not yet — UI module", "Output is a UI surface. In-browser launch is coming in a later phase.", "macwindow")
    case .cannotDetermine:
      return ("Runnable here: not yet — can't tell how to run this", "gunk couldn't confidently derive a command to run, so it won't guess.", "questionmark.circle")
    case .terminalRunnable:
      return ("Runnable", "This module runs as a one-shot terminal entrypoint.", "terminal")
    }
  }

  private static let tailID = "run-console-stage-tail"
}

private extension ExampleInputClass {
  var label: String {
    switch self {
    case .happy: return "happy-path"
    case .yours: return "your-input"
    case .edge: return "edge-case"
    case .adversarial: return "adversarial"
    }
  }
}
