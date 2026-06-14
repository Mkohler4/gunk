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
