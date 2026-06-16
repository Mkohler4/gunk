import Foundation

/// A chunk of live output from a running process.
enum RunOutputChunk: Sendable {
  case stdout(String)
  case stderr(String)
}

/// The terminal outcome of spawning a process (exit + timeout), separate from
/// its captured output (which streams through the chunk callback).
struct ProcessOutcome: Sendable {
  let exitCode: Int32?
  let timedOut: Bool
  /// Set only when the process failed to *launch* (vs. ran and exited).
  let launchError: String?
}

/// Spawns the already-wrapped command, streams its output, enforces the hard
/// timeout, and reports the outcome. Abstracted so `SmokeRunner`'s
/// orchestration (classify → stage → resolve → run → collect) is testable
/// with a canned executor instead of a real subprocess.
protocol SandboxedProcessRunner: Sendable {
  func run(
    executable: URL,
    arguments: [String],
    workingDirectory: URL,
    environment: [String: String],
    timeoutSeconds: Double,
    onChunk: @escaping @Sendable (RunOutputChunk) -> Void
  ) async -> ProcessOutcome
}

/// Executes a module's entrypoint against a throwaway copy of its bundle and
/// captures a structured result, enforcing the ADR-0016 contract: copy the
/// bundle (never run in place), confine writes to the run directory, deny
/// network, time-box, and never inherit the parent's (secret-bearing) env.
///
/// No store writes, no UI. Returns a `SmokeRunResult`; persistence is T-10.3.
struct SmokeRunner {
  /// Root for run directories: `<runsRoot>/<gunkId>/<timestamp>/`. Defaults
  /// to `~/.gunk/runs/smoke`.
  let runsRoot: URL
  let processRunner: SandboxedProcessRunner
  /// Resolves an interpreter name (e.g. `python3`) to an absolute path, or
  /// `nil` if it is not installed.
  let interpreterLocator: @Sendable (String) -> URL?
  /// Whether to wrap runs in `sandbox-exec`. Production: true. Tests that run
  /// under an outer sandbox (where Seatbelt can't nest) pass false — that is
  /// an explicit, labeled opt-out into the reduced-isolation path.
  let useSandbox: Bool
  /// When `useSandbox` is true but the sandbox can't be applied (`sandbox-exec`
  /// missing or the profile can't be written), whether to *silently* fall
  /// back to reduced isolation. Defaults to **false: fail closed** — refuse
  /// to run rather than run untrusted code without the promised network/write
  /// confinement (security review, 2026-06-15). A caller that genuinely wants
  /// the documented fallback must opt in explicitly (and surface it).
  let allowReducedFallback: Bool
  /// Whether the Seatbelt sandbox can be applied. Injectable so the
  /// fail-closed path is testable without depending on the host.
  let isSandboxAvailable: @Sendable () -> Bool
  let fileManager: FileManager
  let now: @Sendable () -> Date

  init(
    runsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".gunk/runs/smoke"),
    processRunner: SandboxedProcessRunner = ProcessSandboxRunner(),
    interpreterLocator: @escaping @Sendable (String) -> URL? = SmokeRunner.locateOnPath,
    useSandbox: Bool = true,
    allowReducedFallback: Bool = false,
    isSandboxAvailable: @escaping @Sendable () -> Bool = { RunSandbox.isAvailable() },
    fileManager: FileManager = .default,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.runsRoot = runsRoot
    self.processRunner = processRunner
    self.interpreterLocator = interpreterLocator
    self.useSandbox = useSandbox
    self.allowReducedFallback = allowReducedFallback
    self.isSandboxAvailable = isSandboxAvailable
    self.fileManager = fileManager
    self.now = now
  }

  // MARK: - Buffered entry point (the MCP tool, T-10.12)

  func run(_ input: RunInput) async -> SmokeRunResult {
    await execute(input, emit: { _ in })
  }

  // MARK: - Streaming entry point (the live console, T-10.7)

  func runStreaming(_ input: RunInput) -> AsyncThrowingStream<RunStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      Task {
        let result = await execute(input) { event in
          continuation.yield(event)
        }
        // `execute` already emits `.finished`; just close the stream.
        _ = result
        continuation.finish()
      }
    }
  }

  // MARK: - Core

  private func execute(
    _ input: RunInput,
    emit: @escaping @Sendable (RunStreamEvent) -> Void
  ) async -> SmokeRunResult {
    let startedAt = now()
    let clockStart = ContinuousClock.now

    let runnability = RunnabilityClassifier.classify(input)
    guard runnability == .terminalRunnable else {
      return notRun(runnability, input: input, startedAt: startedAt)
    }

    guard let resolved = EntrypointResolver.resolve(input) else {
      return notRun(.cannotDetermine, input: input, startedAt: startedAt)
    }

    guard let interpreter = interpreterLocator(resolved.executable) else {
      // We know the language but the interpreter isn't installed: honest
      // "can't run it here" rather than a misleading crash.
      return notRun(
        .cannotDetermine,
        input: input,
        startedAt: startedAt,
        stderr: "\(resolved.executable) was not found on PATH."
      )
    }

    // Stage a throwaway copy of the bundle. Never execute in place.
    let runDirectory = runsRoot
      .appendingPathComponent(String(input.gunkId))
      .appendingPathComponent(timestampSlug(startedAt))
    let bundleCopy = runDirectory.appendingPathComponent(input.bundlePath.lastPathComponent)

    do {
      try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: true)
      try fileManager.copyItem(at: input.bundlePath, to: bundleCopy)
    } catch {
      return failed(
        reason: "Failed to stage the bundle for a sandboxed run: \(error.localizedDescription)",
        command: resolved.display, input: input, startedAt: startedAt, clockStart: clockStart
      )
    }

    // Defense-in-depth: the resolver already rejected `..`/absolute/flag
    // paths, but re-verify the entry resolves *inside* the staged copy after
    // symlink resolution, so a symlinked entry can't point out of the bundle.
    let entryRelative = resolved.arguments.first ?? ""
    let entryURL = bundleCopy.appendingPathComponent(entryRelative).resolvingSymlinksInPath()
    let bundleRoot = bundleCopy.resolvingSymlinksInPath()
    guard entryURL.path == bundleRoot.path || entryURL.path.hasPrefix(bundleRoot.path + "/") else {
      return failed(
        reason: "Refusing to run: entrypoint resolves outside the module bundle.",
        command: resolved.display, input: input, startedAt: startedAt, clockStart: clockStart
      )
    }

    let filesBefore = snapshotFiles(under: runDirectory)

    // Build the command: sandbox-wrapped when possible. We never run
    // unbounded — and we never *silently* drop the sandbox: if the sandbox
    // was requested but can't be applied, we fail closed unless the caller
    // explicitly opted into the reduced-isolation fallback (ADR-0016 +
    // security review). The timeout and scoped cwd apply in every shape.
    let executable: URL
    let arguments: [String]
    let isolation: RunIsolation
    if useSandbox {
      guard isSandboxAvailable() else {
        if allowReducedFallback {
          executable = interpreter
          arguments = resolved.arguments
          isolation = .reducedFallback
          emit(.started(command: resolved.display))
          return await spawn(
            executable: executable, arguments: arguments, bundleCopy: bundleCopy,
            runDirectory: runDirectory, filesBefore: filesBefore, command: resolved.display,
            isolation: isolation, input: input, startedAt: startedAt, clockStart: clockStart, emit: emit
          )
        }
        return failed(
          reason: "Refusing to run without isolation: sandbox-exec is unavailable on this machine.",
          command: resolved.display, input: input, startedAt: startedAt, clockStart: clockStart
        )
      }
      let profile = RunSandbox.profile(runDirectory: runDirectory)
      do {
        let profilePath = try RunSandbox.writeProfile(profile, into: runDirectory, fileManager: fileManager)
        let wrapped = RunSandbox.wrap(interpreter: interpreter, arguments: resolved.arguments, profilePath: profilePath)
        executable = wrapped.executable
        arguments = wrapped.arguments
        isolation = .sandboxExec
      } catch {
        if allowReducedFallback {
          executable = interpreter
          arguments = resolved.arguments
          isolation = .reducedFallback
          emit(.started(command: resolved.display))
          return await spawn(
            executable: executable, arguments: arguments, bundleCopy: bundleCopy,
            runDirectory: runDirectory, filesBefore: filesBefore, command: resolved.display,
            isolation: isolation, input: input, startedAt: startedAt, clockStart: clockStart, emit: emit
          )
        }
        return failed(
          reason: "Refusing to run without isolation: could not write the sandbox profile (\(error.localizedDescription)).",
          command: resolved.display, input: input, startedAt: startedAt, clockStart: clockStart
        )
      }
    } else {
      // Explicit, labeled opt-out (dev/tests under an outer sandbox).
      executable = interpreter
      arguments = resolved.arguments
      isolation = .reducedFallback
    }

    emit(.started(command: resolved.display))
    return await spawn(
      executable: executable, arguments: arguments, bundleCopy: bundleCopy,
      runDirectory: runDirectory, filesBefore: filesBefore, command: resolved.display,
      isolation: isolation, input: input, startedAt: startedAt, clockStart: clockStart, emit: emit
    )
  }

  /// Spawns the resolved command, accumulates output, computes artifacts, and
  /// assembles the final result. Shared by the sandboxed and (labeled)
  /// reduced-isolation shapes so there is exactly one executor path.
  private func spawn(
    executable: URL,
    arguments: [String],
    bundleCopy: URL,
    runDirectory: URL,
    filesBefore: Set<String>,
    command: String,
    isolation: RunIsolation,
    input: RunInput,
    startedAt: Date,
    clockStart: ContinuousClock.Instant,
    emit: @escaping @Sendable (RunStreamEvent) -> Void
  ) async -> SmokeRunResult {

    let accumulator = OutputAccumulator()
    let outcome = await processRunner.run(
      executable: executable,
      arguments: arguments,
      workingDirectory: bundleCopy,
      environment: sandboxEnvironment(),
      timeoutSeconds: input.timeoutSeconds,
      onChunk: { chunk in
        accumulator.append(chunk)
        switch chunk {
        case .stdout(let text): emit(.stdout(text))
        case .stderr(let text): emit(.stderr(text))
        }
      }
    )

    let filesAfter = snapshotFiles(under: runDirectory)
    let artifacts = filesAfter
      .subtracting(filesBefore)
      .sorted()
      .map { URL(fileURLWithPath: $0) }

    var stderr = accumulator.stderr()
    if let launchError = outcome.launchError {
      stderr = stderr.isEmpty ? launchError : stderr + "\n" + launchError
    }

    let result = SmokeRunResult(
      runnability: .terminalRunnable,
      command: command,
      exitCode: outcome.exitCode,
      stdout: accumulator.stdout(),
      stderr: stderr,
      durationMs: elapsedMs(since: clockStart),
      timedOut: outcome.timedOut,
      outputArtifacts: artifacts,
      startedAt: startedAt,
      isolation: isolation,
      origin: input.origin
    )
    emit(.finished(result))
    return result
  }

  // MARK: - Helpers

  private func notRun(
    _ runnability: Runnability,
    input: RunInput,
    startedAt: Date,
    stderr: String = ""
  ) -> SmokeRunResult {
    SmokeRunResult(
      runnability: runnability,
      command: nil,
      exitCode: nil,
      stdout: "",
      stderr: stderr,
      durationMs: 0,
      timedOut: false,
      outputArtifacts: [],
      startedAt: startedAt,
      isolation: .notRun,
      origin: input.origin
    )
  }

  /// A module classified runnable that we deliberately did **not** execute —
  /// because staging failed, the entrypoint escaped the bundle, or the
  /// sandbox couldn't be applied and fallback wasn't permitted. `isolation`
  /// is `.notRun` and the reason is in `stderr`; `passed` stays false.
  private func failed(
    reason: String,
    command: String,
    input: RunInput,
    startedAt: Date,
    clockStart: ContinuousClock.Instant
  ) -> SmokeRunResult {
    SmokeRunResult(
      runnability: .terminalRunnable,
      command: command,
      exitCode: nil,
      stdout: "",
      stderr: reason,
      durationMs: elapsedMs(since: clockStart),
      timedOut: false,
      outputArtifacts: [],
      startedAt: startedAt,
      isolation: .notRun,
      origin: input.origin
    )
  }

  /// A minimal environment: PATH so the interpreter resolves, nothing else.
  /// The parent's environment (which may carry API keys/secrets) is never
  /// passed through (ADR-0016).
  private func sandboxEnvironment() -> [String: String] {
    ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"]
  }

  private func snapshotFiles(under directory: URL) -> Set<String> {
    guard
      let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey]
      )
    else {
      return []
    }
    var files: Set<String> = []
    for case let url as URL in enumerator {
      if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
        files.insert(url.path)
      }
    }
    return files
  }

  private func timestampSlug(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
  }

  private func elapsedMs(since start: ContinuousClock.Instant) -> Int {
    let elapsed = ContinuousClock.now - start
    let seconds = Double(elapsed.components.seconds)
    let fractional = Double(elapsed.components.attoseconds) / 1e18
    return Int((seconds + fractional) * 1000)
  }

  /// Resolves an executable name to an absolute URL by walking PATH — the
  /// same pattern as `EngineBinary.locate`.
  @Sendable
  static func locateOnPath(_ executable: String) -> URL? {
    let path = ProcessInfo.processInfo.environment["PATH"]
      ?? "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
    let fileManager = FileManager.default
    return path
      .split(separator: ":")
      .map { URL(fileURLWithPath: String($0)).appendingPathComponent(executable) }
      .first { fileManager.isExecutableFile(atPath: $0.path) }
  }
}

/// Thread-safe accumulator for streamed stdout/stderr (the chunk callback
/// fires on background reader threads).
private final class OutputAccumulator: @unchecked Sendable {
  private let lock = NSLock()
  private var out = ""
  private var err = ""

  func append(_ chunk: RunOutputChunk) {
    lock.lock()
    defer { lock.unlock() }
    switch chunk {
    case .stdout(let text): out += text
    case .stderr(let text): err += text
    }
  }

  func stdout() -> String {
    lock.lock(); defer { lock.unlock() }
    return out
  }

  func stderr() -> String {
    lock.lock(); defer { lock.unlock() }
    return err
  }
}

/// Production executor: runs the command as a child `Process`, streaming
/// stdout/stderr off pipes and terminating it if it overruns the timeout.
struct ProcessSandboxRunner: SandboxedProcessRunner {
  func run(
    executable: URL,
    arguments: [String],
    workingDirectory: URL,
    environment: [String: String],
    timeoutSeconds: Double,
    onChunk: @escaping @Sendable (RunOutputChunk) -> Void
  ) async -> ProcessOutcome {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory
    process.environment = environment

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
      onChunk(.stdout(text))
    }
    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
      onChunk(.stderr(text))
    }

    let timedOut = TimeoutFlag()
    let timeoutBox = TaskBox()

    return await withCheckedContinuation { continuation in
      // Set the termination handler *before* run() so a fast-exiting process
      // can't terminate before we are listening (which would hang the await).
      process.terminationHandler = { process in
        timeoutBox.cancel()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        // Drain anything buffered after the last readability callback.
        let restOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if !restOut.isEmpty, let text = String(data: restOut, encoding: .utf8) {
          onChunk(.stdout(text))
        }
        let restErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if !restErr.isEmpty, let text = String(data: restErr, encoding: .utf8) {
          onChunk(.stderr(text))
        }
        continuation.resume(
          returning: ProcessOutcome(
            exitCode: process.terminationStatus,
            timedOut: timedOut.get(),
            launchError: nil
          )
        )
      }

      do {
        try process.run()
      } catch {
        process.terminationHandler = nil
        continuation.resume(
          returning: ProcessOutcome(exitCode: nil, timedOut: false, launchError: error.localizedDescription)
        )
        return
      }

      // Put the child in its own process group so a timeout can kill the
      // *whole tree* (forked grandchildren — `subprocess`, workers — not just
      // the direct child). Doing this from the parent races the child's exec,
      // but `setpgid` succeeds while the child is still in our session; only
      // when it returns 0 do we own a dedicated group safe to signal with a
      // negative pid (security review, 2026-06-15).
      let pid = process.processIdentifier
      let ownsGroup = pid > 0 && setpgid(pid, pid) == 0

      timeoutBox.start(seconds: timeoutSeconds) { [weak process] in
        guard let process, process.isRunning else { return }
        timedOut.set()
        if ownsGroup {
          // SIGKILL the entire group; -pid targets the child's group, never ours.
          kill(-pid, SIGKILL)
        } else {
          process.terminate()
        }
      }
    }
  }
}

/// Holds the timeout task so the termination handler can cancel it regardless
/// of ordering races with a fast-exiting process.
private final class TaskBox: @unchecked Sendable {
  private let lock = NSLock()
  private var task: Task<Void, Never>?

  func start(seconds: Double, _ onTimeout: @escaping @Sendable () -> Void) {
    let task = Task {
      try? await Task.sleep(for: .seconds(seconds))
      if !Task.isCancelled { onTimeout() }
    }
    lock.lock()
    self.task = task
    lock.unlock()
  }

  func cancel() {
    lock.lock()
    let task = self.task
    lock.unlock()
    task?.cancel()
  }
}

/// A tiny lock-guarded bool so the timeout task and the reader can share the
/// "did we kill it" flag safely.
private final class TimeoutFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  func set() { lock.lock(); value = true; lock.unlock() }
  func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}
