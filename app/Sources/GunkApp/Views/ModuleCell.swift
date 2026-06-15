import SwiftUI

/// The one trust verdict a briefing card leads with (toolbox-v2 cell anatomy:
/// one verdict per cell; the instrument-panel readout lives in the detail).
enum ModuleCellState {
  case agentReady
  case needsApproval
  case notInToolbox

  var label: String {
    switch self {
    case .agentReady:
      return "Agent-ready"
    case .needsApproval:
      return "Needs approval"
    case .notInToolbox:
      return "Not in toolbox"
    }
  }

  var color: Color {
    switch self {
    case .agentReady:
      return BrandColors.accent
    case .needsApproval:
      return BrandColors.warning
    case .notInToolbox:
      return BrandColors.textTertiary
    }
  }
}

/// A toolbox-v2 briefing card: state label, provider badge, name, purpose,
/// `via <model>` provenance, tag pills. Solid surface (no glass), hover lift,
/// selection/arrival as a 2px accent ring. The hero variant is the same
/// anatomy, larger.
struct ModuleCell: View {
  let item: BrowseItem
  let state: ModuleCellState
  let provenance: BrowseProvenance?
  var isHero = false
  let isSelected: Bool
  /// Freshly created by the run that just completed (ux §4.4): shares the
  /// selection ring vocabulary for a beat, then decays.
  let isArrived: Bool
  let onSelect: () -> Void

  @State private var isHovering = false

  /// Mockup minimums: standard card 168, hero 210.
  private static let standardMinHeight: CGFloat = 168
  private static let heroMinHeight: CGFloat = 210
  /// Selection / arrival ring (mockup: `box-shadow: 0 0 0 2px green`).
  private static let ringWidth: CGFloat = 2
  /// Needs-attention top edge (mockup `.card.attn::before`: `height: 3px`,
  /// top-rounded with the card's own radius).
  private static let attentionEdgeHeight: CGFloat = 3
  /// *Not in toolbox* is the standard card dimmed (hover restores it).
  private static let dimmedOpacity: Double = 0.5
  /// Provider watermark glyph box — roughly card height so the mark anchors
  /// the corner; the hero card carries a larger one.
  private static let watermarkSize: CGFloat = 150
  private static let heroWatermarkSize: CGFloat = 200
  /// How far the watermark bleeds past the bottom-trailing corner before the
  /// card's rounded rect clips it.
  private static let watermarkBleed: CGFloat = 28
  /// The watermark is faint at rest and warms a touch on hover.
  private static let watermarkOpacity: Double = 0.06
  private static let watermarkHoverOpacity: Double = 0.09

  private var showsRing: Bool {
    isSelected || isArrived
  }

  private var maxVisibleTags: Int {
    isHero ? 6 : 3
  }

  var body: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.sm) {
      Text(state.label)
        .font(BrandTypography.callout.weight(.semibold))
        .foregroundStyle(state.color)

      Text(item.gunk.name)
        .font(isHero ? BrandTypography.cardTitleHero : BrandTypography.cardTitle)
        .foregroundStyle(BrandColors.textPrimary)
        .lineLimit(2)

      if let purpose = item.gunk.purpose {
        Text(purpose)
          .font(BrandTypography.body)
          .foregroundStyle(BrandColors.textSecondary)
          .lineLimit(isHero ? 4 : 2)
      }

      Spacer(minLength: BrandMetrics.Spacing.xs)

      // FUTURE: usage telemetry — prepend "N uses this week · " to this meta
      // line once real usage data exists. Never fabricate the number.
      if let provenance {
        Text("via \(provenance.model)")
          .font(BrandTypography.caption)
          .foregroundStyle(BrandColors.textTertiary)
          .lineLimit(1)
      }

      if !item.tags.isEmpty {
        tagRow
      }
    }
    .padding(BrandMetrics.Spacing.lg)
    .frame(
      maxWidth: .infinity,
      minHeight: isHero ? Self.heroMinHeight : Self.standardMinHeight,
      maxHeight: .infinity,
      alignment: .topLeading
    )
    .background(
      ZStack(alignment: .bottomTrailing) {
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous)
          .fill(isHovering ? BrandColors.backgroundElevatedHover : BrandColors.backgroundElevated)

        // Provider provenance as a large brand watermark bleeding off the
        // bottom-trailing corner (clipped to the card). Lifts slightly on
        // hover so the card "warms up" with the rest of the surface.
        if let provenance {
          ProviderWatermark(
            provider: provenance.provider,
            size: isHero ? Self.heroWatermarkSize : Self.watermarkSize,
            opacity: isHovering ? Self.watermarkHoverOpacity : Self.watermarkOpacity
          )
          .offset(x: Self.watermarkBleed, y: Self.watermarkBleed)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous))
    )
    .overlay(alignment: .top) {
      // Needs-approval amber top edge (mockup `.card.attn::before`): the
      // card's own rounded rect masked to its top sliver, so the edge stays
      // concentric with the corners — never a square strip on a round card.
      // Amber/`warning` only; the coral provider badge is an unrelated mark.
      // The selection/arrival ring wins while present: the edge fades under
      // it so two outlines never compete at the top corners.
      if state == .needsApproval, !showsRing {
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous)
          .fill(BrandColors.warning)
          .mask(alignment: .top) {
            Rectangle()
              .frame(height: Self.attentionEdgeHeight)
          }
          .allowsHitTesting(false)
          .transition(.opacity)
      }
    }
    .overlay {
      if showsRing {
        RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous)
          .strokeBorder(BrandColors.accent, lineWidth: Self.ringWidth)
          .allowsHitTesting(false)
      }
    }
    .opacity(state == .notInToolbox && !isHovering ? Self.dimmedOpacity : 1)
    .offset(y: isHovering ? -2 : 0)
    .contentShape(RoundedRectangle(cornerRadius: BrandMetrics.Radius.large, style: .continuous))
    .onTapGesture(perform: onSelect)
    .onHover { hovering in
      withAnimation(BrandMotion.quick) {
        isHovering = hovering
      }
    }
    .animation(BrandMotion.quick, value: isSelected)
    .animation(BrandMotion.smooth, value: isArrived)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(item.gunk.name), \(state.label)")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var tagRow: some View {
    HStack(spacing: BrandMetrics.Spacing.xs) {
      ForEach(item.tags.prefix(maxVisibleTags), id: \.self) { tag in
        TagChip(tag)
      }

      if item.tags.count > maxVisibleTags {
        TagChip("+\(item.tags.count - maxVisibleTags)")
      }
    }
  }
}

/// The list-view sibling of `ModuleCell` (library-v2 §1): one denser row per
/// module reusing the exact same data — verdict, name + purpose, `via <model>`
/// + provider mark, tags — flattened from the card. The trust verdict
/// (`ModuleCellState`) and the provenance value (`BrowseProvenance`) are passed
/// in already-resolved, so neither this row nor the card duplicates that logic.
///
/// The grid's 2×-wide hero does not exist here (library-v2 §1 LOCKED): rows
/// are usage-sorted, so the most-used module is simply the group's first row,
/// carrying only a faint `MOST USED` text marker — never extra height or color.
struct ModuleRow: View {
  let item: BrowseItem
  let state: ModuleCellState
  let provenance: BrowseProvenance?
  /// The group's usage-ranked lead row gets the quiet `MOST USED` marker
  /// (the flattened hero — library-v2 §1).
  let isMostUsed: Bool
  let isSelected: Bool
  /// Freshly created by the run that just completed (ux §4.4): shares the
  /// selection ring vocabulary for a beat, then decays — identical to the grid.
  let isArrived: Bool
  let onSelect: () -> Void

  @State private var isHovering = false

  /// library-v2 §1 row anatomy.
  private static let verdictColumnWidth: CGFloat = 142
  private static let providerMarkSize: CGFloat = 20
  /// Inset amber left rail on a needs-approval row (library-v2 §1: 3pt).
  private static let attentionRailWidth: CGFloat = 3
  /// Selection / arrival ring (library-v2 §1: inset 1.5pt green).
  private static let ringWidth: CGFloat = 1.5
  /// *Not in toolbox* dims the whole row; hover restores it (library-v2 §1).
  private static let dimmedOpacity: Double = 0.46
  /// Persistent faint amber wash on a needs-approval row, warmer on hover.
  private static let attentionWashOpacity: Double = 0.06
  private static let attentionWashHoverOpacity: Double = 0.11
  /// Tags shown inline before overflowing to `+N` (denser than the card).
  private static let maxVisibleTags = 3
  /// The `MOST USED` micro-label is the one sanctioned mono exception
  /// (library-v2 §1 watch-item: 9.5px uppercase, faint).
  private static let mostUsedFont = BrandTypography.monospaced(size: 9.5, weight: .semibold)

  private var showsRing: Bool {
    isSelected || isArrived
  }

  var body: some View {
    HStack(alignment: .center, spacing: BrandMetrics.Spacing.md) {
      verdict
        .frame(width: Self.verdictColumnWidth, alignment: .leading)

      nameAndPurpose
        .frame(maxWidth: .infinity, alignment: .leading)

      if let provenance {
        provenanceView(provenance)
      }

      if !item.tags.isEmpty {
        tagRow
      }
    }
    .padding(.horizontal, BrandMetrics.Spacing.lg)
    .padding(.vertical, BrandMetrics.Spacing.md)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(rowBackground)
    .overlay(alignment: .leading) {
      // Inset amber left rail for the needs-approval row. The selection /
      // arrival ring wins while present so two accents never compete.
      if state == .needsApproval, !showsRing {
        Rectangle()
          .fill(BrandColors.warning)
          .frame(width: Self.attentionRailWidth)
          .allowsHitTesting(false)
      }
    }
    .overlay {
      if showsRing {
        Rectangle()
          .strokeBorder(BrandColors.accent, lineWidth: Self.ringWidth)
          .allowsHitTesting(false)
      }
    }
    .opacity(state == .notInToolbox && !isHovering ? Self.dimmedOpacity : 1)
    .contentShape(Rectangle())
    .onTapGesture(perform: onSelect)
    .onHover { hovering in
      withAnimation(BrandMotion.quick) {
        isHovering = hovering
      }
    }
    .animation(BrandMotion.quick, value: isSelected)
    .animation(BrandMotion.smooth, value: isArrived)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(item.gunk.name), \(state.label)")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var verdict: some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      Circle()
        .fill(state.color)
        .frame(width: BrandMetrics.Spacing.sm, height: BrandMetrics.Spacing.sm)

      Text(state.label)
        .font(BrandTypography.callout.weight(.semibold))
        .foregroundStyle(state.color)
        .lineLimit(1)
    }
  }

  private var nameAndPurpose: some View {
    VStack(alignment: .leading, spacing: BrandMetrics.Spacing.xs / 2) {
      HStack(alignment: .firstTextBaseline, spacing: BrandMetrics.Spacing.sm) {
        Text(item.gunk.name)
          .font(BrandTypography.headline)
          .foregroundStyle(BrandColors.textPrimary)
          .lineLimit(1)
          .truncationMode(.tail)

        if isMostUsed {
          Text("MOST USED")
            .font(Self.mostUsedFont)
            .tracking(0.5)
            .foregroundStyle(BrandColors.textTertiary)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("Most used")
        }
      }

      if let purpose = item.gunk.purpose {
        Text(purpose)
          .font(BrandTypography.body)
          .foregroundStyle(BrandColors.textSecondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
  }

  private func provenanceView(_ provenance: BrowseProvenance) -> some View {
    HStack(spacing: BrandMetrics.Spacing.sm) {
      ProviderMark(provider: provenance.provider, size: Self.providerMarkSize)

      Text("via \(provenance.model)")
        .font(BrandTypography.caption)
        .foregroundStyle(BrandColors.textTertiary)
        .lineLimit(1)
        .fixedSize()
    }
  }

  private var tagRow: some View {
    HStack(spacing: BrandMetrics.Spacing.xs) {
      ForEach(item.tags.prefix(Self.maxVisibleTags), id: \.self) { tag in
        TagChip(tag)
      }

      if item.tags.count > Self.maxVisibleTags {
        TagChip("+\(item.tags.count - Self.maxVisibleTags)")
      }
    }
    .fixedSize()
  }

  @ViewBuilder
  private var rowBackground: some View {
    if showsRing {
      // Selection / arrival reuses the grid's `--surface-hi` fill.
      BrandColors.backgroundElevatedHover
    } else if state == .needsApproval {
      BrandColors.warning.opacity(
        isHovering ? Self.attentionWashHoverOpacity : Self.attentionWashOpacity
      )
    } else if isHovering {
      BrandColors.backgroundElevatedHover
    } else {
      Color.clear
    }
  }
}
