import Foundation

/// A per-run trace written by `gunk-engine` to `~/.gunk/runs/<runId>/trace.json`.
/// Mirrors the `RunTrace` schema in `engine/src/trace/trace.ts`. Decoded
/// best-effort for display in the Runs panel; unknown fields are ignored.
struct RunTrace: Decodable, Identifiable, Equatable, Sendable {
  let runId: String
  let sourceId: Int64?
  let sourceName: String
  let provider: String
  let model: String
  let startedAtMs: Double
  let finishedAtMs: Double?
  let status: String
  let error: String?
  let stages: [Stage]
  let refinements: [Refinement]?
  let verification: Verification?
  let summary: Summary

  var id: String { runId }

  var startedAt: Date { Date(timeIntervalSince1970: startedAtMs / 1000) }

  var durationMs: Double? {
    guard let finishedAtMs else { return nil }
    return finishedAtMs - startedAtMs
  }

  struct Stage: Decodable, Identifiable, Equatable, Sendable {
    let stage: String
    let durationMs: Double
    let counts: [String: Int]
    let status: String
    let error: String?

    var id: String { stage }
  }

  struct Summary: Decodable, Equatable, Sendable {
    let accepted: Int
    let needsApproval: Int
    let rejected: Int
    let gunkIds: [Int64]
  }

  struct Refinement: Decodable, Equatable, Sendable {
    let capability: String
    let accepted: Bool
    let rejectReason: String?
    let module: Module?
  }

  struct Module: Decodable, Equatable, Sendable {
    let name: String
    let ownedFiles: [String]?
    let sharedDeps: [String]?
    let surface: [Surface]?
  }

  struct Surface: Decodable, Equatable, Sendable {
    let path: String
    let symbol: String?
  }

  struct Verification: Decodable, Equatable, Sendable {
    let build: [BuildResult]?
    let selfContainment: [SelfContainmentResult]?
  }

  struct BuildResult: Decodable, Equatable, Sendable {
    let bundlePath: String
    let language: String
    let built: Bool
    let skipped: Bool
    let command: String?
    let log: String
  }

  struct SelfContainmentResult: Decodable, Equatable, Sendable {
    let moduleName: String
    let imports: String
    let entrypoint: String
    let danglingImports: [DanglingImport]
    let missingEntrypoints: [MissingEntrypoint]
  }

  struct DanglingImport: Decodable, Equatable, Sendable {
    let fromPath: String
    let moduleSpecifier: String?
    let resolvedTarget: String?
    let reason: String
  }

  struct MissingEntrypoint: Decodable, Equatable, Sendable {
    let path: String
    let symbol: String?
    let reason: String
  }
}

/// Reads the trace artifacts that the engine drops under `~/.gunk/runs`.
struct RunTraceStore {
  private let runsDirectory: URL
  private let fileManager: FileManager

  init(
    runsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".gunk/runs"),
    fileManager: FileManager = .default
  ) {
    self.runsDirectory = runsDirectory
    self.fileManager = fileManager
  }

  /// All traces, newest run first. Malformed or partial traces are skipped.
  func recentTraces(limit: Int = 50) -> [RunTrace] {
    guard
      let entries = try? fileManager.contentsOfDirectory(
        at: runsDirectory,
        includingPropertiesForKeys: nil
      )
    else {
      return []
    }

    let decoder = JSONDecoder()
    let traces = entries.compactMap { entry -> RunTrace? in
      let traceURL = entry.appendingPathComponent("trace.json")
      guard let data = try? Data(contentsOf: traceURL) else { return nil }
      return try? decoder.decode(RunTrace.self, from: data)
    }

    return Array(traces.sorted { $0.startedAtMs > $1.startedAtMs }.prefix(limit))
  }
}
