import Foundation

/// One NDJSON event emitted by `gunk-engine` on stdout. Mirrors the cross-language
/// contract defined in `engine/src/contract/events.ts`. Durable state lives in the
/// shared SQLite store; these events are control/telemetry only.
enum EngineEvent: Equatable {
  case progress(stage: String, fraction: Double, modulesFound: Int?)
  case stage(stage: String, phase: String, durationMs: Int?, counts: [String: Int])
  case result(
    runId: String,
    gunkIds: [Int64],
    accepted: Int,
    needsApproval: Int,
    rejected: Int,
    tracePath: String?
  )
  case error(message: String, stage: String?)
}

extension EngineEvent: Decodable {
  private enum CodingKeys: String, CodingKey {
    case type
    case stage
    case phase
    case fraction
    case modulesFound
    case durationMs
    case counts
    case runId
    case gunkIds
    case accepted
    case needsApproval
    case rejected
    case tracePath
    case message
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let type = try container.decode(String.self, forKey: .type)

    switch type {
    case "progress":
      self = .progress(
        stage: try container.decode(String.self, forKey: .stage),
        fraction: try container.decode(Double.self, forKey: .fraction),
        modulesFound: try container.decodeIfPresent(Int.self, forKey: .modulesFound)
      )
    case "stage":
      self = .stage(
        stage: try container.decode(String.self, forKey: .stage),
        phase: try container.decode(String.self, forKey: .phase),
        durationMs: try container.decodeIfPresent(Int.self, forKey: .durationMs),
        counts: try container.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
      )
    case "result":
      self = .result(
        runId: try container.decode(String.self, forKey: .runId),
        gunkIds: try container.decodeIfPresent([Int64].self, forKey: .gunkIds) ?? [],
        accepted: try container.decodeIfPresent(Int.self, forKey: .accepted) ?? 0,
        needsApproval: try container.decodeIfPresent(Int.self, forKey: .needsApproval) ?? 0,
        rejected: try container.decodeIfPresent(Int.self, forKey: .rejected) ?? 0,
        tracePath: try container.decodeIfPresent(String.self, forKey: .tracePath)
      )
    case "error":
      self = .error(
        message: try container.decode(String.self, forKey: .message),
        stage: try container.decodeIfPresent(String.self, forKey: .stage)
      )
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .type,
        in: container,
        debugDescription: "Unknown engine event type: \(type)"
      )
    }
  }

  /// Decodes a single NDJSON line, returning `nil` for blank lines or lines that
  /// are not engine events (the engine logs human-readable diagnostics on stderr,
  /// but be defensive in case anything leaks onto stdout).
  static func decode(line: String) -> EngineEvent? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else {
      return nil
    }

    return try? JSONDecoder().decode(EngineEvent.self, from: data)
  }
}
