import Foundation

/// How to invoke the engine: the executable plus any leading arguments (empty
/// for the compiled single binary, `["run", "<entrypoint>"]` for a dev `bun`).
struct ResolvedEngine: Equatable {
  let executableURL: URL
  let leadingArguments: [String]
}

enum EngineLaunchError: Error, LocalizedError {
  case binaryNotFound
  case launchFailed(String)
  case engineFailed(String)
  case missingResult

  var errorDescription: String? {
    switch self {
    case .binaryNotFound:
      return "Could not locate the gunk-engine binary. Build it with `make app` or set GUNK_ENGINE_BIN."
    case .launchFailed(let message):
      return "Failed to start gunk-engine: \(message)"
    case .engineFailed(let message):
      return message
    case .missingResult:
      return "gunk-engine exited without reporting a result."
    }
  }
}

/// Spawns the engine and yields its NDJSON events. Abstracted so the runner can
/// be tested with a canned stream instead of a real subprocess.
protocol EngineLauncher {
  func launch(arguments: [String], environment: [String: String]) -> AsyncThrowingStream<EngineEvent, Error>
}

enum EngineBinary {
  /// Resolution order:
  /// 1. `GUNK_ENGINE_BIN` env var (explicit binary, used in dev/CI).
  /// 2. `gunk-engine` bundled in the app's Resources (production).
  /// 3. `bun` on PATH + `GUNK_ENGINE_SRC` pointing at `engine/src/index.ts` (dev).
  static func resolve(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    bundle: Bundle = .main,
    fileManager: FileManager = .default
  ) -> ResolvedEngine? {
    if let explicit = environment["GUNK_ENGINE_BIN"], !explicit.isEmpty {
      return ResolvedEngine(executableURL: URL(fileURLWithPath: explicit), leadingArguments: [])
    }

    if let bundled = bundle.url(forResource: "gunk-engine", withExtension: nil),
       fileManager.isExecutableFile(atPath: bundled.path) {
      return ResolvedEngine(executableURL: bundled, leadingArguments: [])
    }

    if let source = environment["GUNK_ENGINE_SRC"], !source.isEmpty,
       let bun = locate(executable: "bun", environment: environment, fileManager: fileManager) {
      return ResolvedEngine(executableURL: bun, leadingArguments: ["run", source])
    }

    return nil
  }

  private static func locate(
    executable: String,
    environment: [String: String],
    fileManager: FileManager
  ) -> URL? {
    let candidates = (environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin")
      .split(separator: ":")
      .map { URL(fileURLWithPath: String($0)).appendingPathComponent(executable) }

    return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
  }
}

/// Production launcher: runs the resolved engine as a child `Process`, reading
/// NDJSON events off stdout and forwarding stderr diagnostics to the app log.
struct ProcessEngineLauncher: EngineLauncher {
  private let resolve: () -> ResolvedEngine?

  init(resolve: @escaping () -> ResolvedEngine? = { EngineBinary.resolve() }) {
    self.resolve = resolve
  }

  func launch(arguments: [String], environment: [String: String]) -> AsyncThrowingStream<EngineEvent, Error> {
    AsyncThrowingStream { continuation in
      guard let resolved = resolve() else {
        continuation.finish(throwing: EngineLaunchError.binaryNotFound)
        return
      }

      let process = Process()
      process.executableURL = resolved.executableURL
      process.arguments = resolved.leadingArguments + arguments
      process.environment = environment

      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      process.standardOutput = stdoutPipe
      process.standardError = stderrPipe

      var sawError: String?
      var pendingData = Data()
      let newline = UInt8(ascii: "\n")

      stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        guard !chunk.isEmpty else { return }
        pendingData.append(chunk)

        while let index = pendingData.firstIndex(of: newline) {
          let lineData = pendingData.subdata(in: pendingData.startIndex..<index)
          pendingData.removeSubrange(pendingData.startIndex...index)
          guard
            let line = String(data: lineData, encoding: .utf8),
            let event = EngineEvent.decode(line: line)
          else {
            continue
          }
          if case .error(let message, _) = event {
            sawError = message
          }
          continuation.yield(event)
        }
      }

      stderrPipe.fileHandleForReading.readabilityHandler = { handle in
        let chunk = handle.availableData
        guard !chunk.isEmpty, let text = String(data: chunk, encoding: .utf8) else { return }
        FileHandle.standardError.write(Data(text.utf8))
      }

      process.terminationHandler = { process in
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        if let message = sawError {
          continuation.finish(throwing: EngineLaunchError.engineFailed(message))
        } else if process.terminationStatus != 0 {
          continuation.finish(
            throwing: EngineLaunchError.engineFailed(
              "gunk-engine exited with status \(process.terminationStatus)."
            )
          )
        } else {
          continuation.finish()
        }
      }

      do {
        try process.run()
      } catch {
        continuation.finish(throwing: EngineLaunchError.launchFailed(error.localizedDescription))
        return
      }

      continuation.onTermination = { @Sendable termination in
        if case .cancelled = termination, process.isRunning {
          process.terminate()
        }
      }
    }
  }
}
