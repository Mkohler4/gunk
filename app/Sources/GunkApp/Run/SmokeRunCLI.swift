import Foundation

/// Headless `run` verb: lets the MCP `run_gunk` tool (T-10.12, ADR-0017) invoke
/// the **same** app-side `SmokeRunner` the GUI console (T-10.7) uses — one
/// sandbox, two callers. It reads a `RunInput` request as JSON from stdin, runs
/// it **buffered** through the production sandbox (agent origin; the
/// reduced-isolation fallback is never permitted for an agent run — it fails
/// closed instead), prints a `SmokeRunResult` as JSON to stdout, and exits.
///
/// No UI is started: like the `GUNK_RENDER_APPICON` export, this short-circuits
/// `main()` before `NSApplication.run()` when argv is `gunk run`.
enum SmokeRunCLI {
  /// The hard ceiling on a single agent run, independent of what the request
  /// asks for. The agent can never request an unbounded run (ADR-0017).
  static let maxTimeoutSeconds: Double = 120
  static let defaultTimeoutSeconds: Double = 30

  /// The request the MCP tool sends (a resolved `RunInput`). Safety is still
  /// re-derived Swift-side (classification, entrypoint validation, sandbox), so
  /// a malformed/poisoned request is refused by `SmokeRunner`, not trusted.
  struct Request: Decodable {
    let gunkId: Int64
    let bundlePath: String
    let language: String
    let entrypoints: [EntrypointDTO]
    let dependencies: [String]?
    let arguments: [String]?
    let timeoutSeconds: Double?

    struct EntrypointDTO: Decodable {
      let path: String
      let symbol: String?
    }
  }

  /// The receipt emitted back to the MCP tool — a flat, language-agnostic
  /// projection of `SmokeRunResult`.
  struct Response: Encodable {
    let gunkId: Int64
    let runnability: String
    let isolation: String
    let origin: String
    let command: String?
    let exitCode: Int32?
    let stdout: String
    let stderr: String
    let durationMs: Int
    let timedOut: Bool
    let passed: Bool
    let outputArtifacts: [String]
    let startedAt: String
  }

  /// Detects the `run` verb. Returns `true` (and runs to completion + exits)
  /// when handled, so `main()` can `return` before starting the UI.
  static func runIfRequested() -> Bool {
    let arguments = CommandLine.arguments
    guard arguments.count >= 2, arguments[1] == "run" else {
      return false
    }

    let requestData = FileHandle.standardInput.readDataToEndOfFile()
    let requestJSON = String(data: requestData, encoding: .utf8) ?? ""

    // Explicitly pin the agent's posture (ADR-0017): always sandboxed, and the
    // reduced-isolation fallback is *never* permitted for an agent run — it
    // fails closed. Stated here so the guarantee can't silently regress if
    // `SmokeRunner`'s init defaults ever change.
    let runner = SmokeRunner(useSandbox: true, allowReducedFallback: false)

    let semaphore = DispatchSemaphore(value: 0)
    var output = (json: errorJSON("run failed to start"), exitCode: Int32(1))
    Task {
      output = await execute(requestJSON: requestJSON, runner: runner)
      semaphore.signal()
    }
    semaphore.wait()

    FileHandle.standardOutput.write(Data((output.json + "\n").utf8))
    exit(output.exitCode)
  }

  /// Decodes the request, builds a `RunInput` (forcing `origin = .agent`), runs
  /// it buffered, and encodes the result. Pure of process-exit so it is unit
  /// testable with an injected `SmokeRunner`.
  static func execute(
    requestJSON: String,
    runner: SmokeRunner
  ) async -> (json: String, exitCode: Int32) {
    guard let data = requestJSON.data(using: .utf8), !data.isEmpty else {
      return (errorJSON("empty run request"), 1)
    }

    let request: Request
    do {
      request = try JSONDecoder().decode(Request.self, from: data)
    } catch {
      return (errorJSON("could not decode run request: \(error.localizedDescription)"), 1)
    }

    let input = RunInput(
      gunkId: request.gunkId,
      bundlePath: URL(fileURLWithPath: request.bundlePath),
      language: ModuleLanguage(rawLanguage: request.language),
      entrypoints: request.entrypoints.map { Entrypoint(path: $0.path, symbol: $0.symbol) },
      dependencies: request.dependencies ?? [],
      arguments: request.arguments ?? [],
      timeoutSeconds: clampTimeout(request.timeoutSeconds),
      origin: .agent
    )

    let result = await runner.run(input)
    return (encode(result, gunkId: request.gunkId), 0)
  }

  /// Clamps a requested timeout into `(0, maxTimeoutSeconds]`, defaulting when
  /// absent or non-positive. The agent can never request an unbounded run.
  static func clampTimeout(_ requested: Double?) -> Double {
    guard let requested, requested > 0 else {
      return defaultTimeoutSeconds
    }
    return min(requested, maxTimeoutSeconds)
  }

  static func encode(_ result: SmokeRunResult, gunkId: Int64) -> String {
    let response = Response(
      gunkId: gunkId,
      runnability: result.runnability.rawValue,
      isolation: result.isolation.rawValue,
      origin: result.origin.rawValue,
      command: result.command,
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
      durationMs: result.durationMs,
      timedOut: result.timedOut,
      passed: result.passed,
      outputArtifacts: result.outputArtifacts.map(\.path),
      startedAt: ISO8601DateFormatter().string(from: result.startedAt)
    )
    guard let data = try? JSONEncoder().encode(response),
          let json = String(data: data, encoding: .utf8) else {
      return errorJSON("could not encode run result")
    }
    return json
  }

  private static func errorJSON(_ message: String) -> String {
    let escaped = message
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "{\"error\":\"\(escaped)\"}"
  }
}
