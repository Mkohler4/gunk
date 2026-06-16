import SwiftUI

/// The module-run-v2 **coverage ledger** — the airy, de-boxed companion to the
/// run console. Trust isn't one run; it's knowing each *class* of input
/// behaves. A spine of the four coverage classes (happy / yours / edge /
/// adversarial), then hairline lists of the passing checks, any failing checks
/// that block sign-off, and recorded known limits, ending in the connect
/// sign-off.
///
/// The ledger reads the saved examples (T-10.3 store, via `BrowseModel`) and
/// the pure coverage derivation (`CoverageState`, T-10.11). It states facts,
/// never a tier to climb (no points, streaks, or "next rung" nudges). The
/// *ready to connect* sign-off is earned by happy path + your own inputs.
struct CoverageLedgerView: View {
  let model: BrowseModel
  let gunkId: Int64

  private struct ClassNode {
    let name: String
    let systemImage: String
    let ok: Bool
    let detail: String
    let count: String
  }

  private var examples: [ModuleExample] { model.examples(for: gunkId) }

  /// The single coverage derivation (T-10.11) — the ledger spine, the sign-off,
  /// and the breadcrumb bar chip all read this so they never disagree.
  private var state: CoverageState { model.coverageState(for: gunkId) }

  /// Passing checks: saved examples the developer hasn't flagged wrong.
  private var passing: [ModuleExample] {
    examples.filter { $0.verdict != .wrong && $0.expectedOutput == nil && $0.inputClass != .adversarial }
  }

  /// Failing checks: a "wrong" verdict or a pinned expected output (blocks sign-off).
  private var failing: [ModuleExample] {
    examples.filter { $0.verdict == .wrong || $0.expectedOutput != nil }
  }

  /// Known limits: adversarial examples carrying a note (characterized edges).
  private var limits: [ModuleExample] {
    examples.filter { $0.inputClass == .adversarial && $0.note != nil }
  }

  private var classes: [ClassNode] {
    let s = state
    let yoursCount = passing.filter { $0.inputClass == .yours }.count

    return [
      ClassNode(
        name: "Happy path",
        systemImage: "bolt.fill",
        ok: s.happy,
        detail: s.happy ? "Shipped example parses clean." : "Run the bundled example once.",
        count: s.happy ? "1" : ""
      ),
      ClassNode(
        name: "Your own inputs",
        systemImage: "person",
        ok: s.yours,
        detail: yoursCount > 0 ? "\(yoursCount) of your inputs checked" : "Bring input you actually care about.",
        count: yoursCount > 0 ? "\(yoursCount) checks" : ""
      ),
      ClassNode(
        name: "Edge cases",
        systemImage: "scope",
        ok: s.edge,
        detail: s.edge ? "Boundary structure covered." : "Boundary inputs untested.",
        count: ""
      ),
      ClassNode(
        name: "Adversarial",
        systemImage: "shield",
        ok: s.adversarial,
        detail: s.adversarial ? "Malformed input characterized." : "Try to break it with bad input.",
        count: s.adversarial ? "\(limits.count) limit\(limits.count == 1 ? "" : "s")" : ""
      ),
    ]
  }

  private var ready: Bool { state.readyToConnect }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      spine
      if !passing.isEmpty { passingSection }
      if !failing.isEmpty { failingSection }
      limitsSection
      signoff
    }
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      Text("Coverage")
        .font(BrandTypography.headline)
        .foregroundStyle(BrandColors.textPrimary)
      Text("Trust isn't one run — it's knowing each class of input behaves.")
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: Spine

  private var spine: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(classes.enumerated()), id: \.offset) { _, node in
        spineNode(node)
      }
    }
    .padding(.vertical, BrandMetrics.Spacing.md)
    .overlay(alignment: .leading) {
      // The spine rail, threaded behind the dots.
      Rectangle()
        .fill(BrandColors.separator)
        .frame(width: 1.5)
        .padding(.leading, 9)
        .padding(.vertical, BrandMetrics.Spacing.lg)
    }
  }

  private func spineNode(_ node: ClassNode) -> some View {
    HStack(alignment: .top, spacing: BrandMetrics.Spacing.md) {
      ZStack {
        Circle()
          .fill(BrandColors.backgroundPrimary)
          .frame(width: 19, height: 19)
        if node.ok {
          Circle().fill(BrandColors.accent).frame(width: 19, height: 19)
          Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(BrandColors.backgroundPrimary)
        } else {
          Circle()
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            .foregroundStyle(BrandColors.textTertiary)
            .frame(width: 19, height: 19)
          Circle().fill(BrandColors.textTertiary).frame(width: 5, height: 5)
        }
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(node.name)
          .font(BrandTypography.callout.weight(.semibold))
          .foregroundStyle(BrandColors.textPrimary)
        Text(node.detail)
          .font(BrandTypography.caption)
          .foregroundStyle(node.ok ? BrandColors.textSecondary : BrandColors.textTertiary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)

      if !node.count.isEmpty {
        Text(node.count)
          .font(BrandTypography.mono)
          .foregroundStyle(BrandColors.textTertiary)
      } else if !node.ok {
        HStack(spacing: 2) {
          Text("test")
          Image(systemName: "arrow.right")
        }
        .font(BrandTypography.caption.weight(.semibold))
        .foregroundStyle(BrandColors.textTertiary)
      }
    }
    .padding(.vertical, BrandMetrics.Spacing.sm)
  }

  // MARK: Passing checks

  private var passingSection: some View {
    ledgerSection(
      title: "Passing checks",
      systemImage: "checkmark",
      count: passing.count,
      tint: BrandColors.textTertiary
    ) {
      ForEach(passing) { example in
        checkRow(example, dot: BrandColors.accent)
      }
    }
  }

  private func checkRow(_ example: ModuleExample, dot: Color) -> some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      Circle().fill(dot).frame(width: 6, height: 6)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: BrandMetrics.Spacing.xs) {
          Text(example.name)
            .font(BrandTypography.callout)
            .foregroundStyle(BrandColors.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)
          if example.inputClass == .yours {
            Text("yours")
              .font(BrandTypography.caption.weight(.semibold))
              .foregroundStyle(ConsolePalette.violet)
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(Capsule().fill(ConsolePalette.violet.opacity(0.13)))
          }
          if example.isGolden {
            Image(systemName: "star.fill")
              .font(.system(size: 8))
              .foregroundStyle(BrandColors.warning)
          }
        }
        Text(classLabel(example.inputClass))
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textTertiary)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, BrandMetrics.Spacing.sm)
    .overlay(alignment: .bottom) {
      Rectangle().fill(BrandColors.separator.opacity(0.5)).frame(height: 1)
    }
  }

  // MARK: Failing

  private var failingSection: some View {
    ledgerSection(
      title: "Failing — blocks sign-off",
      systemImage: "exclamationmark.triangle",
      count: failing.count,
      tint: BrandColors.danger
    ) {
      ForEach(failing) { example in
        HStack(spacing: BrandMetrics.Spacing.sm) {
          Circle().fill(BrandColors.danger).frame(width: 6, height: 6)
          VStack(alignment: .leading, spacing: 2) {
            Text(example.name)
              .font(BrandTypography.callout)
              .foregroundStyle(BrandColors.textPrimary)
              .lineLimit(1)
              .truncationMode(.middle)
            Text(example.note ?? "output didn't match expectation")
              .font(BrandTypography.caption)
              .foregroundStyle(BrandColors.textTertiary)
              .lineLimit(2)
          }
          Spacer(minLength: 0)
          // The guided "Fix it" re-extraction is captured-and-queued this
          // phase (CP-F #10) — the trigger lands later; the affordance is here.
          StatusBadge("Fix it", variant: .warning, systemImage: "wand.and.stars")
        }
        .padding(.vertical, BrandMetrics.Spacing.sm)
        .overlay(alignment: .bottom) {
          Rectangle().fill(BrandColors.separator.opacity(0.5)).frame(height: 1)
        }
      }
    }
  }

  // MARK: Known limits

  private var limitsSection: some View {
    ledgerSection(
      title: "Known limits",
      systemImage: "shield",
      count: limits.count,
      tint: BrandColors.textTertiary
    ) {
      if limits.isEmpty {
        Text("None yet. When you find input it can't handle, record it so it's known — not discovered in production.")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textTertiary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.vertical, BrandMetrics.Spacing.sm)
      } else {
        ForEach(limits) { example in
          HStack(alignment: .top, spacing: BrandMetrics.Spacing.sm) {
            Circle().fill(BrandColors.warning).frame(width: 5, height: 5).padding(.top, 5)
            Text("\(example.name) — \(example.note ?? "")")
              .font(BrandTypography.caption)
              .foregroundStyle(BrandColors.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
          }
          .padding(.vertical, BrandMetrics.Spacing.xs)
        }
      }
    }
  }

  // MARK: Sign-off

  private var signoff: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      HStack(spacing: BrandMetrics.Spacing.xs) {
        Image(systemName: "powerplug")
        Text(ready ? "Ready to connect" : "Not ready to connect")
      }
      .font(BrandTypography.callout.weight(.semibold))
      .foregroundStyle(ready ? BrandColors.accent : BrandColors.textSecondary)

      Text(signoffDetail)
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textTertiary)
        .fixedSize(horizontal: false, vertical: true)

      Button {
        // Wiring the agent connect/MCP handoff is phase-exit work.
      } label: {
        HStack(spacing: BrandMetrics.Spacing.xs) {
          Image(systemName: "powerplug")
          Text("Connect to my agent")
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.brandPrimary)
      .disabled(!ready)
    }
    .padding(.top, BrandMetrics.Spacing.lg)
    .overlay(alignment: .top) {
      Rectangle().fill(BrandColors.separator).frame(height: 1)
    }
  }

  private var signoffDetail: String {
    if ready {
      return "Happy path and your own inputs covered, nothing failing. Your agent can call this with confidence."
    }
    if state.hasFailing {
      return "Fix the failing check first."
    }
    // The sign-off gates on happy path + your own inputs (copy locked
    // 2026-06-16); edge/adversarial deepen coverage but never block it.
    var need: [String] = []
    if !state.happy { need.append("happy path") }
    if !state.yours { need.append("your own inputs") }
    if need.isEmpty { need = ["happy path", "your own inputs"] }
    return "Cover \(need.joined(separator: " and ")) to reach a confident sign-off."
  }

  // MARK: Section chrome

  private func ledgerSection<Content: View>(
    title: String,
    systemImage: String,
    count: Int,
    tint: Color,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs) {
      HStack(spacing: BrandMetrics.Spacing.xs) {
        Image(systemName: systemImage)
        Text(title.uppercased())
          .tracking(0.4)
        Spacer(minLength: 0)
        Text("\(count)")
          .font(BrandTypography.mono)
      }
      .font(BrandTypography.caption.weight(.semibold))
      .foregroundStyle(tint)

      content()
    }
    .padding(.top, BrandMetrics.Spacing.lg)
    .overlay(alignment: .top) {
      Rectangle().fill(BrandColors.separator).frame(height: 1)
    }
  }

  private func classLabel(_ inputClass: ExampleInputClass) -> String {
    switch inputClass {
    case .happy: return "happy path"
    case .yours: return "your input"
    case .edge: return "edge case"
    case .adversarial: return "adversarial"
    }
  }
}
