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
    environment: [String: String] = [:],
    bundledBinary: URL? = nil
  ) -> MCPClientConfigurator {
    MCPClientConfigurator(
      home: home,
      applicationsDirectory: applications,
      fileManager: .default,
      environment: environment,
      bundledBinary: bundledBinary,
      ensureBinary: bundledBinary != nil ? nil : {
        guard let binary else { throw MCPConfigError.binaryNotFound }
        return URL(fileURLWithPath: binary)
      }
    )
  }

  @discardableResult
  private func makeExecutable(at url: URL, contents: String = "#!/bin/sh\necho gunk-mcp\n") throws -> URL {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: url)
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
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

  func testEnsureInstalledCopiesBundledBinaryToInstallPath() throws {
    let fileManager = FileManager.default
    let bundled = try makeExecutable(at: home.appendingPathComponent("bundle/gunk-mcp"))
    let install = home.appendingPathComponent(".local/bin/gunk-mcp")

    let resolved = try MCPBinary.ensureInstalled(
      environment: [:], bundledBinary: bundled, fileManager: fileManager, home: home
    )

    XCTAssertEqual(resolved.path, install.path)
    XCTAssertTrue(fileManager.isExecutableFile(atPath: install.path))
    XCTAssertTrue(fileManager.contentsEqual(atPath: bundled.path, andPath: install.path))
  }

  func testEnsureInstalledIsIdempotentWhenInstallMatchesBundle() throws {
    let fileManager = FileManager.default
    let bundled = try makeExecutable(at: home.appendingPathComponent("bundle/gunk-mcp"))

    let install = try MCPBinary.ensureInstalled(
      environment: [:], bundledBinary: bundled, fileManager: fileManager, home: home
    )
    let firstAttributes = try fileManager.attributesOfItem(atPath: install.path)

    let again = try MCPBinary.ensureInstalled(
      environment: [:], bundledBinary: bundled, fileManager: fileManager, home: home
    )
    let secondAttributes = try fileManager.attributesOfItem(atPath: again.path)

    XCTAssertEqual(install, again)
    XCTAssertEqual(
      firstAttributes[.systemFileNumber] as? Int,
      secondAttributes[.systemFileNumber] as? Int,
      "a byte-identical install must not be rewritten"
    )
  }

  func testEnsureInstalledRefreshesStaleInstalledBinary() throws {
    let fileManager = FileManager.default
    let bundled = try makeExecutable(at: home.appendingPathComponent("bundle/gunk-mcp"), contents: "#!/bin/sh\necho v2\n")
    let install = try makeExecutable(at: home.appendingPathComponent(".local/bin/gunk-mcp"), contents: "#!/bin/sh\necho v1\n")

    _ = try MCPBinary.ensureInstalled(
      environment: [:], bundledBinary: bundled, fileManager: fileManager, home: home
    )

    XCTAssertTrue(
      fileManager.contentsEqual(atPath: bundled.path, andPath: install.path),
      "a stale install must be refreshed from the bundle"
    )
  }

  func testEnsureInstalledPrefersExplicitOverrideWithoutInstalling() throws {
    let bundled = try makeExecutable(at: home.appendingPathComponent("bundle/gunk-mcp"))

    let resolved = try MCPBinary.ensureInstalled(
      environment: ["GUNK_MCP_BIN": "/dev/gunk-mcp"], bundledBinary: bundled, fileManager: .default, home: home
    )

    XCTAssertEqual(resolved.path, "/dev/gunk-mcp")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: home.appendingPathComponent(".local/bin/gunk-mcp").path),
      "the explicit override must not trigger an install"
    )
  }

  func testEnsureInstalledHonorsInstallPathOverride() throws {
    let bundled = try makeExecutable(at: home.appendingPathComponent("bundle/gunk-mcp"))
    let custom = home.appendingPathComponent("custom/bin/gunk-mcp")

    let resolved = try MCPBinary.ensureInstalled(
      environment: ["GUNK_MCP_INSTALL_PATH": custom.path], bundledBinary: bundled, fileManager: .default, home: home
    )

    XCTAssertEqual(resolved.path, custom.path)
    XCTAssertTrue(FileManager.default.isExecutableFile(atPath: custom.path))
  }

  func testEnsureInstalledFallsBackToExistingInstallWithoutBundle() throws {
    let install = try makeExecutable(at: home.appendingPathComponent(".local/bin/gunk-mcp"))

    let resolved = try MCPBinary.ensureInstalled(
      environment: [:], bundledBinary: nil, fileManager: .default, home: home
    )

    XCTAssertEqual(resolved.path, install.path)
  }

  func testEnsureInstalledThrowsWhenNothingIsAvailable() {
    XCTAssertThrowsError(
      try MCPBinary.ensureInstalled(environment: [:], bundledBinary: nil, fileManager: .default, home: home)
    ) { error in
      XCTAssertEqual(error as? MCPConfigError, .binaryNotFound)
    }
  }

  func testWireWithBundledBinaryInstallsAndPointsConfigAtInstallPath() throws {
    let bundled = try makeExecutable(at: home.appendingPathComponent("bundle/gunk-mcp"))
    let configurator = makeConfigurator(bundledBinary: bundled)
    let install = home.appendingPathComponent(".local/bin/gunk-mcp")

    try configurator.wire(.cursor)

    XCTAssertTrue(FileManager.default.isExecutableFile(atPath: install.path))
    XCTAssertEqual(configurator.status(for: .cursor), .ready(command: install.path))
    let entry = try XCTUnwrap(try gunkEntry(in: configurator.configURL(for: .cursor), for: .cursor))
    XCTAssertEqual(entry["command"] as? String, install.path)
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

  // MARK: - Status semantics (the rule every MCP surface renders from)

  func testCursorStatusDistinguishesEveryState() throws {
    let configurator = makeConfigurator()
    let url = configurator.configURL(for: .cursor)

    XCTAssertEqual(configurator.status(for: .cursor), .configMissing)

    try seed(#"{"mcpServers": {}}"#, at: url)
    XCTAssertEqual(configurator.status(for: .cursor), .entryMissing)

    try seed(#"{"mcpServers": {"gunk": {"command": "/somewhere/else"}}}"#, at: url)
    XCTAssertEqual(configurator.status(for: .cursor), .commandMismatch)

    try configurator.wire(.cursor)
    XCTAssertEqual(configurator.status(for: .cursor), .ready(command: binaryPath))

    try configurator.unwire(.cursor)
    XCTAssertEqual(configurator.status(for: .cursor), .entryMissing)

    try seed("{ this is not json", at: url)
    guard case .unreadable(let message) = configurator.status(for: .cursor) else {
      return XCTFail("expected .unreadable")
    }
    XCTAssertFalse(message.isEmpty)
  }
}
