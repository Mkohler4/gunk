import Foundation

/// Builds the macOS Seatbelt (`sandbox-exec`) wrapper for a smoke run: a
/// deny-by-default profile that confines writes to the run directory and
/// turns network off, plus the wrapped command line (ADR-0016).
///
/// Pure and side-effect free except `writeProfile` — so the profile string
/// and the wrapped argv are unit-testable without spawning anything.
enum RunSandbox {
  static let sandboxExecPath = URL(fileURLWithPath: "/usr/bin/sandbox-exec")

  /// Whether `sandbox-exec` exists and is executable on this machine. Note
  /// this does **not** prove it can be *applied* — applying a profile fails
  /// when the host process is itself already sandboxed (it does not nest).
  static func isAvailable(fileManager: FileManager = .default) -> Bool {
    fileManager.isExecutableFile(atPath: sandboxExecPath.path)
  }

  /// A deny-by-default Seatbelt profile.
  ///
  /// - reads are broadly allowed (interpreters must read their runtime and
  ///   the bundle; reads are not the threat — writes and network are);
  /// - writes are confined to `runDirectory` (+ the temp dir and the null
  ///   device a process needs to start);
  /// - **network is denied outright.**
  static func profile(runDirectory: URL, temporaryDirectory: URL = FileManager.default.temporaryDirectory) -> String {
    let runPath = canonicalPath(runDirectory)
    let tempPath = canonicalPath(temporaryDirectory)
    return """
    (version 1)
    (deny default)
    (allow process-fork)
    (allow process-exec*)
    (allow sysctl-read)
    (allow file-read*)
    (allow file-write*
      (subpath "\(escape(runPath))")
      (subpath "\(escape(tempPath))")
      (literal "/dev/null")
      (literal "/dev/dtracehelper"))
    (allow file-write-data
      (literal "/dev/stdout")
      (literal "/dev/stderr")
      (regex #"^/dev/tty"))
    (deny network*)
    """
  }

  /// Wraps a resolved interpreter command in `sandbox-exec -f <profile>`.
  /// `interpreter` must be an absolute path so the sandbox does not depend on
  /// PATH resolution inside the confined process.
  static func wrap(
    interpreter: URL,
    arguments: [String],
    profilePath: URL
  ) -> (executable: URL, arguments: [String]) {
    (
      executable: sandboxExecPath,
      arguments: ["-f", profilePath.path, interpreter.path] + arguments
    )
  }

  /// Writes the profile into the run directory and returns its URL.
  static func writeProfile(
    _ profile: String,
    into runDirectory: URL,
    fileManager: FileManager = .default
  ) throws -> URL {
    let url = runDirectory.appendingPathComponent("sandbox.sb")
    try profile.data(using: .utf8)?.write(to: url)
    return url
  }

  /// Resolves symlinks so the profile's subpaths match the real paths the
  /// kernel sees (e.g. `/var` → `/private/var`, the common macOS temp case).
  private static func canonicalPath(_ url: URL) -> String {
    url.resolvingSymlinksInPath().path
  }

  private static func escape(_ path: String) -> String {
    path.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }
}
