import Foundation

/// Decides whether a module is a one-shot terminal entrypoint the sandbox can
/// fairly run, or *why it can't be run here* — keying off language, entrypoint
/// shape, and the declared dependency manifest (CP-F decision #9, ADR-0016).
///
/// The bias is conservative: **when a signal is ambiguous, prefer a
/// not-runnable-here reason over a wrong guess.** A wrong guess runs code we
/// shouldn't; a conservative refusal just shows the call-it snippet instead.
enum RunnabilityClassifier {
  /// Dependency name fragments that mark a module as a non-terminating
  /// server / watcher / TUI. Checked as substrings (lowercased).
  private static let serverSignals: Set<String> = [
    "express", "fastify", "koa", "hapi", "nest", "next", "nuxt",
    "flask", "django", "fastapi", "uvicorn", "gunicorn", "starlette",
    "tornado", "aiohttp.web", "http.server", "ws", "socket.io", "socketio",
    "nodemon", "chokidar", "watchman", "blessed", "ink",
  ]

  /// Dependency fragments that mean the module's whole job is to reach the
  /// network / a live API. The sandbox is network-off, so prove it elsewhere.
  private static let networkSignals: Set<String> = [
    "requests", "httpx", "aiohttp", "urllib3", "axios", "node-fetch",
    "got", "undici", "superagent", "needle", "request-promise",
  ]

  /// Dependency fragments for SDKs that require credentials/secrets (they
  /// also touch the network, but "needs secrets" is the more useful reason).
  private static let secretSignals: Set<String> = [
    "boto3", "botocore", "google-cloud", "googleapis", "@aws-sdk",
    "aws-sdk", "stripe", "openai", "anthropic", "@azure", "azure-",
    "twilio", "sendgrid", "@google-cloud",
  ]

  /// Dependency fragments for UI surfaces (deferred to T-10.13).
  private static let uiSignals: Set<String> = [
    "react-dom", "react-native", "vue", "svelte", "@angular", "electron",
    "vite", "webpack-dev-server", "streamlit", "gradio", "dash",
  ]

  /// Dependency fragments for interactive CLIs that read from stdin.
  private static let interactiveSignals: Set<String> = [
    "inquirer", "prompts", "enquirer", "@clack", "questionary",
  ]

  static func classify(_ input: RunInput) -> Runnability {
    // No resolvable entrypoint → we genuinely can't tell how to run it.
    guard input.entrypoints.contains(where: { !$0.path.isEmpty }) else {
      return .cannotDetermine
    }

    // Only languages with a confident one-shot interpreter are candidates.
    switch input.language {
    case .python, .node:
      break
    case .other:
      return .cannotDetermine
    }

    // Dependency signals, most-specific first. UI and long-running are
    // category facts; secrets is more actionable than the network reason it
    // implies; interactive is last because it is the weakest signal.
    let deps = input.dependencies.map { $0.lowercased() }
    if matches(deps, uiSignals) { return .uiModule }
    if matches(deps, serverSignals) { return .longRunning }
    if matches(deps, secretSignals) { return .needsSecrets }
    if matches(deps, networkSignals) { return .needsNetwork }
    if matches(deps, interactiveSignals) { return .interactiveStdin }

    return .terminalRunnable
  }

  private static func matches(_ deps: [String], _ signals: Set<String>) -> Bool {
    deps.contains { dep in signals.contains { dep.contains($0) } }
  }
}
