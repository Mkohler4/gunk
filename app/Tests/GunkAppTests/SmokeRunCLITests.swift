import XCTest
@testable import GunkApp

/// Exercises the headless `gunk run` verb (ADR-0017) end to end through its
/// pure `execute(requestJSON:runner:)` entry point — decode → build `RunInput`
/// → run buffered → encode — with a canned executor, so no real subprocess or
/// sandbox is required. The verb is the path the MCP `run_gunk` tool uses to
/// reach the one app-side sandbox runner.
final class SmokeRunCLITests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testEncodesPassingReceipt() async throws {
    let bundle = try makeBundle(files: ["parser.py": "print('ok')"])
    let runner = makeRunner(.init(stdout: "parsed 1 chapter\n", exitCode: 0))
    let request = """
    { "gunkId": 42, "bundlePath": "\(bundle.path)", "language": "python",
      "entrypoints": [{ "path": "parser.py", "symbol": null }],
      "dependencies": [], "arguments": ["--in", "demo.epub"] }
    """

    let output = await SmokeRunCLI.execute(requestJSON: request, runner: runner)

    XCTAssertEqual(output.exitCode, 0)
    let receipt = try decode(output.json)
    XCTAssertEqual(receipt["gunkId"] as? Int, 42)
    XCTAssertEqual(receipt["passed"] as? Bool, true)
    XCTAssertEqual(receipt["runnability"] as? String, "terminal-runnable")
    XCTAssertEqual(receipt["exitCode"] as? Int, 0)
    XCTAssertEqual(receipt["command"] as? String, "python3 parser.py --in demo.epub")
    XCTAssertEqual(receipt["stdout"] as? String, "parsed 1 chapter\n")
    // Agent origin is forced regardless of the request.
    XCTAssertEqual(receipt["origin"] as? String, "agent")
  }

  func testEncodesFailingReceipt() async throws {
    let bundle = try makeBundle(files: ["main.py": "boom"])
    let runner = makeRunner(.init(stderr: "Traceback\n", exitCode: 3))
    let request = requestJSON(gunkId: 5, bundle: bundle, language: "python", entry: "main.py")

    let output = await SmokeRunCLI.execute(requestJSON: request, runner: runner)

    let receipt = try decode(output.json)
    XCTAssertEqual(receipt["passed"] as? Bool, false)
    XCTAssertEqual(receipt["exitCode"] as? Int, 3)
    XCTAssertEqual(receipt["stderr"] as? String, "Traceback\n")
  }

  func testNotRunnableReturnsTypedClassificationNotAnError() async throws {
    let bundle = try makeBundle(files: ["server.js": "// noop"])
    let runner = makeRunner(.init(stdout: "should not run"))
    let request = """
    { "gunkId": 9, "bundlePath": "\(bundle.path)", "language": "node",
      "entrypoints": [{ "path": "server.js", "symbol": null }],
      "dependencies": ["express"] }
    """

    let output = await SmokeRunCLI.execute(requestJSON: request, runner: runner)

    XCTAssertEqual(output.exitCode, 0, "A not-runnable-here module is an honest receipt, not an error.")
    let receipt = try decode(output.json)
    XCTAssertEqual(receipt["runnability"] as? String, "long-running")
    XCTAssertEqual(receipt["isolation"] as? String, "not-run")
    XCTAssertEqual(receipt["passed"] as? Bool, false)
  }

  func testMalformedRequestIsRejectedNotRun() async throws {
    let runner = makeRunner(.init(stdout: "nope"))
    let output = await SmokeRunCLI.execute(requestJSON: "{ not json", runner: runner)

    XCTAssertEqual(output.exitCode, 1)
    let receipt = try decode(output.json)
    XCTAssertNotNil(receipt["error"])
  }

  func testEmptyRequestIsRejected() async throws {
    let runner = makeRunner(.init())
    let output = await SmokeRunCLI.execute(requestJSON: "", runner: runner)
    XCTAssertEqual(output.exitCode, 1)
    XCTAssertNotNil(try decode(output.json)["error"])
  }

  func testTimeoutIsClampedAndDefaulted() {
    XCTAssertEqual(SmokeRunCLI.clampTimeout(nil), SmokeRunCLI.defaultTimeoutSeconds)
    XCTAssertEqual(SmokeRunCLI.clampTimeout(0), SmokeRunCLI.defaultTimeoutSeconds)
    XCTAssertEqual(SmokeRunCLI.clampTimeout(-5), SmokeRunCLI.defaultTimeoutSeconds)
    XCTAssertEqual(SmokeRunCLI.clampTimeout(10), 10)
    XCTAssertEqual(SmokeRunCLI.clampTimeout(99_999), SmokeRunCLI.maxTimeoutSeconds)
  }

  // MARK: - Helpers

  private func makeRunner(_ behavior: CannedRunner.Behavior) -> SmokeRunner {
    SmokeRunner(
      runsRoot: temporaryDirectory.appendingPathComponent("runs"),
      processRunner: CannedRunner(behavior: behavior),
      interpreterLocator: { _ in URL(fileURLWithPath: "/usr/bin/true") },
      useSandbox: false,
      allowReducedFallback: false,
      isSandboxAvailable: { true },
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
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

  private func requestJSON(gunkId: Int, bundle: URL, language: String, entry: String) -> String {
    """
    { "gunkId": \(gunkId), "bundlePath": "\(bundle.path)", "language": "\(language)",
      "entrypoints": [{ "path": "\(entry)", "symbol": null }], "dependencies": [] }
    """
  }

  private func decode(_ json: String) throws -> [String: Any] {
    let data = try XCTUnwrap(json.data(using: .utf8))
    let object = try JSONSerialization.jsonObject(with: data)
    return try XCTUnwrap(object as? [String: Any])
  }
}

/// A canned executor for the CLI tests (the `SmokeRunnerTests` fake is private
/// to that file).
private final class CannedRunner: SandboxedProcessRunner, @unchecked Sendable {
  struct Behavior {
    var stdout = ""
    var stderr = ""
    var exitCode: Int32? = 0
    var timedOut = false
  }

  private let behavior: Behavior
  init(behavior: Behavior) { self.behavior = behavior }

  func run(
    executable: URL,
    arguments: [String],
    workingDirectory: URL,
    environment: [String: String],
    timeoutSeconds: Double,
    onChunk: @escaping @Sendable (RunOutputChunk) -> Void
  ) async -> ProcessOutcome {
    if !behavior.stdout.isEmpty { onChunk(.stdout(behavior.stdout)) }
    if !behavior.stderr.isEmpty { onChunk(.stderr(behavior.stderr)) }
    return ProcessOutcome(exitCode: behavior.exitCode, timedOut: behavior.timedOut, launchError: nil)
  }
}
