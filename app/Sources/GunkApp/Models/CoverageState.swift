import Foundation

/// The honest coverage readout (T-10.11, CP-J) — a **pure** derivation over a
/// module's saved examples + its last run. It states which classes of input are
/// covered as plain facts; it is **not** a tier ladder (no levels, points,
/// streaks, or "next rung" nudges).
///
/// The *ready to connect* sign-off rule (CP-F open question #1; copy locked
/// 2026-06-16 in `docs/design/explorations/module-run-v2.md`) is **Happy path
/// covered + at least one of Your own inputs checked**, with nothing failing.
/// Edge cases and adversarial deepen coverage but are **not** required to
/// unlock the sign-off. A lone synthesized happy-path pass is never sufficient
/// on its own (it carries no developer-brought input), and agent-initiated runs
/// alone never count as human-checked coverage (open question #8) — `yours`
/// coverage can only come from an example the developer saved.
struct CoverageState: Equatable, Sendable {
  let happy: Bool
  let yours: Bool
  let edge: Bool
  let adversarial: Bool
  /// A pinned failing case (a `wrong` verdict or a pinned expected output)
  /// blocks the sign-off until it is resolved.
  let hasFailing: Bool

  /// How many of the four input classes are covered — a plain count, never a
  /// tier to climb.
  var classesCovered: Int { [happy, yours, edge, adversarial].filter { $0 }.count }

  /// The locked sign-off: Happy path covered + at least one of Your own inputs
  /// checked, and nothing failing.
  var readyToConnect: Bool { happy && yours && !hasFailing }

  static func derive(examples: [ModuleExample], lastRun: SmokeRunRecord?) -> CoverageState {
    let hasFailing = examples.contains { $0.verdict == .wrong || $0.expectedOutput != nil }

    // Passing checks: saved examples not flagged wrong, excluding adversarial
    // (those characterize known limits, not happy-path coverage).
    let passing = examples.filter {
      $0.verdict != .wrong && $0.expectedOutput == nil && $0.inputClass != .adversarial
    }

    // A known limit is an adversarial example carrying a note.
    let hasLimit = examples.contains { $0.inputClass == .adversarial && $0.note != nil }

    return CoverageState(
      happy: passing.contains { $0.inputClass == .happy } || lastRun?.passed == true,
      yours: passing.contains { $0.inputClass == .yours },
      edge: passing.contains { $0.inputClass == .edge },
      adversarial: hasLimit,
      hasFailing: hasFailing
    )
  }
}

extension BrowseModel {
  /// The coverage state for a module, derived from its saved examples + last
  /// run (T-10.3). The ledger sign-off and the breadcrumb bar chip both read
  /// this single source so they never disagree.
  func coverageState(for gunkId: Int64) -> CoverageState {
    CoverageState.derive(
      examples: examples(for: gunkId),
      lastRun: lastSmokeRun(for: gunkId)
    )
  }
}
