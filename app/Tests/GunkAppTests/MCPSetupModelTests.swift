import XCTest
@testable import GunkApp

/// T-8.10: the shared model behind the chip, the setup sheet, and Settings'
/// per-client toggles. Every test runs against a throwaway temp home.
@MainActor
final class MCPSetupModelTests: XCTestCase {
  private var home: URL!
  private var applications: URL!
  private let binaryPath = "/Users/tester/.local/bin/gunk-mcp"

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("gunk-mcp-setup-model-\(UUID().uuidString)", isDirectory: true)
    applications = home.appendingPathComponent("Applications", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }

  private func makeModel(binary: String? = "/Users/tester/.local/bin/gunk-mcp") -> MCPSetupModel {
    MCPSetupModel(
      configurator: MCPClientConfigurator(
        home: home,
        applicationsDirectory: applications,
        fileManager: .default,
        environment: [:],
        ensureBinary: {
          guard let binary else { throw MCPConfigError.binaryNotFound }
          return URL(fileURLWithPath: binary)
        }
      )
    )
  }

  private func row(_ client: MCPClient, in model: MCPSetupModel) throws -> MCPSetupModel.ClientRow {
    try XCTUnwrap(model.rows.first { $0.client == client }, "\(client)")
  }

  private func markDetected(_ client: MCPClient) throws {
    let fileManager = FileManager.default
    switch client {
    case .cursor:
      try fileManager.createDirectory(at: home.appendingPathComponent(".cursor"), withIntermediateDirectories: true)
    case .claudeCode:
      try Data("{}".utf8).write(to: home.appendingPathComponent(".claude.json"))
    case .claudeDesktop:
      try fileManager.createDirectory(at: applications.appendingPathComponent("Claude.app"), withIntermediateDirectories: true)
    case .codex:
      try fileManager.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
    case .opencode:
      try fileManager.createDirectory(at: home.appendingPathComponent(".config/opencode"), withIntermediateDirectories: true)
    }
  }

  // MARK: Rows + display status

  func testRowsCoverAllClientsInOrder() {
    let model = makeModel()
    XCTAssertEqual(model.rows.map(\.client), MCPClient.allCases)
  }

  func testUndetectedUnwiredClientReadsNotDetected() throws {
    let model = makeModel()
    XCTAssertEqual(try row(.codex, in: model).displayStatus, .notDetected)
    XCTAssertFalse(model.isAnyClientConnected)
  }

  func testDetectedUnwiredClientReadsNotSetUp() throws {
    try markDetected(.cursor)
    let model = makeModel()
    XCTAssertEqual(try row(.cursor, in: model).displayStatus, .notSetUp)
  }

  func testWiredClientReadsConnectedEvenWithoutDetectionMarkers() throws {
    // claude.json doubles as Claude Code's detection marker, so use Codex:
    // a wired config without its app dir still means the agent is connected.
    let codexConfig = home.appendingPathComponent("codex-home/config.toml")
    try FileManager.default.createDirectory(at: codexConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("[mcp_servers.gunk]\ncommand = \"\(binaryPath)\"\n".utf8).write(to: codexConfig)

    let model = MCPSetupModel(
      configurator: MCPClientConfigurator(
        home: home,
        applicationsDirectory: applications,
        fileManager: .default,
        environment: ["CODEX_HOME": codexConfig.deletingLastPathComponent().path],
        ensureBinary: { URL(fileURLWithPath: self.binaryPath) }
      )
    )

    XCTAssertEqual(try row(.codex, in: model).displayStatus, .connected)
    XCTAssertTrue(model.isAnyClientConnected)
  }

  func testUnreadableConfigReadsProblemWithMessage() throws {
    try markDetected(.cursor)
    let cursorConfig = home.appendingPathComponent(".cursor/mcp.json")
    try Data("{ this is not json".utf8).write(to: cursorConfig)

    let model = makeModel()
    guard case .problem(let message) = try row(.cursor, in: model).displayStatus else {
      return XCTFail("expected .problem")
    }
    XCTAssertFalse(message.isEmpty)
  }

  // MARK: Connect / disconnect

  func testConnectWiresClientAndRechecksEveryStatus() throws {
    try markDetected(.cursor)
    let model = makeModel()

    model.connect(.cursor)

    XCTAssertEqual(try row(.cursor, in: model).displayStatus, .connected)
    XCTAssertNil(try row(.cursor, in: model).actionError)
    XCTAssertTrue(model.isAnyClientConnected)
    XCTAssertTrue(model.connectedSummary.contains("Cursor"))
    XCTAssertTrue(model.connectedSummary.contains(".cursor/mcp.json"))
  }

  func testDisconnectUnwiresOnlyThatClient() throws {
    let model = makeModel()
    model.connect(.cursor)
    model.connect(.opencode)

    model.disconnect(.cursor)

    XCTAssertNotEqual(try row(.cursor, in: model).displayStatus, .connected)
    XCTAssertEqual(try row(.opencode, in: model).displayStatus, .connected)
    XCTAssertTrue(model.isAnyClientConnected)
  }

  func testConnectFailureSurfacesConfiguratorErrorVerbatimAndNeverClobbers() throws {
    try markDetected(.cursor)
    let cursorConfig = home.appendingPathComponent(".cursor/mcp.json")
    let malformed = Data("{ this is not json".utf8)
    try malformed.write(to: cursorConfig)

    let model = makeModel()
    model.connect(.cursor)

    let error = try XCTUnwrap(try row(.cursor, in: model).actionError)
    // The model surfaces `MCPConfigError`'s message verbatim — same prefix,
    // same path, same fix-it suffix as the configurator's abort.
    XCTAssertTrue(error.hasPrefix("Refusing to modify \(cursorConfig.path): not valid JSON"), error)
    XCTAssertTrue(error.hasSuffix("Fix or remove the file and try again."), error)
    XCTAssertEqual(try Data(contentsOf: cursorConfig), malformed, "the malformed config must never be clobbered")
    XCTAssertFalse(model.isAnyClientConnected)
  }

  func testActionErrorClearsOnNextSuccessfulAction() throws {
    try markDetected(.cursor)
    let cursorConfig = home.appendingPathComponent(".cursor/mcp.json")
    try Data("{ this is not json".utf8).write(to: cursorConfig)

    let model = makeModel()
    model.connect(.cursor)
    XCTAssertNotNil(try row(.cursor, in: model).actionError)

    try FileManager.default.removeItem(at: cursorConfig)
    model.connect(.cursor)

    XCTAssertNil(try row(.cursor, in: model).actionError)
    XCTAssertEqual(try row(.cursor, in: model).displayStatus, .connected)
  }

  func testMissingBinarySurfacesErrorWithoutCreatingConfig() throws {
    try markDetected(.cursor)
    let model = makeModel(binary: nil)

    model.connect(.cursor)

    XCTAssertEqual(
      try row(.cursor, in: model).actionError,
      MCPConfigError.binaryNotFound.localizedDescription
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".cursor/mcp.json").path))
  }

  // MARK: Connect all

  func testConnectAllTargetsOnlyDetectedUnwiredClients() throws {
    try markDetected(.cursor)
    try markDetected(.codex)
    try markDetected(.opencode)
    let model = makeModel()
    model.connect(.opencode) // Already wired — not a target.

    XCTAssertEqual(model.connectAllTargets, [.cursor, .codex])

    model.connectAll()

    XCTAssertEqual(try row(.cursor, in: model).displayStatus, .connected)
    XCTAssertEqual(try row(.codex, in: model).displayStatus, .connected)
    // Undetected clients are untouched: one click never writes config for
    // tools that are not installed.
    XCTAssertEqual(try row(.claudeDesktop, in: model).displayStatus, .notDetected)
    XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude.json").path))
    XCTAssertTrue(model.connectAllTargets.isEmpty)
  }
}
