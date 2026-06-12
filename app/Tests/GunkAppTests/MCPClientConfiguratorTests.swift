import XCTest
@testable import GunkApp

/// T-8.9: every test runs against a throwaway temp "home" — nothing here may
/// touch the real home directory.
final class MCPClientConfiguratorTests: XCTestCase {
  private var home: URL!
  private var applications: URL!
  private let binaryPath = "/Users/tester/.local/bin/gunk-mcp"

  override func setUpWithError() throws {
    home = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("gunk-mcp-configurator-\(UUID().uuidString)", isDirectory: true)
    applications = home.appendingPathComponent("Applications", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: home)
  }

  private func makeConfigurator(
    binary: String? = "/Users/tester/.local/bin/gunk-mcp",
    environment: [String: String] = [:]
  ) -> MCPClientConfigurator {
    MCPClientConfigurator(
      home: home,
      applicationsDirectory: applications,
      fileManager: .default,
      environment: environment,
      resolveBinary: { binary.map { URL(fileURLWithPath: $0) } }
    )
  }

  private func seed(_ text: String, at url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data(text.utf8).write(to: url)
  }

  private func readText(_ url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
  }

  private func readJSON(_ url: URL) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    return try XCTUnwrap(object as? [String: Any])
  }

  /// An existing config with another MCP server plus unrelated top-level
  /// keys, in each client's native shape.
  private func unrelatedSeed(for client: MCPClient) -> String {
    switch client {
    case .cursor:
      return """
      {"mcpServers": {"other": {"type": "stdio", "command": "/usr/local/bin/other-mcp", "args": ["--flag"]}}, "theme": "dark"}
      """
    case .claudeCode:
      return """
      {"mcpServers": {"other": {"type": "stdio", "command": "/usr/local/bin/other-mcp"}}, "numStartups": 42, "projects": {"/Users/tester/proj": {"allowedTools": ["Bash"]}}}
      """
    case .claudeDesktop:
      return """
      {"mcpServers": {"other": {"command": "/usr/local/bin/other-mcp", "args": []}}, "globalShortcut": "Cmd+Space"}
      """
    case .opencode:
      return """
      {"$schema": "https://opencode.ai/config.json", "mcp": {"other": {"type": "local", "command": ["/usr/local/bin/other-mcp", "--flag"], "enabled": true}}, "theme": "system"}
      """
    case .codex:
      return """
      # Codex config
      model = "gpt-5-codex"

      [mcp_servers.other]
      command = "/usr/local/bin/other-mcp"
      args = ["--flag"]
      """ + "\n"
    }
  }

  private func expectedEntry(for client: MCPClient) -> NSDictionary {
    switch client {
    case .cursor, .claudeCode:
      return ["type": "stdio", "command": binaryPath, "args": [String]()]
    case .claudeDesktop:
      return ["command": binaryPath, "args": [String]()]
    case .opencode:
      return ["type": "local", "command": [binaryPath], "enabled": true]
    case .codex:
      return [:]
    }
  }

  private func gunkEntry(in url: URL, for client: MCPClient) throws -> [String: Any]? {
    let root = try readJSON(url)
    let servers = root[client.jsonContainerKey] as? [String: Any]
    return servers?["gunk"] as? [String: Any]
  }

  // MARK: - Wire into empty

  func testWireIntoEmptyWritesEntryAndReportsReady() throws {
    let configurator = makeConfigurator()

    for client in MCPClient.allCases {
      XCTAssertEqual(configurator.status(for: client), .configMissing, "\(client)")
      try configurator.wire(client)
      XCTAssertEqual(configurator.status(for: client), .ready(command: binaryPath), "\(client)")

      let url = configurator.configURL(for: client)
      switch client.configFormat {
      case .json:
        let entry = try XCTUnwrap(try gunkEntry(in: url, for: client), "\(client)")
        XCTAssertEqual(entry as NSDictionary, expectedEntry(for: client), "\(client)")
      case .toml:
        XCTAssertEqual(
          try readText(url),
          "[mcp_servers.gunk]\ncommand = \"\(binaryPath)\"\n",
          "\(client)"
        )
      }
    }
  }

  // MARK: - Wire into existing config

  func testWirePreservesUnrelatedEntries() throws {
    let configurator = makeConfigurator()

    for client in MCPClient.allCases {
      let url = configurator.configURL(for: client)
      try seed(unrelatedSeed(for: client), at: url)

      try configurator.wire(client)
      XCTAssertEqual(configurator.status(for: client), .ready(command: binaryPath), "\(client)")

      switch client.configFormat {
      case .json:
        let root = try readJSON(url)
        let servers = try XCTUnwrap(root[client.jsonContainerKey] as? [String: Any], "\(client)")
        XCTAssertNotNil(servers["other"], "\(client): the other MCP server must survive")

        let original = try XCTUnwrap(
          try JSONSerialization.jsonObject(with: Data(unrelatedSeed(for: client).utf8)) as? [String: Any]
        )
        let originalServers = try XCTUnwrap(original[client.jsonContainerKey] as? [String: Any])
        XCTAssertEqual(
          try XCTUnwrap(servers["other"] as? [String: Any]) as NSDictionary,
          try XCTUnwrap(originalServers["other"] as? [String: Any]) as NSDictionary,
          "\(client): the other server's entry must be value-identical"
        )
        for (key, value) in original where key != client.jsonContainerKey {
          XCTAssertEqual(
            root[key] as? NSObject, value as? NSObject,
            "\(client): unrelated top-level key `\(key)` must survive"
          )
        }
      case .toml:
        let text = try readText(url)
        XCTAssertTrue(text.hasPrefix(unrelatedSeed(for: client)), "\(client): every pre-existing line must be byte-identical")
        XCTAssertTrue(text.hasSuffix("[mcp_servers.gunk]\ncommand = \"\(binaryPath)\"\n"), "\(client)")
      }
    }
  }

  func testWireReplacesStaleGunkEntry() throws {
    let configurator = makeConfigurator()

    let cursorURL = configurator.configURL(for: .cursor)
    try seed(#"{"mcpServers": {"gunk": {"command": "/somewhere/else"}}}"#, at: cursorURL)
    XCTAssertEqual(configurator.status(for: .cursor), .commandMismatch)
    try configurator.wire(.cursor)
    XCTAssertEqual(configurator.status(for: .cursor), .ready(command: binaryPath))

    let codexURL = configurator.configURL(for: .codex)
    try seed("[mcp_servers.gunk]\ncommand = \"/somewhere/else\"\nargs = [\"--old\"]\n", at: codexURL)
    XCTAssertEqual(configurator.status(for: .codex), .commandMismatch)
    try configurator.wire(.codex)
    XCTAssertEqual(configurator.status(for: .codex), .ready(command: binaryPath))
    XCTAssertEqual(try readText(codexURL), "[mcp_servers.gunk]\ncommand = \"\(binaryPath)\"\n")
  }

  // MARK: - Idempotency

  func testDoubleWireIsByteStable() throws {
    let configurator = makeConfigurator()

    for client in MCPClient.allCases {
      let url = configurator.configURL(for: client)
      try seed(unrelatedSeed(for: client), at: url)

      try configurator.wire(client)
      let first = try Data(contentsOf: url)
      try configurator.wire(client)
      let second = try Data(contentsOf: url)
      XCTAssertEqual(first, second, "\(client): wiring twice must be byte-stable")
    }
  }

  func testDoubleWireFromEmptyIsByteStable() throws {
    let configurator = makeConfigurator()

    for client in MCPClient.allCases {
      let url = configurator.configURL(for: client)
      try configurator.wire(client)
      let first = try Data(contentsOf: url)
      try configurator.wire(client)
      let second = try Data(contentsOf: url)
      XCTAssertEqual(first, second, "\(client): wiring twice must be byte-stable")
    }
  }

  // MARK: - Malformed config

  func testWireAbortsOnMalformedConfigWithoutClobbering() throws {
    let configurator = makeConfigurator()

    let malformedSeeds: [MCPClient: [String]] = [
      .cursor: ["{ this is not json", "[1, 2, 3]", #"{"mcpServers": "not an object"}"#],
      .claudeCode: ["{ this is not json"],
      .claudeDesktop: ["{ this is not json"],
      .opencode: ["{ this is not json", #"{"mcp": 7}"#],
      .codex: [
        "[mcp_servers.gunk]\ncommand = \"a\"\n\n[mcp_servers.gunk]\ncommand = \"b\"\n",
        "mcp_servers.gunk = { command = \"/inline/form\" }\n",
        "[mcp_servers]\n",
      ],
    ]

    for (client, seeds) in malformedSeeds {
      for text in seeds {
        let url = configurator.configURL(for: client)
        try? FileManager.default.removeItem(at: url)
        try seed(text, at: url)
        let before = try Data(contentsOf: url)

        XCTAssertThrowsError(try configurator.wire(client), "\(client): \(text)") { error in
          guard case MCPConfigError.malformedConfig = error else {
            return XCTFail("\(client): expected malformedConfig, got \(error)")
          }
        }
        XCTAssertEqual(try Data(contentsOf: url), before, "\(client): malformed config must never be clobbered")
      }
    }
  }

  // MARK: - Unwire

  func testUnwireRemovesOnlyGunkEntry() throws {
    let configurator = makeConfigurator()

    for client in MCPClient.allCases {
      let url = configurator.configURL(for: client)
      try seed(unrelatedSeed(for: client), at: url)
      try configurator.wire(client)

      try configurator.unwire(client)
      XCTAssertEqual(configurator.status(for: client), .entryMissing, "\(client)")

      switch client.configFormat {
      case .json:
        XCTAssertNil(try gunkEntry(in: url, for: client), "\(client)")
        let root = try readJSON(url)
        let servers = try XCTUnwrap(root[client.jsonContainerKey] as? [String: Any], "\(client)")
        XCTAssertNotNil(servers["other"], "\(client): the other MCP server must survive unwire")
      case .toml:
        XCTAssertEqual(
          try readText(url), unrelatedSeed(for: client),
          "\(client): wire→unwire must restore the original bytes"
        )
      }
    }
  }

  func testUnwireWhenAbsentLeavesFileByteUntouched() throws {
    let configurator = makeConfigurator()

    for client in MCPClient.allCases {
      let url = configurator.configURL(for: client)
      try seed(unrelatedSeed(for: client), at: url)
      let before = try Data(contentsOf: url)

      try configurator.unwire(client)
      XCTAssertEqual(try Data(contentsOf: url), before, "\(client): unwire with no gunk entry must not rewrite the file")
    }
  }

  func testUnwireWhenConfigMissingIsANoOp() throws {
    let configurator = makeConfigurator()

    for client in MCPClient.allCases {
      let url = configurator.configURL(for: client)
      XCTAssertNoThrow(try configurator.unwire(client), "\(client)")
      XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "\(client)")
    }
  }

  // MARK: - Binary resolution

  func testWireThrowsWhenBinaryCannotBeResolved() throws {
    let configurator = makeConfigurator(binary: nil)

    for client in MCPClient.allCases {
      XCTAssertThrowsError(try configurator.wire(client), "\(client)") { error in
        XCTAssertEqual(error as? MCPConfigError, .binaryNotFound, "\(client)")
      }
      XCTAssertFalse(
        FileManager.default.fileExists(atPath: configurator.configURL(for: client).path),
        "\(client): a failed wire must not create config"
      )
    }
  }

  func testMCPBinaryResolutionOrder() throws {
    let fileManager = FileManager.default

    // 1. Explicit env override wins without an existence check (dev/CI).
    XCTAssertEqual(
      MCPBinary.resolve(environment: ["GUNK_MCP_BIN": "/dev/gunk-mcp"], fileManager: fileManager, home: home)?.path,
      "/dev/gunk-mcp"
    )

    // 2. Installer override path, only when executable.
    let installed = home.appendingPathComponent("custom/gunk-mcp")
    try fileManager.createDirectory(at: installed.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: installed)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installed.path)
    XCTAssertEqual(
      MCPBinary.resolve(environment: ["GUNK_MCP_INSTALL_PATH": installed.path], fileManager: fileManager, home: home)?.path,
      installed.path
    )

    // 3. The documented default install location.
    let defaultInstall = home.appendingPathComponent(".local/bin/gunk-mcp")
    try fileManager.createDirectory(at: defaultInstall.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: defaultInstall)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: defaultInstall.path)
    XCTAssertEqual(
      MCPBinary.resolve(environment: [:], fileManager: fileManager, home: home)?.path,
      defaultInstall.path
    )

    // 4. Nothing resolvable.
    try fileManager.removeItem(at: defaultInstall)
    XCTAssertNil(MCPBinary.resolve(environment: [:], fileManager: fileManager, home: home))
  }

  // MARK: - Detection

  func testDetectInstalledFindsConfigDirsAndAppBundles() throws {
    let configurator = makeConfigurator()
    let fileManager = FileManager.default
    XCTAssertEqual(configurator.detectInstalled(), [])

    try fileManager.createDirectory(at: home.appendingPathComponent(".cursor"), withIntermediateDirectories: true)
    XCTAssertEqual(configurator.detectInstalled(), [.cursor])

    try Data("{}".utf8).write(to: home.appendingPathComponent(".claude.json"))
    try fileManager.createDirectory(at: applications.appendingPathComponent("Claude.app"), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: home.appendingPathComponent(".config/opencode"), withIntermediateDirectories: true)

    XCTAssertEqual(configurator.detectInstalled(), MCPClient.allCases)
  }

  // MARK: - Config location overrides

  func testCursorConfigHonorsGunkMCPConfigOverride() throws {
    let override = home.appendingPathComponent("override/mcp.json")
    let configurator = makeConfigurator(environment: ["GUNK_MCP_CONFIG": override.path])

    XCTAssertEqual(configurator.configURL(for: .cursor).path, override.path)
    try configurator.wire(.cursor)
    XCTAssertTrue(FileManager.default.fileExists(atPath: override.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".cursor/mcp.json").path))
  }

  func testCodexConfigHonorsCodexHome() throws {
    let codexHome = home.appendingPathComponent("codex-home")
    let configurator = makeConfigurator(environment: ["CODEX_HOME": codexHome.path])

    XCTAssertEqual(configurator.configURL(for: .codex).path, codexHome.appendingPathComponent("config.toml").path)
  }

  // MARK: - Cursor provider parity (the shell's MCP chip + Settings read this)

  func testCursorProviderKeepsLegacyStatusItemsByteIdentical() throws {
    let fileManager = FileManager.default
    let url = home.appendingPathComponent(".cursor/mcp.json")

    let missing = MCPStatusProvider.status(configURL: url, fileManager: fileManager)
    XCTAssertEqual(missing.title, "MCP config")
    XCTAssertEqual(missing.value, "Not configured")
    XCTAssertEqual(missing.message, "Cursor config was not found at \(url.path). Follow docs/integration/cursor.md to add gunk.")
    XCTAssertEqual(missing.state, .needsSetup)

    try seed(#"{"mcpServers": {}}"#, at: url)
    let entryMissing = MCPStatusProvider.status(configURL: url, fileManager: fileManager)
    XCTAssertEqual(entryMissing.value, "Missing gunk server")
    XCTAssertEqual(entryMissing.message, "Add a `gunk` server entry under `mcpServers` in \(url.path).")
    XCTAssertEqual(entryMissing.state, .needsSetup)

    try seed(#"{"mcpServers": {"gunk": {"command": "/somewhere/else"}}}"#, at: url)
    let mismatch = MCPStatusProvider.status(configURL: url, fileManager: fileManager)
    XCTAssertEqual(mismatch.value, "Check command")
    XCTAssertEqual(mismatch.message, "The `gunk` MCP server exists, but its command does not look like gunk-mcp.")
    XCTAssertEqual(mismatch.state, .needsSetup)

    try seed(#"{"mcpServers": {"gunk": {"type": "stdio", "command": "/Users/tester/.local/bin/gunk-mcp", "args": []}}}"#, at: url)
    let ready = MCPStatusProvider.status(configURL: url, fileManager: fileManager)
    XCTAssertEqual(ready.value, "Configured for Cursor")
    XCTAssertEqual(ready.message, "Cursor can spawn gunk through /Users/tester/.local/bin/gunk-mcp.")
    XCTAssertEqual(ready.state, .ready)

    try seed("{ this is not json", at: url)
    let unreadable = MCPStatusProvider.status(configURL: url, fileManager: fileManager)
    XCTAssertEqual(unreadable.value, "Unreadable")
    XCTAssertEqual(unreadable.state, .unavailable)
    XCTAssertFalse(unreadable.message.isEmpty)
  }

  func testProviderStatusMatchesConfiguratorWireForCursor() throws {
    let configurator = makeConfigurator()
    let url = configurator.configURL(for: .cursor)

    try configurator.wire(.cursor)
    let item = MCPStatusProvider.status(configURL: url, fileManager: .default)
    XCTAssertEqual(item.state, .ready)
    XCTAssertEqual(item.value, "Configured for Cursor")

    try configurator.unwire(.cursor)
    let after = MCPStatusProvider.status(configURL: url, fileManager: .default)
    XCTAssertEqual(after.state, .needsSetup)
    XCTAssertEqual(after.value, "Missing gunk server")
  }
}
