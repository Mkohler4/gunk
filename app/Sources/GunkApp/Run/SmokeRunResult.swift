import Foundation

/// How a module should be run — or why it can't be run *here*. Produced by
/// `RunnabilityClassifier` before any execution. Only `.terminalRunnable`
/// is actually executed this phase (ADR-0016); every other case is a typed
/// "runnable here: not yet" reason the page renders as a neutral state,
/// never a failed run.
enum Runnability: String, Equatable, Sendable, Codable {
  /// A one-shot CLI/library entrypoint the sandbox can fairly execute.
  case terminalRunnable = "terminal-runnable"
  /// The module's job is to call out to the network (sandbox is network-off).
  case needsNetwork = "needs-network"
  /// Requires credentials/secrets not present in the sandbox.
  case needsSecrets = "needs-secrets"
  /// A CLI that prompts and reads from stdin — the one-shot runner can't answer.
  case interactiveStdin = "interactive-stdin"
  /// A server/watcher/TUI that does not terminate.
  case longRunning = "long-running"
  /// Output *is* a UI surface (deferred to T-10.13).
  case uiModule = "ui-module"
  /// gunk cannot confidently derive how to run it.
  case cannotDetermine = "cannot-determine"

  /// Whether this class is executed this phase.
  var isExecutable: Bool { self == .terminalRunnable }
}

/// How the run was isolated. The promise the UI makes at first-run consent
/// is only honest for `.sandboxExec`; `.reducedFallback` is labeled weaker.
enum RunIsolation: String, Equatable, Sendable, Codable {
  /// Wrapped in `sandbox-exec` with the deny-by-default Seatbelt profile.
  case sandboxExec = "sandbox-exec"
  /// `sandbox-exec` unavailable: a constrained `Process` (scoped cwd, no
  /// inherited env, hard timeout) — weaker isolation, explicitly labeled.
  case reducedFallback = "reduced-fallback"
  /// Not executed (a not-runnable-here classification).
  case notRun = "not-run"
}

/// Who initiated the run, so agent volume never reads as human-checked
/// evidence (CP-F decision #8). The runner records it; the evidence readout
/// (T-10.11) keeps the piles separate.
enum RunOrigin: String, Equatable, Sendable, Codable {
  case human
  case agent
}

/// The structured result of a smoke run (or a refusal to run). Returned by
/// both the buffered and streaming entry points — the streaming consumer
/// receives the same value in its terminal `.finished` event.
///
/// No store writes happen here (that is T-10.3); this is a value the
/// developer's console (T-10.7) and the MCP tool (T-10.12) each persist.
struct SmokeRunResult: Equatable, Sendable {
  /// The classification. `.terminalRunnable` means it was executed; any
  /// other value means it was deliberately *not* executed.
  let runnability: Runnability
  /// The resolved command line that ran, for display. `nil` when not run.
  let command: String?
  /// Process exit status. `nil` when not run or when launch failed.
  let exitCode: Int32?
  let stdout: String
  let stderr: String
  let durationMs: Int
  /// The run exceeded the hard timeout. A *fact*, not an error.
  let timedOut: Bool
  /// New files left inside the run directory by the run.
  let outputArtifacts: [URL]
  let startedAt: Date
  let isolation: RunIsolation
  let origin: RunOrigin

  /// A run that executed and exited cleanly. Distinct from "trustworthy" —
  /// a passing exit is evidence, not a verdict (the developer judges).
  var passed: Bool {
    runnability == .terminalRunnable && !timedOut && exitCode == 0
  }
}

/// A module's run-relevant facts, assembled by the caller from stored
/// entrypoints + language + the parsed dependency manifest (T-10.6). The
/// runner consumes this; it does not read the store itself.
///
/// **Future-vision seam (ADR-0016):** this describes a single self-contained
/// bundle to stage. It deliberately does not hard-code that assumption into
/// its shape, so a later parent-gunk run can stage "bundle + resolved
/// gunk-deps" without reshaping the runner.
struct RunInput: Equatable, Sendable {
  let gunkId: Int64
  /// The extracted bundle (read-only source — copied into the run dir,
  /// never executed in place).
  let bundlePath: URL
  let language: ModuleLanguage
  let entrypoints: [Entrypoint]
  /// Declared dependency names from the manifest (lowercased is fine), used
  /// only to classify runnability — not installed or resolved here.
  let dependencies: [String]
  /// Extra arguments the active intent verb composed onto the command
  /// (e.g. `--in corrupt.epub`).
  let arguments: [String]
  /// Hard timeout. Default 30s (ADR-0016).
  let timeoutSeconds: Double
  let origin: RunOrigin

  init(
    gunkId: Int64,
    bundlePath: URL,
    language: ModuleLanguage,
    entrypoints: [Entrypoint],
    dependencies: [String] = [],
    arguments: [String] = [],
    timeoutSeconds: Double = 30,
    origin: RunOrigin = .human
  ) {
    self.gunkId = gunkId
    self.bundlePath = bundlePath
    self.language = language
    self.entrypoints = entrypoints
    self.dependencies = dependencies
    self.arguments = arguments
    self.timeoutSeconds = timeoutSeconds
    self.origin = origin
  }
}

/// An entrypoint into the module: a file path (relative to the bundle) and
/// an optional exported symbol. Mirrors `RunTrace.Surface` (Hard data fact 4).
struct Entrypoint: Equatable, Sendable {
  let path: String
  let symbol: String?

  init(path: String, symbol: String? = nil) {
    self.path = path
    self.symbol = symbol
  }
}

/// The languages with a confident one-shot interpreter this phase. Anything
/// else classifies as `.cannotDetermine` rather than guessing a command.
enum ModuleLanguage: Equatable, Sendable {
  case python
  case node
  case other(String)

  /// Maps an engine/trace language string (best-effort, case-insensitive).
  init(rawLanguage: String) {
    switch rawLanguage.lowercased() {
    case "python", "py":
      self = .python
    case "javascript", "typescript", "js", "ts", "jsx", "tsx", "node", "nodejs":
      self = .node
    default:
      self = .other(rawLanguage)
    }
  }
}

/// A resolved interpreter command (before sandbox wrapping). `executable` is
/// the interpreter name to locate on PATH; `arguments` are passed after it.
struct ResolvedCommand: Equatable, Sendable {
  let executable: String
  let arguments: [String]

  /// A human-readable command line for the console + the receipt.
  var display: String {
    ([executable] + arguments).joined(separator: " ")
  }
}

/// Streaming events for the live console (T-10.7). The buffered entry point
/// returns the `.finished` payload directly.
enum RunStreamEvent: Sendable {
  case started(command: String)
  case stdout(String)
  case stderr(String)
  case finished(SmokeRunResult)
}
