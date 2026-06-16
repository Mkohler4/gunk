import Foundation

/// Resolves the interpreter command for a runnable module from its stored
/// entrypoints + language (Hard data fact 4). Returns `nil` when no command
/// can be derived confidently — the runner turns that into a
/// `.cannotDetermine` result rather than guessing (ADR-0016).
enum EntrypointResolver {
  static func resolve(_ input: RunInput) -> ResolvedCommand? {
    guard let entry = input.entrypoints.first(where: { !$0.path.isEmpty }) else {
      return nil
    }

    switch input.language {
    case .python:
      // The file form runs the entry module. The symbol-import form
      // (`python3 -c "from <mod> import <sym>"`) is a future refinement;
      // running the file is the safe one-shot default this phase.
      return ResolvedCommand(executable: "python3", arguments: [entry.path] + input.arguments)
    case .node:
      return ResolvedCommand(executable: "node", arguments: [entry.path] + input.arguments)
    case .other:
      return nil
    }
  }
}
