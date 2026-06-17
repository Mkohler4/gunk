struct Source: Equatable, Identifiable, Sendable {
  let id: Int64
  let name: String
  let path: String
  let droppedAt: Int64
  let removedAt: Int64?
}

struct Gunk: Equatable, Identifiable, Sendable {
  let id: Int64
  let sourceId: Int64
  let name: String
  let purpose: String?
  let language: String?
  let confidence: Double?
  let bundlePath: String?
  let manifestPath: String?
  let extractedAt: Int64?
  let approvedAt: Int64?
  let removedAt: Int64?
  /// Durable model attribution (T-9.2): the provider/model that created this
  /// module, written at extraction time (or backfilled from a `RunTrace`).
  /// `nil` for modules with no resolvable run — they render the neutral mark.
  /// Defaulted so the many existing `Gunk(...)` call sites are unaffected.
  var provider: String? = nil
  var model: String? = nil
}

struct Tag: Equatable, Identifiable, Sendable {
  let id: Int64
  let name: String
}

struct GunkTag: Equatable, Sendable {
  let gunkId: Int64
  let tagId: Int64
  let tag: String
  let confidence: Double?
}

struct GunkFile: Equatable, Identifiable, Sendable {
  let id: Int64
  let gunkId: Int64
  let relpath: String
  let size: Int64?
}

struct LLMRun: Equatable, Identifiable, Sendable {
  let id: Int64
  let sourceId: Int64?
  let provider: String
  let model: String
  let inputTokens: Int64?
  let outputTokens: Int64?
  let costUsd: Double?
  let startedAt: Int64
  let finishedAt: Int64?
}

struct LLMRunAggregate: Equatable, Sendable {
  let provider: String
  let model: String
  let inputTokens: Int64
  let outputTokens: Int64
  let runCount: Int
  let hasUnknownTokens: Bool
}

struct GunkEmbedding: Equatable, Identifiable, Sendable {
  var id: Int64 { gunkId }

  let gunkId: Int64
  let vector: [Double]
  let dim: Int
  let model: String
}

/// The developer's binary judgement on a run or an example (module-run-v2:
/// the verdict stays binary — `right`/`wrong` — and the *note* carries any
/// nuance). `nil` when not yet judged.
enum RunVerdict: String, Equatable, Sendable, Codable {
  case right
  case wrong
}

/// The four coverage axes a saved example belongs to (CP-F open question #1).
/// These are a flat description of *which class of input* a fixture exercises,
/// never a tier to climb. A pinned failing case is an `edge`/`adversarial`
/// example with an `expectedOutput` + `note`; a known limit is an
/// `adversarial` example with a `note`.
enum ExampleInputClass: String, Equatable, Sendable, Codable {
  /// The shipped/synthesized demo — the lowest honest evidence.
  case happy
  /// An input the developer brought themselves (the `yours` provenance).
  case yours
  /// A boundary/edge-case input.
  case edge
  /// A "try to break it" input.
  case adversarial
}

/// A durable smoke-run receipt (T-10.3) — one row per execution or refusal.
/// Persists the CP-F receipt fields so proof survives `RunTrace` pruning
/// (Hard data fact 2). No store writes happen in the runner itself; the
/// console (T-10.7) and the MCP tool (T-10.12) each persist one of these.
struct SmokeRunRecord: Equatable, Identifiable, Sendable {
  let id: Int64
  let gunkId: Int64
  /// The example/input this run used, if any. `nil` for an ad-hoc run.
  let exampleId: Int64?
  /// The resolved command line that ran, for display. `nil` when not run.
  let command: String?
  /// The runnability classification — only `.terminalRunnable` was executed.
  let runnability: Runnability
  /// Who initiated the run, so agent volume never reads as human-checked.
  let origin: RunOrigin
  let exitCode: Int32?
  /// The clean-exit *fact* (`nil` when the module was not actually executed).
  /// Distinct from `verdict`: a passing exit is evidence, not a judgement.
  let passed: Bool?
  let timedOut: Bool
  let durationMs: Int
  /// Path to an artifact left in the run dir — never the bytes; prunes with
  /// the run dir.
  let outputArtifactPath: String?
  /// Captured stdout/stderr.
  let log: String
  /// The developer's verdict on this run (`nil` until they judge).
  let verdict: RunVerdict?
  let createdAt: Int64
}

/// A saved/golden example — the developer's fixture library, listed by the
/// coverage ledger. Folds pinned failing cases and known limits into one
/// table via `inputClass` + `expectedOutput`/`note` (CP-F open question #10,
/// capture-and-queue).
struct ModuleExample: Equatable, Identifiable, Sendable {
  let id: Int64
  let gunkId: Int64
  let name: String
  /// The input (or an input ref) this example feeds the entrypoint.
  let input: String
  let inputClass: ExampleInputClass
  /// The canonical example a future run diffs against. Exclusive per
  /// `(gunkId, inputClass)`.
  let isGolden: Bool
  let verdict: RunVerdict?
  /// The output the developer says it *should* produce (for a pinned failing
  /// case / correction). `nil` for a plain passing example.
  let expectedOutput: String?
  /// A free-text note — the "what's wrong" correction or a known-limit record.
  let note: String?
  let createdAt: Int64
}
