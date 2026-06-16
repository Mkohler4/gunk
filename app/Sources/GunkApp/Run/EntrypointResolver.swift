import Foundation

/// Resolves the interpreter command for a runnable module from its stored
/// entrypoints + language (Hard data fact 4). Returns `nil` when no command
/// can be derived confidently — the runner turns that into a
/// `.cannotDetermine` result rather than guessing (ADR-0016).
enum EntrypointResolver {
  static func resolve(_ input: RunInput) -> ResolvedCommand? {
    guard let entry = input.entrypoints.first(where: { isSafeEntrypointPath($0.path) }) else {
      return nil
    }

    switch input.language {
    case .python:
      // The file form runs the entry module. The symbol-import form
      // (`python3 -c "from <mod> import <sym>"`) is a future refinement;
      // running the file is the safe one-shot default this phase.
      //
      // The entry path is validated to be a bundle-relative file (not a
      // flag), so the interpreter treats it as a script and everything after
      // it as the script's argv — flags can't be smuggled via `arguments`.
      return ResolvedCommand(executable: "python3", arguments: [entry.path] + input.arguments)
    case .node:
      return ResolvedCommand(executable: "node", arguments: [entry.path] + input.arguments)
    case .other:
      return nil
    }
  }

  /// A safe entrypoint is a non-empty, bundle-*relative* file path that can't
  /// escape the staged bundle or be misread as an interpreter flag. Mirrors
  /// `Extractor.validateRelativePath` and adds a leading-`-` guard so a
  /// poisoned manifest/trace entry like `-c` or `../../other/main.py` is
  /// refused rather than executed (security review, 2026-06-15).
  static func isSafeEntrypointPath(_ path: String) -> Bool {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    guard
      !normalized.isEmpty,
      !normalized.hasPrefix("/"),
      !normalized.hasPrefix("-"),
      !normalized.split(separator: "/").contains("..")
    else {
      return false
    }
    return true
  }
}
