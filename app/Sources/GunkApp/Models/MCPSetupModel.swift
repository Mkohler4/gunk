import Foundation

/// The single source of truth for "which AI clients can see gunk?" (T-8.10).
///
/// One instance lives in the shell and is observed by all three MCP
/// surfaces — the sidebar chip, the setup sheet, and Settings' per-client
/// toggles — so a wire/unwire from any of them re-checks every status and
/// the surfaces can never disagree (the task's "statuses agree everywhere"
/// rule). All filesystem work happens in `MCPClientConfigurator`; this model
/// only orchestrates and publishes.
@MainActor
final class MCPSetupModel: ObservableObject {
  /// What a client row renders. `problem` carries the configurator's
  /// message verbatim — a malformed config is surfaced, never papered over.
  enum DisplayStatus: Equatable {
    case connected
    case notSetUp
    case notDetected
    case problem(String)

    var label: String {
      switch self {
      case .connected: return "Connected"
      case .notSetUp: return "Not set up"
      case .notDetected: return "Not detected"
      case .problem: return "Problem"
      }
    }
  }

  struct ClientRow: Identifiable, Equatable {
    let client: MCPClient
    let isDetected: Bool
    let status: MCPClientStatus
    let configURL: URL
    /// The last wire/unwire failure for this client, verbatim from
    /// `MCPConfigError` (the refining-loop rule: surface the abort error
    /// as-is, with an open-config affordance, never silently overwrite).
    var actionError: String?

    var id: String { client.id }

    var displayStatus: DisplayStatus {
      switch status {
      case .ready:
        // A wired config wins over detection heuristics: if the entry
        // exists and spawns gunk-mcp, the agent is connected.
        return .connected
      case .unreadable(let message):
        return .problem(message)
      case .configMissing:
        return isDetected ? .notSetUp : .notDetected
      case .entryMissing, .commandMismatch:
        return .notSetUp
      }
    }

    var isConnected: Bool { displayStatus == .connected }

    /// Connect applies to anything not connected; "Connect all" narrows to
    /// detected clients so one click never writes config for tools that
    /// are not installed.
    var isConnectable: Bool { !isConnected }
  }

  @Published private(set) var rows: [ClientRow] = []

  private let configurator: MCPClientConfigurator

  /// Dev-only: `GUNK_DEBUG_MCP_HOME=<dir>` points the entire configurator —
  /// detection, statuses, and writes — at a staged fake home, so scripted
  /// screenshot runs can exercise every state (including a real Connect
  /// click) without touching any real client config. Same family as
  /// `GUNK_MCP_CONFIG` / `GUNK_DEBUG_SECTION`; never set in normal launches.
  nonisolated static func defaultConfigurator(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> MCPClientConfigurator {
    if let fakeHome = environment["GUNK_DEBUG_MCP_HOME"], !fakeHome.isEmpty {
      let home = URL(fileURLWithPath: fakeHome, isDirectory: true)
      return MCPClientConfigurator(
        home: home,
        applicationsDirectory: home.appendingPathComponent("Applications", isDirectory: true),
        environment: environment.filter { $0.key != "GUNK_MCP_CONFIG" }
      )
    }
    return MCPClientConfigurator()
  }

  init(configurator: MCPClientConfigurator = MCPSetupModel.defaultConfigurator()) {
    self.configurator = configurator
    refresh()
  }

  // MARK: Derived state

  /// The chip's question: is at least one agent wired in?
  var isAnyClientConnected: Bool {
    rows.contains(where: \.isConnected)
  }

  /// Hover disclosure for the healthy chip: which clients are wired, and
  /// through which config file.
  var connectedSummary: String {
    let connected = rows.filter(\.isConnected)
    guard !connected.isEmpty else {
      return ""
    }
    return connected
      .map { "\($0.client.displayName) (\($0.configURL.path))" }
      .joined(separator: ", ")
  }

  /// The clients "Connect all" would wire: detected and not yet connected.
  var connectAllTargets: [MCPClient] {
    rows.filter { $0.isDetected && $0.isConnectable }.map(\.client)
  }

  // MARK: Actions

  func refresh() {
    let previousErrors = Dictionary(
      uniqueKeysWithValues: rows.map { ($0.client, $0.actionError) }
    )
    let installed = Set(configurator.detectInstalled())
    rows = MCPClient.allCases.map { client in
      ClientRow(
        client: client,
        isDetected: installed.contains(client),
        status: configurator.status(for: client),
        configURL: configurator.configURL(for: client),
        actionError: previousErrors[client] ?? nil
      )
    }
  }

  func connect(_ client: MCPClient) {
    perform(client) { try configurator.wire(client) }
  }

  func disconnect(_ client: MCPClient) {
    perform(client) { try configurator.unwire(client) }
  }

  func connectAll() {
    for client in connectAllTargets {
      connect(client)
    }
  }

  private func perform(_ client: MCPClient, _ action: () throws -> Void) {
    var error: String?
    do {
      try action()
    } catch let configError as MCPConfigError {
      error = configError.localizedDescription
    } catch let unexpected {
      error = unexpected.localizedDescription
    }

    refresh()
    if let index = rows.firstIndex(where: { $0.client == client }) {
      rows[index].actionError = error
    }
  }
}
