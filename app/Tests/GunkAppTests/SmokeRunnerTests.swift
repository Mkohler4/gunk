import XCTest
@testable import GunkApp

final class SmokeRunnerTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }

  // MARK: - Runnability classification (CP-F decision #9)

  func testClassifiesPythonEntrypointAsTerminalRunnable() {
    let input = makeInput(language: .python, entrypoints: [Entrypoint(path: "main.py")])
    XCTAssertEqual(RunnabilityClassifier.classify(input), .terminalRunnable)
  }

  func testClassifiesNodeEntrypointAsTerminalRunnable() {
    let input = makeInput(language: .node, entrypoints: [Entrypoint(path: "index.js", symbol: "run")])
    XCTAssertEqual(RunnabilityClassifier.classify(input), .terminalRunnable)
  }

  func testNoEntrypointCannotDetermine() {
    let input = makeInput(language: .python, entrypoints: [])
    XCTAssertEqual(RunnabilityClassifier.classify(input), .cannotDetermine)
  }

  func testUnsupportedLanguageCannotDetermine() {
    let input = makeInput(language: .other("go"), entrypoints: [Entrypoint(path: "main.go")])
    XCTAssertEqual(RunnabilityClassifier.classify(input), .cannotDetermine)
  }

  func testNetworkDependencyMarksNeedsNetwork() {
    let input = makeInput(language: .node, entrypoints: [Entrypoint(path: "fetch.js")], dependencies: ["axios"])
    XCTAssertEqual(RunnabilityClassifier.classify(input), .needsNetwork)
  }

  func testServerDependencyMarksLongRunning() {
    let input = makeInput(language: .node, entrypoints: [Entrypoint(path: "server.js")], dependencies: ["express"])
    XCTAssertEqual(RunnabilityClassifier.classify(input), .longRunning)
  }

  func testUiDependencyMarksUiModule() {
    let input = makeInput(language: .node, entrypoints: [Entrypoint(path: "app.jsx")], dependencies: ["react", "react-dom"])
    XCTAssertEqual(RunnabilityClassifier.classify(input), .uiModule)
  }

  func testSecretSdkMarksNeedsSecrets() {
    let input = makeInput(language: .python, entrypoints: [Entrypoint(path: "upload.py")], dependencies: ["boto3"])
    XCTAssertEqual(RunnabilityClassifier.classify(input), .needsSecrets)
  }

  func testInteractiveDependencyMarksInteractiveStdin() {
    let input = makeInput(language: .node, entrypoints: [Entrypoint(path: "cli.js")], dependencies: ["inquirer"])
    XCTAssertEqual(RunnabilityClassifier.classify(input), .interactiveStdin)
  }

  // MARK: - Entrypoint resolution

  func testResolvesPythonCommand() {
    let input = makeInput(language: .python, entrypoints: [Entrypoint(path: "parser.py")], arguments: ["--in", "x.epub"])
    let command = EntrypointResolver.resolve(input)
    XCTAssertEqual(command?.executable, "python3")
    XCTAssertEqual(command?.arguments, ["parser.py", "--in", "x.epub"])
    XCTAssertEqual(command?.display, "python3 parser.py --in x.epub")
  }

  func testResolvesNodeCommand() {
    let input = makeInput(language: .node, entrypoints: [Entrypoint(path: "index.js")])
    XCTAssertEqual(EntrypointResolver.resolve(input)?.executable, "node")
  }

  func testResolutionFailsForUnsupportedLanguage() {
    let input = makeInput(language: .other("ruby"), entrypoints: [Entrypoint(path: "main.rb")])
    XCTAssertNil(EntrypointResolver.resolve(input))
  }

  // MARK: - Entrypoint path safety (security review)

  func testRejectsUnsafeEntrypointPaths() {
    XCTAssertFalse(EntrypointResolver.isSafeEntrypointPath(""))
    XCTAssertFalse(EntrypointResolver.isSafeEntrypointPath("/etc/passwd"))
    XCTAssertFalse(EntrypointResolver.isSafeEntrypointPath("-c"))
    XCTAssertFalse(EntrypointResolver.isSafeEntrypointPath("--eval"))
    XCTAssertFalse(EntrypointResolver.isSafeEntrypointPath("../evil.py"))
    XCTAssertFalse(EntrypointResolver.isSafeEntrypointPath("src/../../evil.py"))
    XCTAssertTrue(EntrypointResolver.isSafeEntrypointPath("main.py"))
    XCTAssertTrue(EntrypointResolver.isSafeEntrypointPath("src/parser/main.py"))
  }

  func testPoisonedEntrypointClassifiesCannotDetermineAndDoesNotResolve() {
    let input = makeInput(language: .python, entrypoints: [Entrypoint(path: "../../../etc/shadow")])
    XCTAssertEqual(RunnabilityClassifier.classify(input), .cannotDetermine)
    XCTAssertNil(EntrypointResolver.resolve(input))
  }

  func testFlagPathDoesNotResolveEvenWithArguments() {
    let input = makeInput(language: .node, entrypoints: [Entrypoint(path: "-e")], arguments: ["require('child_process')"])
    XCTAssertNil(EntrypointResolver.resolve(input))
  }

  // MARK: - Sandbox profile (ADR-0016 promise)

  func testProfileDeniesNetworkAndConfinesWrites() {
    let runDir = temporaryDirectory.appendingPathComponent("run")
    let profile = RunSandbox.profile(runDirectory: runDir)
    XCTAssertTrue(profile.contains("(deny default)"))
    XCTAssertTrue(profile.contains("(deny network*)"))
    XCTAssertTrue(profile.contains("(allow file-read*)"))
    // Writes confined to the (symlink-resolved) run directory.
    XCTAssertTrue(profile.contains(runDir.resolvingSymlinksInPath().path))
  }

  func testWrapBuildsSandboxExecInvocation() {
    let profilePath = temporaryDirectory.appendingPathComponent("sandbox.sb")
    let wrapped = RunSandbox.wrap(
      interpreter: URL(fileURLWithPath: "/usr/bin/python3"),
      arguments: ["main.py"],
      profilePath: profilePath
    )
    XCTAssertEqual(wrapped.executable, RunSandbox.sandboxExecPath)
    XCTAssertEqual(wrapped.arguments, ["-f", profilePath.path, "/usr/bin/python3", "main.py"])
  }

  // MARK: - Orchestration (fake executor)

  func testNotRunnableReturnsClassificationWithoutExecuting() async throws {
    let bundle = try makeBundle(files: ["server.js": "// noop"])
    let runner = FakeProcessRunner(behavior: .init(stdout: "should not run"))
    let smokeRunner = makeSmokeRunner(processRunner: runner)
    let input = makeInput(
      gunkId: 7,
      bundlePath: bundle,
      language: .node,
      entrypoints: [Entrypoint(path: "server.js")],
      dependencies: ["express"]
    )

    let result = await smokeRunner.run(input)

    XCTAssertEqual(result.runnability, .longRunning)
    XCTAssertEqual(result.isolation, .notRun)
    XCTAssertNil(result.command)
    XCTAssertEqual(runner.invocationCount, 0, "A not-runnable-here module must never be executed.")
  }

  func testCannotDetermineWhenInterpreterMissing() async throws {
    let bundle = try makeBundle(files: ["main.py": "print('hi')"])
    let runner = FakeProcessRunner(behavior: .init())
    let smokeRunner = makeSmokeRunner(processRunner: runner, interpreterLocator: { _ in nil })
    let input = makeInput(gunkId: 1, bundlePath: bundle, language: .python, entrypoints: [Entrypoint(path: "main.py")])

    let result = await smokeRunner.run(input)

    XCTAssertEqual(result.runnability, .cannotDetermine)
    XCTAssertEqual(runner.invocationCount, 0)
    XCTAssertTrue(result.stderr.contains("python3"))
  }

  func testRunnableModuleStagesBundleAndPassesThroughOutcome() async throws {
    let bundle = try makeBundle(files: ["parser.py": "print('ok')"])
    let runner = FakeProcessRunner(behavior: .init(stdout: "parsed 1 chapter\n", exitCode: 0))
    let smokeRunner = makeSmokeRunner(processRunner: runner)
    let input = makeInput(
      gunkId: 42,
      bundlePath: bundle,
      language: .python,
      entrypoints: [Entrypoint(path: "parser.py")],
      arguments: ["--in", "demo.epub"]
    )

    let result = await smokeRunner.run(input)

    XCTAssertEqual(result.runnability, .terminalRunnable)
    XCTAssertTrue(result.passed)
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertEqual(result.stdout, "parsed 1 chapter\n")
    XCTAssertEqual(result.command, "python3 parser.py --in demo.epub")
    XCTAssertEqual(runner.invocationCount, 1)

    // The bundle was copied into a throwaway run dir, not run in place.
    let invocation = try XCTUnwrap(runner.lastInvocation)
    XCTAssertTrue(invocation.workingDirectory.path.contains("/42/"))
    XCTAssertNotEqual(invocation.workingDirectory.path, bundle.path)
    XCTAssertTrue(FileManager.default.fileExists(
      atPath: invocation.workingDirectory.appendingPathComponent("parser.py").path
    ))
    // The parent environment is never inherited — only PATH is passed.
    XCTAssertEqual(Array(invocation.environment.keys), ["PATH"])
  }

  func testFailingModuleReportsNonZeroExitAndStderr() async throws {
    let bundle = try makeBundle(files: ["main.py": "import sys; sys.exit(3)"])
    let runner = FakeProcessRunner(behavior: .init(stderr: "Traceback...\n", exitCode: 3))
    let smokeRunner = makeSmokeRunner(processRunner: runner)
    let input = makeInput(gunkId: 5, bundlePath: bundle, language: .python, entrypoints: [Entrypoint(path: "main.py")])

    let result = await smokeRunner.run(input)

    XCTAssertFalse(result.passed)
    XCTAssertEqual(result.exitCode, 3)
    XCTAssertTrue(result.stderr.contains("Traceback"))
  }

  func testTimeoutIsReportedAsAFactNotAnError() async throws {
    let bundle = try makeBundle(files: ["loop.py": "while True: pass"])
    let runner = FakeProcessRunner(behavior: .init(exitCode: nil, timedOut: true))
    let smokeRunner = makeSmokeRunner(processRunner: runner)
    let input = makeInput(gunkId: 9, bundlePath: bundle, language: .python, entrypoints: [Entrypoint(path: "loop.py")])

    let result = await smokeRunner.run(input)

    XCTAssertTrue(result.timedOut)
    XCTAssertFalse(result.passed)
    XCTAssertEqual(result.runnability, .terminalRunnable)
  }

  func testNewFilesAreReportedAsOutputArtifacts() async throws {
    let bundle = try makeBundle(files: ["gen.py": "open('out.txt','w').write('x')"])
    let runner = FakeProcessRunner(behavior: .init(stdout: "wrote\n", exitCode: 0, artifactFilename: "out.txt"))
    let smokeRunner = makeSmokeRunner(processRunner: runner)
    let input = makeInput(gunkId: 11, bundlePath: bundle, language: .python, entrypoints: [Entrypoint(path: "gen.py")])

    let result = await smokeRunner.run(input)

    XCTAssertTrue(
      result.outputArtifacts.contains { $0.lastPathComponent == "out.txt" },
      "A file written into the run dir should surface as an output artifact."
    )
  }

  func testFailsClosedWhenSandboxRequestedButUnavailable() async throws {
    let bundle = try makeBundle(files: ["main.py": "print('hi')"])
    let runner = FakeProcessRunner(behavior: .init(stdout: "hi\n"))
    let smokeRunner = makeSmokeRunner(
      processRunner: runner, useSandbox: true, allowReducedFallback: false, isSandboxAvailable: { false }
    )
    let input = makeInput(gunkId: 21, bundlePath: bundle, language: .python, entrypoints: [Entrypoint(path: "main.py")])

    let result = await smokeRunner.run(input)

    XCTAssertEqual(result.isolation, .notRun, "Must not silently run without the sandbox.")
    XCTAssertEqual(result.runnability, .terminalRunnable)
    XCTAssertFalse(result.passed)
    XCTAssertTrue(result.stderr.contains("without isolation"))
    XCTAssertEqual(runner.invocationCount, 0)
  }

  func testReducedFallbackRunsOnlyWhenExplicitlyAllowed() async throws {
    let bundle = try makeBundle(files: ["main.py": "print('hi')"])
    let runner = FakeProcessRunner(behavior: .init(stdout: "hi\n", exitCode: 0))
    let smokeRunner = makeSmokeRunner(
      processRunner: runner, useSandbox: true, allowReducedFallback: true, isSandboxAvailable: { false }
    )
    let input = makeInput(gunkId: 22, bundlePath: bundle, language: .python, entrypoints: [Entrypoint(path: "main.py")])

    let result = await smokeRunner.run(input)

    XCTAssertEqual(result.isolation, .reducedFallback)
    XCTAssertEqual(runner.invocationCount, 1)
    XCTAssertTrue(result.passed)
  }

  func testSandboxWrappingMarksIsolationWhenAvailable() async throws {
    guard RunSandbox.isAvailable() else {
      throw XCTSkip("sandbox-exec is not present on this machine.")
    }
    let bundle = try makeBundle(files: ["main.py": "print('hi')"])
    let runner = FakeProcessRunner(behavior: .init(stdout: "hi\n", exitCode: 0))
    let smokeRunner = makeSmokeRunner(processRunner: runner, useSandbox: true)
    let input = makeInput(gunkId: 3, bundlePath: bundle, language: .python, entrypoints: [Entrypoint(path: "main.py")])

    let result = await smokeRunner.run(input)

    XCTAssertEqual(result.isolation, .sandboxExec)
    let invocation = try XCTUnwrap(runner.lastInvocation)
    XCTAssertEqual(invocation.executable, RunSandbox.sandboxExecPath)
    XCTAssertTrue(invocation.arguments.contains("-f"))
    XCTAssertTrue(invocation.arguments.contains { $0.hasSuffix("sandbox.sb") })
  }

  // MARK: - Real executor (against /bin/sh, no module interpreter required)

  func testRealExecutorCapturesPassingRun() async throws {
    let outcome = await runShell("echo hello; exit 0")
    XCTAssertEqual(outcome.result.exitCode, 0)
    XCTAssertFalse(outcome.result.timedOut)
    XCTAssertTrue(outcome.stdout.contains("hello"))
  }

  func testRealExecutorCapturesFailingRun() async throws {
    let outcome = await runShell("echo boom 1>&2; exit 4")
    XCTAssertEqual(outcome.result.exitCode, 4)
    XCTAssertTrue(outcome.stderr.contains("boom"))
  }

  func testRealExecutorEnforcesTimeout() async throws {
    let start = ContinuousClock.now
    let outcome = await runShell("sleep 5", timeoutSeconds: 0.3)
    let elapsed = ContinuousClock.now - start
    XCTAssertTrue(outcome.result.timedOut)
    XCTAssertLessThan(elapsed, .seconds(3), "The timeout should have killed the process well before 5s.")
  }

  func testRealExecutorTimeoutKillsBackgroundChildren() async throws {
    // The shell backgrounds a child then sleeps; the timeout must tear down
    // the whole process group, not just the direct child.
    let start = ContinuousClock.now
    let outcome = await runShell("sleep 30 & sleep 30", timeoutSeconds: 0.3)
    let elapsed = ContinuousClock.now - start
    XCTAssertTrue(outcome.result.timedOut)
    XCTAssertLessThan(elapsed, .seconds(3))
  }

  func testRealExecutorHonorsWorkingDirectory() async throws {
    let workDir = temporaryDirectory.appendingPathComponent("work")
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    let outcome = await runShell("pwd", workingDirectory: workDir)
    XCTAssertTrue(outcome.stdout.contains(workDir.resolvingSymlinksInPath().lastPathComponent))
  }

  // MARK: - Helpers

  private func makeInput(
    gunkId: Int64 = 1,
    bundlePath: URL? = nil,
    language: ModuleLanguage,
    entrypoints: [Entrypoint],
    dependencies: [String] = [],
    arguments: [String] = []
  ) -> RunInput {
    RunInput(
      gunkId: gunkId,
      bundlePath: bundlePath ?? temporaryDirectory.appendingPathComponent("bundle"),
      language: language,
      entrypoints: entrypoints,
      dependencies: dependencies,
      arguments: arguments
    )
  }

  private func makeBundle(files: [String: String]) throws -> URL {
    let bundle = temporaryDirectory.appendingPathComponent("bundle-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    for (name, contents) in files {
      try contents.data(using: .utf8)!.write(to: bundle.appendingPathComponent(name))
    }
    return bundle
  }

  private func makeSmokeRunner(
    processRunner: SandboxedProcessRunner,
    interpreterLocator: @escaping @Sendable (String) -> URL? = { _ in URL(fileURLWithPath: "/usr/bin/true") },
    useSandbox: Bool = false,
    allowReducedFallback: Bool = false,
    isSandboxAvailable: @escaping @Sendable () -> Bool = { true }
  ) -> SmokeRunner {
    SmokeRunner(
      runsRoot: temporaryDirectory.appendingPathComponent("runs"),
      processRunner: processRunner,
      interpreterLocator: interpreterLocator,
      useSandbox: useSandbox,
      allowReducedFallback: allowReducedFallback,
      isSandboxAvailable: isSandboxAvailable,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
  }

  private struct ShellOutcome {
    let result: ProcessOutcome
    let stdout: String
    let stderr: String
  }

  /// Runs a shell script through the *real* `ProcessSandboxRunner` (no module
  /// interpreter required, so this works wherever `/bin/sh` exists).
  private func runShell(
    _ script: String,
    workingDirectory: URL? = nil,
    timeoutSeconds: Double = 5
  ) async -> ShellOutcome {
    let collector = ChunkCollector()
    let runner = ProcessSandboxRunner()
    let outcome = await runner.run(
      executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", script],
      workingDirectory: workingDirectory ?? temporaryDirectory,
      environment: ["PATH": "/usr/bin:/bin"],
      timeoutSeconds: timeoutSeconds,
      onChunk: { collector.append($0) }
    )
    return ShellOutcome(result: outcome, stdout: collector.stdout(), stderr: collector.stderr())
  }
}

/// A canned executor that records invocations and returns a fixed outcome,
/// so the orchestration is testable without spawning a real process.
private final class FakeProcessRunner: SandboxedProcessRunner, @unchecked Sendable {
  struct Behavior {
    var stdout = ""
    var stderr = ""
    var exitCode: Int32? = 0
    var timedOut = false
    var launchError: String?
    var artifactFilename: String?
  }

  private let behavior: Behavior
  private let lock = NSLock()
  private var invocations: [(executable: URL, arguments: [String], workingDirectory: URL, environment: [String: String])] = []

  init(behavior: Behavior) { self.behavior = behavior }

  var invocationCount: Int {
    lock.lock(); defer { lock.unlock() }
    return invocations.count
  }

  var lastInvocation: (executable: URL, arguments: [String], workingDirectory: URL, environment: [String: String])? {
    lock.lock(); defer { lock.unlock() }
    return invocations.last
  }

  func run(
    executable: URL,
    arguments: [String],
    workingDirectory: URL,
    environment: [String: String],
    timeoutSeconds: Double,
    onChunk: @escaping @Sendable (RunOutputChunk) -> Void
  ) async -> ProcessOutcome {
    lock.lock()
    invocations.append((executable, arguments, workingDirectory, environment))
    lock.unlock()

    if let filename = behavior.artifactFilename {
      try? "x".data(using: .utf8)?.write(to: workingDirectory.appendingPathComponent(filename))
    }
    if !behavior.stdout.isEmpty { onChunk(.stdout(behavior.stdout)) }
    if !behavior.stderr.isEmpty { onChunk(.stderr(behavior.stderr)) }
    return ProcessOutcome(exitCode: behavior.exitCode, timedOut: behavior.timedOut, launchError: behavior.launchError)
  }
}

private final class ChunkCollector: @unchecked Sendable {
  private let lock = NSLock()
  private var out = ""
  private var err = ""

  func append(_ chunk: RunOutputChunk) {
    lock.lock(); defer { lock.unlock() }
    switch chunk {
    case .stdout(let text): out += text
    case .stderr(let text): err += text
    }
  }

  func stdout() -> String { lock.lock(); defer { lock.unlock() }; return out }
  func stderr() -> String { lock.lock(); defer { lock.unlock() }; return err }
}
