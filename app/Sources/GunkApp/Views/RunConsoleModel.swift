import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Drives the smoke-run console (T-10.7): the developer's "Try it" door on the
/// module page. Owns the per-page run state — never-tried, first-run consent,
/// running/streaming, and the resting receipt — over the `BrowseModel`
/// orchestration (which builds the runner input, executes the sandboxed run,
/// and persists the receipt). UI state only; the durable proof lives in the
/// store (T-10.3). The v2 presentation over this engine is `RunConsoleStageView`.
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

  /// The typed-input surface (T-10.8): controls derived from the entrypoint
  /// signature, prefilled with the staged demo input and swappable. Empty +
  /// `reliable == false` → the page falls back to the bare zero-touch run.
  let signature: InputSignature
  /// The developer's current value per field id (prefilled from each field's
  /// demo value). Mutated as they swap inputs; composed into the run arguments.
  var fieldValues: [String: String]
  /// File sizes (bytes) for dropped file inputs, so the sandbox file-size cap
  /// can be enforced as quiet guidance before a run.
  private(set) var fileSizes: [String: Int] = [:]
  /// Set after a run the developer launched with *their own* input, so the
  /// "save as example" affordance appears (the end of the effort spectrum).
  private(set) var lastRunWasSwapped = false
  /// A just-saved example's name, for the brief "Saved" confirmation.
  private(set) var savedExampleName: String?
  /// Increments each time a run finishes (consent → run → done). The v2 run
  /// console (`RunConsoleStageView`) observes this to transition into its
  /// result + verdict state without polling the async run task.
  private(set) var runsCompleted: Int = 0

  /// Dev-only screenshot override (see `applyDebugOverride`): forces the
  /// classification so the neutral "not runnable here" state can be staged.
  private var runnabilityOverride: Runnability?
  /// Dev-only screenshot override: forces the typed-input signature so the
  /// prefilled/swapped/invalid/missing states can be staged deterministically.
  private var signatureOverride: InputSignature?

  private var runTask: Task<Void, Never>?

  init(model: BrowseModel, detail: BrowseModuleDetail) {
    self.model = model
    self.detail = detail
    self.receipt = model.lastSmokeRun(for: detail.item.gunk.id)
    let signature = model.inputSignature(for: detail)
    self.signature = signature
    self.fieldValues = Dictionary(
      uniqueKeysWithValues: signature.fields.map { ($0.id, $0.demoValue) }
    )
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

  /// The signature actually shown — a dev override when staging screenshots,
  /// otherwise the model's inference.
  var activeSignature: InputSignature {
    signatureOverride ?? signature
  }

  /// Whether to render the typed-input surface: a reliable, non-empty signature
  /// on a runnable module. Otherwise the console is the bare zero-touch run.
  var showsInputSurface: Bool {
    isRunnableHere && activeSignature.reliable && !activeSignature.isEmpty
  }

  /// The developer's current values composed into positional run arguments.
  var composedArguments: [String] {
    activeSignature.arguments(from: fieldValues)
  }

  /// Whether any field carries a value the developer brought (differs from the
  /// staged demo and is non-empty) — gates the "save as example" affordance and
  /// the `yours` coverage class.
  var hasSwappedInput: Bool {
    activeSignature.fields.contains { field in
      let value = (fieldValues[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      return !value.isEmpty && value != field.demoValue
    }
  }

  /// The command the run will (or did) execute, reflecting the composed input,
  /// for the consent treatment and the console header.
  var command: String? {
    model.resolvedRunCommand(for: detail, arguments: composedArguments)
  }

  /// The validation state of a field's current value, for quiet guidance.
  func validation(for field: InputField) -> InputFieldValidation {
    InputValidator.validate(
      field: field,
      value: fieldValues[field.id] ?? "",
      fileSizeBytes: fileSizes[field.id]
    )
  }

  /// Whether any field has a blocking problem (missing requirement, wrong file
  /// type, too large, not a number) — Run is disabled until it's resolved.
  var hasBlockingValidation: Bool {
    activeSignature.fields.contains { validation(for: $0) != .ok }
  }

  /// The working directory promise: a *throwaway copy* of the bundle, never the
  /// developer's source (ADR-0016). We show the bundle's name, not its path.
  var bundleName: String? {
    detail.bundlePath.map { URL(fileURLWithPath: $0).lastPathComponent }
  }

  // MARK: Intents

  /// The single "Try it" entry point. Asks for first-run consent once per
  /// module (inferred from any prior receipt), then runs. Always works at the
  /// prefilled demo values (the zero-touch floor); blocked only when a swapped
  /// input is invalid (quiet guidance, not a failure).
  func tryIt() {
    guard isRunnableHere, !isRunning, !hasBlockingValidation else {
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

  /// Swap a text/number/choice value. Clears the just-saved confirmation so the
  /// "save as example" affordance re-arms for the new input.
  func setValue(_ value: String, for field: InputField) {
    fieldValues[field.id] = value
    savedExampleName = nil
  }

  /// Swap a file input from a dropped/picked URL: stores its path (read inside
  /// the sandbox — reads are allowed; writes/network are not) and its size so
  /// the cap can be enforced as quiet guidance.
  func setFile(_ url: URL, for field: InputField) {
    fieldValues[field.id] = url.path
    fileSizes[field.id] = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    savedExampleName = nil
  }

  /// Reset a field to its staged-demo value (the one-gesture "back to demo").
  func resetToDemo(_ field: InputField) {
    fieldValues[field.id] = field.demoValue
    fileSizes[field.id] = nil
    savedExampleName = nil
  }

  /// Persist the current input as a named example (T-10.3). The developer's own
  /// input is the `yours` coverage class; the untouched demo is `happy`. The
  /// saved-example list + re-run are T-10.10 — this wires the save action only.
  func saveAsExample(name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return
    }
    let saved = model.saveExample(
      for: detail,
      name: trimmed,
      input: composedArguments.joined(separator: " "),
      inputClass: hasSwappedInput ? .yours : .happy
    )
    if saved != nil {
      savedExampleName = trimmed
    }
  }

  private func run() {
    guard !isRunning else {
      return
    }

    liveLog = ""
    runStartedAt = Date()
    lastRunWasSwapped = hasSwappedInput
    savedExampleName = nil
    phase = .running

    let arguments = composedArguments
    runTask = Task { [weak self] in
      guard let self else {
        return
      }

      let record = await self.model.runSmokeTest(for: self.detail, arguments: arguments) { [weak self] event in
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
      self.runsCompleted += 1
    }
  }

  // MARK: Debug staging (screenshots)

  /// Dev-only screenshot hook (same family as `GUNK_DEBUG_MODULE_PAGE`): stages
  /// a console state at launch so every CP-F state can be captured without live
  /// execution. Pair with `GUNK_DEBUG_MODULE_PAGE=first|<id>` to open the page.
  /// Values: `nevertried`, `consent`, `running`, `passed`, `failed`,
  /// `unrunnable`, `uimodule` (the T-10.13 deferred UI-module state), and the
  /// typed-input surface (T-10.8): `prefilled`, `swapped`, `invalid`,
  /// `missing`, `dropwell`.
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
    case "uimodule":
      runnabilityOverride = .uiModule
    case "prefilled", "dropwell":
      stageInputSurface(values: [:])
    case "swapped":
      stageInputSurface(values: ["input-file": "/Users/you/Documents/my-book.epub"])
      fileSizes["input-file"] = 2_400_000
    case "invalid":
      stageInputSurface(values: ["input-file": "/Users/you/Documents/notes.txt"])
    case "missing":
      stageInputSurface(values: ["input-file": ""], required: true)
    default:
      break
    }
  }

  /// Stages the typed-input surface with a canned `.epub` file field so the
  /// prefilled/swapped/invalid/missing/drop-well states are screenshot-able
  /// without a module whose real signature happens to infer a file input.
  private func stageInputSurface(values: [String: String], required: Bool = false) {
    runnabilityOverride = .terminalRunnable
    receipt = nil
    let field = InputField(
      id: "input-file",
      label: "Input file",
      kind: .file(extensions: ["epub"]),
      hint: "This entrypoint takes a .epub file. Drop your own to run it on your data.",
      required: required
    )
    signatureOverride = InputSignature(fields: [field], reliable: true)
    fieldValues = ["input-file": values["input-file"] ?? ""]
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
