import Foundation

/// The single source of truth for "is gunk wired into Cursor's MCP config?".
///
/// Extracted from `SettingsStatusSnapshot` (T-7.6) so the shell's status
/// strip and the Settings health group render the same answer (ux §4.3,
/// §4.5, D8). The check itself is unchanged: it inspects Cursor's
/// `~/.cursor/mcp.json` for a `gunk` server entry that spawns `gunk-mcp`.
struct MCPStatusProvider {
  var configURL: URL
  var fileManager: FileManager

  init(
    configURL: URL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".cursor/mcp.json"),
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
    guard fileManager.fileExists(atPath: path) else {
      return SettingsStatusItem(
        title: "MCP config",
        value: "Not configured",
        message: "Cursor config was not found at \(path). Follow docs/integration/cursor.md to add gunk.",
        state: .needsSetup
      )
    }

    do {
      let data = try Data(contentsOf: configURL)
      let object = try JSONSerialization.jsonObject(with: data)
      guard let root = object as? [String: Any],
            let servers = root["mcpServers"] as? [String: Any],
            let gunk = servers["gunk"] as? [String: Any] else {
        return SettingsStatusItem(
          title: "MCP config",
          value: "Missing gunk server",
          message: "Add a `gunk` server entry under `mcpServers` in \(path).",
          state: .needsSetup
        )
      }

      let command = gunk["command"] as? String ?? ""
      if command.contains("gunk-mcp") {
        return SettingsStatusItem(
          title: "MCP config",
          value: "Configured for Cursor",
          message: "Cursor can spawn gunk through \(command).",
          state: .ready
        )
      }

      return SettingsStatusItem(
        title: "MCP config",
        value: "Check command",
        message: "The `gunk` MCP server exists, but its command does not look like gunk-mcp.",
        state: .needsSetup
      )
    } catch {
      return SettingsStatusItem(
        title: "MCP config",
        value: "Unreadable",
        message: error.localizedDescription,
        state: .unavailable
      )
    }
  }
}
