import Foundation
import XCTest
@testable import GunkApp

final class SettingsStatusTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testSnapshotReportsMissingHostedProviderKeyAndMCPConfig() throws {
    let snapshot = SettingsStatusSnapshot.make(
      provider: .openAI,
      model: "gpt-test",
      storePath: "/tmp/gunk/store.db",
      secretStore: InMemorySecretStore(),
      resolveEngine: { nil },
      mcpConfigURL: temporaryDirectory.appendingPathComponent("missing-mcp.json"),
      fileManager: .default
    )

    XCTAssertEqual(snapshot.configuration.state, .ready)
    XCTAssertEqual(snapshot.apiKey.state, .needsSetup)
    XCTAssertEqual(snapshot.apiKey.value, "Missing")
    XCTAssertEqual(snapshot.store.state, .ready)
    XCTAssertEqual(snapshot.engine.state, .needsSetup)
    XCTAssertEqual(snapshot.mcp.state, .needsSetup)
  }

  func testSnapshotReportsReadyStatusForConfiguredProviderEngineAndMCP() throws {
    let secretStore = InMemorySecretStore()
    try secretStore.setSecret("sk-test", for: LLMProvider.openAI.secretAccount)
    let mcpConfigURL = temporaryDirectory.appendingPathComponent("mcp.json")
    try """
    {
      "mcpServers": {
        "gunk": {
          "type": "stdio",
          "command": "/Users/example/.local/bin/gunk-mcp",
          "args": []
        }
      }
    }
    """.write(to: mcpConfigURL, atomically: true, encoding: .utf8)
    let engineURL = temporaryDirectory.appendingPathComponent("gunk-engine")

    let snapshot = SettingsStatusSnapshot.make(
      provider: .openAI,
      model: "gpt-test",
      storePath: "/tmp/gunk/store.db",
      secretStore: secretStore,
      resolveEngine: {
        ResolvedEngine(executableURL: engineURL, leadingArguments: [])
      },
      mcpConfigURL: mcpConfigURL,
      fileManager: .default
    )

    XCTAssertEqual(snapshot.apiKey.state, .ready)
    XCTAssertEqual(snapshot.apiKey.value, "Saved in Keychain")
    XCTAssertEqual(snapshot.engine.state, .ready)
    XCTAssertEqual(snapshot.engine.value, engineURL.path)
    XCTAssertEqual(snapshot.mcp.state, .ready)
    XCTAssertEqual(snapshot.mcp.value, "Configured for Cursor")
  }

  func testSnapshotExplainsLocalProviderAndInMemoryStore() {
    let snapshot = SettingsStatusSnapshot.make(
      provider: .ollama,
      model: "",
      storePath: nil,
      secretStore: InMemorySecretStore(),
      resolveEngine: { nil },
      mcpConfigURL: temporaryDirectory.appendingPathComponent("missing-mcp.json"),
      fileManager: .default
    )

    XCTAssertEqual(snapshot.configuration.state, .needsSetup)
    XCTAssertEqual(snapshot.apiKey.state, .ready)
    XCTAssertEqual(snapshot.apiKey.value, "Not required")
    XCTAssertEqual(snapshot.store.state, .needsSetup)
    XCTAssertEqual(snapshot.store.value, "In-memory")
  }
}
