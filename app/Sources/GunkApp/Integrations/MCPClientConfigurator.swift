import Foundation

/// The AI clients gunk knows how to wire `gunk-mcp` into (T-8.9).
///
/// Per-client config shapes verified against each tool's official docs
/// (2026-06-12):
/// - Cursor: `~/.cursor/mcp.json`, `mcpServers.gunk` with `type: stdio` +
///   `command` + `args` (docs/integration/cursor.md; docs.cursor.com).
/// - Claude Code: `~/.claude.json` (user scope), top-level `mcpServers.gunk`,
///   same stdio shape. The CLI (`claude mcp add --scope user`) writes the
///   same file (code.claude.com/docs/en/mcp).
/// - Claude Desktop: `~/Library/Application Support/Claude/
///   claude_desktop_config.json`, `mcpServers.gunk` with `command` + `args`
///   (no `type` key in the canonical examples;
///   modelcontextprotocol.io/quickstart/user).
/// - Codex: `~/.codex/config.toml` (or `$CODEX_HOME/config.toml`), a
///   `[mcp_servers.gunk]` table with `command` — stdio is the default
///   transport, no type key (developers.openai.com/codex/mcp).
/// - OpenCode: `~/.config/opencode/opencode.json`, `mcp.gunk` with
///   `type: "local"`, `command` as an array (binary + args together), and
///   `enabled: true` (opencode.ai/docs/mcp-servers).
enum MCPClient: String, CaseIterable, Identifiable, Sendable {
  case cursor
  case claudeCode
  case claudeDesktop
  case codex
  case opencode

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .cursor: return "Cursor"
    case .claudeCode: return "Claude Code"
    case .claudeDesktop: return "Claude Desktop"
    case .codex: return "Codex"
    case .opencode: return "OpenCode"
    }
  }

  enum ConfigFormat: Sendable {
    case json
    case toml
  }

  var configFormat: ConfigFormat {
    self == .codex ? .toml : .json
  }

  /// The top-level JSON key holding the server map. OpenCode names it `mcp`;
  /// the rest use `mcpServers`. Codex is TOML and does not use this.
  var jsonContainerKey: String {
    self == .opencode ? "mcp" : "mcpServers"
  }

  /// The entry written under the server name. OpenCode merges binary + args
  /// into one `command` array; the JSON clients split `command`/`args`;
  /// Claude Desktop's canonical examples omit `type` (it only spawns stdio).
  func jsonEntry(binaryPath: String) -> [String: Any] {
    switch self {
    case .cursor, .claudeCode:
      return ["type": "stdio", "command": binaryPath, "args": [String]()]
    case .claudeDesktop:
      return ["command": binaryPath, "args": [String]()]
    case .opencode:
      return ["type": "local", "command": [binaryPath], "enabled": true]
    case .codex:
      return [:] // TOML client; never consulted.
    }
  }
}

/// What the configurator found in a client's config. The shell maps this to
/// user-facing status (`MCPSetupModel.DisplayStatus`).
enum MCPClientStatus: Equatable, Sendable {
  /// A `gunk` entry exists and its command looks like gunk-mcp.
  case ready(command: String)
  /// The config file does not exist.
  case configMissing
  /// The file parses, but there is no `gunk` server entry (this also covers
  /// a root that is not an object — same answer the old provider gave).
  case entryMissing
  /// A `gunk` entry exists, but its command does not look like gunk-mcp.
  case commandMismatch
  /// The file exists but could not be read or parsed.
  case unreadable(String)
}

enum MCPConfigError: Error, LocalizedError, Equatable {
  case binaryNotFound
  case installFailed(path: String, detail: String)
  case malformedConfig(path: String, detail: String)
  case unreadableConfig(path: String, detail: String)

  var errorDescription: String? {
    switch self {
    case .binaryNotFound:
      return "Could not locate the gunk-mcp binary. Install it with `bun run install:bin` from mcp/ or set GUNK_MCP_BIN."
    case .installFailed(let path, let detail):
      return "Could not install gunk-mcp to \(path): \(detail)"
    case .malformedConfig(let path, let detail):
      return "Refusing to modify \(path): \(detail). Fix or remove the file and try again."
    case .unreadableConfig(let path, let detail):
      return "Could not read \(path): \(detail)"
    }
  }
}

/// Locates the `gunk-mcp` binary the config entries should spawn.
///
/// Packaged builds bundle `gunk-mcp` alongside `gunk-engine` (app/Makefile),
/// but client configs must never point inside the .app bundle — the path
/// breaks the moment the app moves or updates. So `wire` goes through
/// `ensureInstalled`, which copies the bundled binary to the documented
/// install path (`~/.local/bin/gunk-mcp`, the `bun run install:bin` target;
/// `GUNK_MCP_INSTALL_PATH` overrides the destination) and points configs at
/// that stable path. The copy is idempotent: byte-identical installs are
/// left untouched, stale ones are refreshed.
enum MCPBinary {
  static func defaultBundledBinary(bundle: Bundle = .main) -> URL? {
    bundle.url(forResource: "gunk-mcp", withExtension: nil)
  }

  /// The stable path `wire` installs to and writes into client configs.
  static func installURL(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> URL {
    if let override = environment["GUNK_MCP_INSTALL_PATH"], !override.isEmpty {
      return URL(fileURLWithPath: override)
    }
    return home.appendingPathComponent(".local/bin/gunk-mcp")
  }

  /// Wire-time resolution:
  /// 1. `GUNK_MCP_BIN` env var — explicit binary (dev/CI), no install side
  ///    effect.
  /// 2. Bundled `gunk-mcp` — installed/refreshed at the install path, which
  ///    is what gets returned (and written into configs).
  /// 3. An existing install (dev `bun run install:bin`) with no bundle —
  ///    used as-is.
  static func ensureInstalled(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundledBinary: URL? = MCPBinary.defaultBundledBinary(),
    fileManager: FileManager = .default,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
  ) throws -> URL {
    if let explicit = environment["GUNK_MCP_BIN"], !explicit.isEmpty {
      return URL(fileURLWithPath: explicit)
    }

    let destination = installURL(environment: environment, home: home)

    if let bundled = bundledBinary, fileManager.isExecutableFile(atPath: bundled.path) {
      try installIfNeeded(from: bundled, to: destination, fileManager: fileManager)
      return destination
    }

    if fileManager.isExecutableFile(atPath: destination.path) {
      return destination
    }

    throw MCPConfigError.binaryNotFound
  }

  private static func installIfNeeded(from source: URL, to destination: URL, fileManager: FileManager) throws {
    if fileManager.fileExists(atPath: destination.path),
       fileManager.contentsEqual(atPath: source.path, andPath: destination.path) {
      return
    }

    do {
      try fileManager.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      try fileManager.copyItem(at: source, to: destination)
      try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
    } catch {
      throw MCPConfigError.installFailed(path: destination.path, detail: error.localizedDescription)
    }
  }
}

/// Idempotent detect/read/write support for wiring gunk-mcp into each AI
/// client's config (T-8.9). Pure logic, no UI — T-8.10 builds on this.
///
/// Everything is injected (home, applications dir, FileManager, environment,
/// binary resolver) so tests run entirely against temp directories.
///
/// Write guarantees:
/// - `wire` twice produces byte-stable config.
/// - Unrelated entries are preserved (JSON files are re-serialized with
///   sorted keys, so unrelated *data* survives exactly while formatting is
///   normalized; Codex TOML is edited line-targeted, so unrelated lines are
///   preserved byte-for-byte).
/// - Malformed existing config aborts with `MCPConfigError` and never
///   clobbers.
/// - `unwire` removes only the gunk entry; when the entry is absent it does
///   not rewrite the file at all.
struct MCPClientConfigurator {
  static let serverName = "gunk"
  /// The status rule (since T-7.6): the entry is "ours" when its command
  /// mentions this binary name.
  static let binaryMarker = "gunk-mcp"

  let home: URL
  let applicationsDirectory: URL
  let fileManager: FileManager
  let environment: [String: String]
  let ensureBinary: () throws -> URL

  init(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundledBinary: URL? = MCPBinary.defaultBundledBinary(),
    ensureBinary: (() throws -> URL)? = nil
  ) {
    self.home = home
    self.applicationsDirectory = applicationsDirectory
    self.fileManager = fileManager
    self.environment = environment
    self.ensureBinary = ensureBinary ?? {
      try MCPBinary.ensureInstalled(
        environment: environment,
        bundledBinary: bundledBinary,
        fileManager: fileManager,
        home: home
      )
    }
  }

  // MARK: - Locations

  /// Honors the dev-only `GUNK_MCP_CONFIG` Cursor override (established in
  /// T-7.6 so scripted runs never touch the real `~/.cursor/mcp.json`), and
  /// Codex's documented `CODEX_HOME`.
  func configURL(for client: MCPClient) -> URL {
    switch client {
    case .cursor:
      if let override = environment["GUNK_MCP_CONFIG"], !override.isEmpty {
        return URL(fileURLWithPath: override)
      }
      return home.appendingPathComponent(".cursor/mcp.json")
    case .claudeCode:
      return home.appendingPathComponent(".claude.json")
    case .claudeDesktop:
      return home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
    case .codex:
      if let codexHome = environment["CODEX_HOME"], !codexHome.isEmpty {
        return URL(fileURLWithPath: codexHome).appendingPathComponent("config.toml")
      }
      return home.appendingPathComponent(".codex/config.toml")
    case .opencode:
      return home.appendingPathComponent(".config/opencode/opencode.json")
    }
  }

  /// Markers whose presence means "this client is installed". Config-dir or
  /// app-bundle presence; deliberately cheap (no PATH probing — a dir left
  /// behind by an uninstalled tool is an acceptable false positive for the
  /// setup sheet, which shows per-client status anyway).
  func detectionPaths(for client: MCPClient) -> [URL] {
    switch client {
    case .cursor:
      return [
        home.appendingPathComponent(".cursor"),
        applicationsDirectory.appendingPathComponent("Cursor.app"),
      ]
    case .claudeCode:
      return [
        home.appendingPathComponent(".claude.json"),
        home.appendingPathComponent(".claude"),
      ]
    case .claudeDesktop:
      return [
        applicationsDirectory.appendingPathComponent("Claude.app"),
        home.appendingPathComponent("Library/Application Support/Claude"),
      ]
    case .codex:
      return [configURL(for: .codex).deletingLastPathComponent()]
    case .opencode:
      return [
        home.appendingPathComponent(".config/opencode"),
        home.appendingPathComponent(".local/share/opencode"),
      ]
    }
  }

  func detectInstalled() -> [MCPClient] {
    MCPClient.allCases.filter { client in
      detectionPaths(for: client).contains { fileManager.fileExists(atPath: $0.path) }
    }
  }

  // MARK: - Status

  func status(for client: MCPClient) -> MCPClientStatus {
    Self.status(of: client, configURL: configURL(for: client), fileManager: fileManager)
  }

  /// Static so callers with their own config URL (tests, future tooling)
  /// run the exact same check.
  static func status(of client: MCPClient, configURL: URL, fileManager: FileManager) -> MCPClientStatus {
    guard fileManager.fileExists(atPath: configURL.path) else {
      return .configMissing
    }

    let data: Data
    do {
      data = try Data(contentsOf: configURL)
    } catch {
      return .unreadable(error.localizedDescription)
    }

    switch client.configFormat {
    case .json:
      return jsonStatus(of: client, data: data)
    case .toml:
      return tomlStatus(data: data)
    }
  }

  private static func jsonStatus(of client: MCPClient, data: Data) -> MCPClientStatus {
    let object: Any
    do {
      object = try JSONSerialization.jsonObject(with: data)
    } catch {
      return .unreadable(error.localizedDescription)
    }

    guard let root = object as? [String: Any],
          let servers = root[client.jsonContainerKey] as? [String: Any],
          let entry = servers[serverName] as? [String: Any] else {
      return .entryMissing
    }

    let command: String
    if client == .opencode {
      command = (entry["command"] as? [Any])?.first as? String ?? ""
    } else {
      command = entry["command"] as? String ?? ""
    }

    return command.contains(binaryMarker) ? .ready(command: command) : .commandMismatch
  }

  private static func tomlStatus(data: Data) -> MCPClientStatus {
    guard let text = String(data: data, encoding: .utf8) else {
      return .unreadable("The file is not valid UTF-8.")
    }

    let lines = text.components(separatedBy: "\n")
    guard let block = tomlGunkBlock(in: lines) else {
      return .entryMissing
    }

    for line in lines[block] {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("command"), let equals = trimmed.firstIndex(of: "=") else { continue }
      var value = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
      if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
        value = String(value.dropFirst().dropLast())
          .replacingOccurrences(of: "\\\"", with: "\"")
          .replacingOccurrences(of: "\\\\", with: "\\")
      }
      return value.contains(binaryMarker) ? .ready(command: value) : .commandMismatch
    }

    return .commandMismatch
  }

  // MARK: - Wire / unwire

  func wire(_ client: MCPClient) throws {
    let binary = try ensureBinary()
    let url = configURL(for: client)
    switch client.configFormat {
    case .json:
      try wireJSON(client: client, url: url, binaryPath: binary.path)
    case .toml:
      try wireTOML(url: url, binaryPath: binary.path)
    }
  }

  func unwire(_ client: MCPClient) throws {
    let url = configURL(for: client)
    switch client.configFormat {
    case .json:
      try unwireJSON(client: client, url: url)
    case .toml:
      try unwireTOML(url: url)
    }
  }

  // MARK: - JSON read-modify-write

  private func wireJSON(client: MCPClient, url: URL, binaryPath: String) throws {
    var root: [String: Any] = [:]
    if let data = try readIfExists(url), !isEffectivelyEmpty(data) {
      root = try parseJSONObject(data, path: url.path)
    }

    let key = client.jsonContainerKey
    var servers: [String: Any] = [:]
    if let existing = root[key] {
      guard let dictionary = existing as? [String: Any] else {
        throw MCPConfigError.malformedConfig(path: url.path, detail: "`\(key)` is not an object")
      }
      servers = dictionary
    }

    servers[Self.serverName] = client.jsonEntry(binaryPath: binaryPath)
    root[key] = servers
    try writeJSON(root, to: url)
  }

  private func unwireJSON(client: MCPClient, url: URL) throws {
    guard let data = try readIfExists(url), !isEffectivelyEmpty(data) else {
      return
    }

    let root = try parseJSONObject(data, path: url.path)
    let key = client.jsonContainerKey
    guard var servers = root[key] as? [String: Any], servers[Self.serverName] != nil else {
      return // Nothing of ours here — leave the file byte-untouched.
    }

    servers.removeValue(forKey: Self.serverName)
    var updated = root
    updated[key] = servers
    try writeJSON(updated, to: url)
  }

  private func parseJSONObject(_ data: Data, path: String) throws -> [String: Any] {
    let object: Any
    do {
      object = try JSONSerialization.jsonObject(with: data)
    } catch {
      throw MCPConfigError.malformedConfig(path: path, detail: "not valid JSON (\(error.localizedDescription))")
    }
    guard let root = object as? [String: Any] else {
      throw MCPConfigError.malformedConfig(path: path, detail: "the top level is not a JSON object")
    }
    return root
  }

  /// Sorted keys + stable pretty-printing make repeated wires byte-stable.
  private func writeJSON(_ root: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(
      withJSONObject: root,
      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    try write(data + Data("\n".utf8), to: url)
  }

  // MARK: - TOML targeted read-modify-write (Codex)

  /// No Foundation TOML parser exists; per the task's refining note this is a
  /// minimal line-targeted editor for the one table we own,
  /// `[mcp_servers.gunk]`. Every line outside that block is preserved
  /// byte-for-byte. Any gunk entry in a form this editor cannot safely
  /// rewrite (an inline `mcp_servers.gunk = {…}`, a bare `[mcp_servers]`
  /// table that could already define `gunk`, duplicate headers) aborts
  /// instead of guessing.
  private func wireTOML(url: URL, binaryPath: String) throws {
    var lines: [String] = []
    if let data = try readIfExists(url), !isEffectivelyEmpty(data) {
      guard let text = String(data: data, encoding: .utf8) else {
        throw MCPConfigError.malformedConfig(path: url.path, detail: "the file is not valid UTF-8")
      }
      lines = text.components(separatedBy: "\n")
      try validateTOML(lines: lines, path: url.path)
    }

    let canonical = Self.canonicalTOMLBlock(binaryPath: binaryPath)

    if let block = Self.tomlGunkBlock(in: lines) {
      lines.replaceSubrange(block, with: canonical)
    } else {
      // Append at EOF, normalizing only the seam: one blank line between the
      // existing content and our table, one trailing newline.
      while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
        lines.removeLast()
      }
      if !lines.isEmpty {
        lines.append("")
      }
      lines.append(contentsOf: canonical)
    }

    while lines.last?.isEmpty == true {
      lines.removeLast()
    }
    lines.append("") // Single trailing newline.
    try write(Data(lines.joined(separator: "\n").utf8), to: url)
  }

  private func unwireTOML(url: URL) throws {
    guard let data = try readIfExists(url), !isEffectivelyEmpty(data) else {
      return
    }
    guard let text = String(data: data, encoding: .utf8) else {
      throw MCPConfigError.malformedConfig(path: url.path, detail: "the file is not valid UTF-8")
    }

    var lines = text.components(separatedBy: "\n")
    guard let block = Self.tomlGunkBlock(in: lines) else {
      return // No gunk table — leave the file byte-untouched.
    }
    if Self.tomlGunkHeaderCount(in: lines) > 1 {
      throw MCPConfigError.malformedConfig(path: url.path, detail: "multiple [mcp_servers.gunk] tables exist")
    }

    lines.removeSubrange(block)

    // Collapse the seam the removal opened: a blank line we inserted before
    // the table, or doubled blanks where the table sat between two tables.
    let seam = block.lowerBound
    if seam > 0, lines[seam - 1].trimmingCharacters(in: .whitespaces).isEmpty,
       seam >= lines.count || lines[seam].trimmingCharacters(in: .whitespaces).isEmpty {
      lines.remove(at: seam - 1)
    }

    while lines.count > 1, lines.last?.isEmpty == true, lines[lines.count - 2].isEmpty {
      lines.removeLast()
    }
    if lines.last?.isEmpty != true {
      lines.append("")
    }
    if lines == [""] {
      lines = []
    }
    try write(Data(lines.joined(separator: "\n").utf8), to: url)
  }

  private static func canonicalTOMLBlock(binaryPath: String) -> [String] {
    let escaped = binaryPath
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return ["[mcp_servers.gunk]", "command = \"\(escaped)\""]
  }

  private func validateTOML(lines: [String], path: String) throws {
    if Self.tomlGunkHeaderCount(in: lines) > 1 {
      throw MCPConfigError.malformedConfig(path: path, detail: "multiple [mcp_servers.gunk] tables exist")
    }

    let hasHeader = Self.tomlGunkBlock(in: lines) != nil
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.hasPrefix("#") else { continue }
      if trimmed == "[mcp_servers]" {
        throw MCPConfigError.malformedConfig(
          path: path,
          detail: "a bare [mcp_servers] table exists, which this writer cannot safely extend"
        )
      }
      if !hasHeader, trimmed.contains("mcp_servers.gunk") {
        throw MCPConfigError.malformedConfig(
          path: path,
          detail: "a gunk entry exists in a form this writer cannot safely rewrite"
        )
      }
    }
  }

  private static func tomlGunkHeaderCount(in lines: [String]) -> Int {
    lines.count { $0.trimmingCharacters(in: .whitespaces) == "[mcp_servers.gunk]" }
  }

  /// The gunk table: its header line through the last non-blank line before
  /// the next table header (or EOF). Trailing blank lines stay outside the
  /// block so the surrounding spacing survives a replace.
  private static func tomlGunkBlock(in lines: [String]) -> Range<Int>? {
    guard let start = lines.firstIndex(where: {
      $0.trimmingCharacters(in: .whitespaces) == "[mcp_servers.gunk]"
    }) else {
      return nil
    }

    var end = start + 1
    while end < lines.count {
      let trimmed = lines[end].trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("[") { break }
      end += 1
    }
    while end > start + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty {
      end -= 1
    }
    return start..<end
  }

  // MARK: - Filesystem plumbing

  private func readIfExists(_ url: URL) throws -> Data? {
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    do {
      return try Data(contentsOf: url)
    } catch {
      throw MCPConfigError.unreadableConfig(path: url.path, detail: error.localizedDescription)
    }
  }

  private func isEffectivelyEmpty(_ data: Data) -> Bool {
    String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .isEmpty ?? false
  }

  private func write(_ data: Data, to url: URL) throws {
    try fileManager.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: url, options: .atomic)
  }
}
