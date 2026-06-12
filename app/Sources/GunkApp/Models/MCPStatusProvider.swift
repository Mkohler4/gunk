import Foundation

/// The single source of truth for "is gunk wired into Cursor's MCP config?".
///
/// Extracted from `SettingsStatusSnapshot` (T-7.6) so the shell's status
/// strip and the Settings health group render the same answer (ux §4.3,
/// §4.5, D8). Since T-8.9 the check itself lives in
/// `MCPClientConfigurator` (which generalizes it to every supported
/// client); this provider maps the Cursor result onto the exact same
/// `SettingsStatusItem` values it always produced.
struct MCPStatusProvider {
  var configURL: URL
  var fileManager: FileManager

  /// Cursor's config location. Dev-only: `GUNK_MCP_CONFIG=<path>` overrides
  /// it so scripted runs can exercise the ready / needs-setup states without
  /// touching the real `~/.cursor/mcp.json` (mirrors the `GUNK_ENGINE_BIN`
  /// pattern — never set in normal launches).
  static var defaultConfigURL: URL {
    if let override = ProcessInfo.processInfo.environment["GUNK_MCP_CONFIG"],
       !override.isEmpty {
      return URL(fileURLWithPath: override)
    }

    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".cursor/mcp.json")
  }

  init(
    configURL: URL = MCPStatusProvider.defaultConfigURL,
    fileManager: FileManager = .default
  ) {
    self.configURL = configURL
    self.fileManager = fileManager
  }

  func status() -> SettingsStatusItem {
    Self.status(configURL: configURL, fileManager: fileManager)
  }

  static func status(configURL: URL, fileManager: FileManager) -> SettingsStatusItem {
    let path = configURL.path
    let status = MCPClientConfigurator.status(of: .cursor, configURL: configURL, fileManager: fileManager)

    switch status {
    case .configMissing:
      return SettingsStatusItem(
        title: "MCP config",
        value: "Not configured",
        message: "Cursor config was not found at \(path). Follow docs/integration/cursor.md to add gunk.",
        state: .needsSetup
      )
    case .entryMissing:
      return SettingsStatusItem(
        title: "MCP config",
        value: "Missing gunk server",
        message: "Add a `gunk` server entry under `mcpServers` in \(path).",
        state: .needsSetup
      )
    case .ready(let command):
      return SettingsStatusItem(
        title: "MCP config",
        value: "Configured for Cursor",
        message: "Cursor can spawn gunk through \(command).",
        state: .ready
      )
    case .commandMismatch:
      return SettingsStatusItem(
        title: "MCP config",
        value: "Check command",
        message: "The `gunk` MCP server exists, but its command does not look like gunk-mcp.",
        state: .needsSetup
      )
    case .unreadable(let description):
      return SettingsStatusItem(
        title: "MCP config",
        value: "Unreadable",
        message: description,
        state: .unavailable
      )
    }
  }
}
