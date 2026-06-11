import SwiftUI

/// The gunk brand mark — "the Ooze" — drawn natively from the approved
/// concept art (body path, 3D gradient, outline, sheen, and face).
///
/// This view is the single source for the mark: the app icon (T-7.5),
/// wordmark, launch view, and loading/empty states all build on it. When
/// `isAnimated` is true it plays the approved idle loop (breathe + blink)
/// using `BrandMotion.Mascot` timing; Reduce Motion renders a still frame.
struct BrandMark: View {
  var size: CGFloat = BrandMetrics.Mark.large
  var isAnimated: Bool = false

  var body: some View {
    Group {
      if isAnimated, !BrandMotion.reduceMotion {
        TimelineView(.animation) { timeline in
          canvas(time: timeline.date.timeIntervalSinceReferenceDate)
        }
      } else {
        canvas(time: nil)
      }
    }
    .frame(width: size, height: size)
    .accessibilityLabel("gunk")
  }

  // MARK: Drawing

  /// The mark is designed on a 100×100 canvas; everything below is in those
  /// design units and scaled to the rendered size.
  private static let designSize: CGFloat = 100
  /// Breathe/squash pivot — the mascot's "feet" (50, 84) from the spec.
  private static let pivot = CGPoint(x: 50, y: 84)

  private func canvas(time: TimeInterval?) -> some View {
    Canvas { context, canvasSize in
      let scale = min(canvasSize.width, canvasSize.height) / Self.designSize
      context.scaleBy(x: scale, y: scale)

      if let time {
        applyBreathe(at: time, to: &context)
      }

      let body = Self.bodyPath
      context.fill(body, with: .linearGradient(
        Gradient(stops: [
          .init(color: BrandColors.Mark.gradientTop, location: 0),
          .init(color: BrandColors.Mark.gradientMid, location: 0.42),
          .init(color: BrandColors.Mark.gradientBottom, location: 1),
        ]),
        startPoint: CGPoint(x: 20, y: 8),
        endPoint: CGPoint(x: 82, y: 94)
      ))
      context.stroke(
        body,
        with: .color(BrandColors.Mark.outline),
        style: StrokeStyle(lineWidth: BrandMetrics.Mark.outlineWidth, lineJoin: .round)
      )

      // Top-left sheen, clipped to the body.
      context.drawLayer { layer in
        layer.clip(to: body)
        layer.fill(
          Path(ellipseIn: CGRect(x: 46 - 26, y: 30 - 18, width: 52, height: 36)),
          with: .color(.white.opacity(0.24))
        )
      }

      let blink = time.map(blinkAmount(at:)) ?? 1
      face(in: &context, blink: blink)
    }
  }

  private func face(in context: inout GraphicsContext, blink: CGFloat) {
    func eye(cx: CGFloat, cy: CGFloat) {
      let ry = 6.5 * blink
      context.fill(
        Path(ellipseIn: CGRect(x: cx - 5, y: cy - ry, width: 10, height: ry * 2)),
        with: .color(BrandColors.Mark.face)
      )
    }
    eye(cx: 45, cy: 38)
    eye(cx: 62, cy: 36)
    context.fill(
      Path(ellipseIn: CGRect(x: 54 - 3, y: 50 - 4, width: 6, height: 8)),
      with: .color(BrandColors.Mark.face)
    )
  }

  // MARK: Idle loop (BrandMotion.Mascot spec)

  private func applyBreathe(at time: TimeInterval, to context: inout GraphicsContext) {
    let phase = time * (2 * .pi / BrandMotion.Mascot.breatheDuration)
    let wave = CGFloat(sin(phase))
    let scaleY = 1 + BrandMotion.Mascot.breatheScaleY * wave
    let scaleX = 1 - BrandMotion.Mascot.breatheScaleX * wave
    let lift = BrandMotion.Mascot.breatheLift * max(0, wave)

    context.translateBy(x: Self.pivot.x, y: Self.pivot.y - lift)
    context.scaleBy(x: scaleX, y: scaleY)
    context.translateBy(x: -Self.pivot.x, y: -Self.pivot.y)
  }

  /// 1 = eyes open; dips toward `blinkMinimum` once per `blinkCycle`.
  private func blinkAmount(at time: TimeInterval) -> CGFloat {
    let cycle = time.truncatingRemainder(dividingBy: BrandMotion.Mascot.blinkCycle)
    let blinkStart = BrandMotion.Mascot.blinkCycle - BrandMotion.Mascot.blinkDuration
    guard cycle > blinkStart else { return 1 }
    let progress = (cycle - blinkStart) / BrandMotion.Mascot.blinkDuration
    let amount = 1 - CGFloat(sin(progress * .pi))
    return max(BrandMotion.Mascot.blinkMinimum, amount)
  }

  // MARK: Geometry

  /// The Ooze body in 100×100 design units, from the approved concept SVG.
  static var bodyPath: Path {
    var path = Path()
    path.move(to: CGPoint(x: 56, y: 8))
    path.addCurve(
      to: CGPoint(x: 90, y: 42),
      control1: CGPoint(x: 77, y: 8),
      control2: CGPoint(x: 90, y: 22)
    )
    path.addCurve(
      to: CGPoint(x: 64, y: 80),
      control1: CGPoint(x: 90, y: 58),
      control2: CGPoint(x: 82, y: 72)
    )
    path.addCurve(
      to: CGPoint(x: 36, y: 83),
      control1: CGPoint(x: 54, y: 84),
      control2: CGPoint(x: 44, y: 85)
    )
    path.addCurve(
      to: CGPoint(x: 16, y: 67),
      control1: CGPoint(x: 26, y: 80),
      control2: CGPoint(x: 18, y: 76)
    )
    path.addCurve(
      to: CGPoint(x: 14, y: 44),
      control1: CGPoint(x: 14, y: 60),
      control2: CGPoint(x: 13, y: 52)
    )
    path.addCurve(
      to: CGPoint(x: 56, y: 8),
      control1: CGPoint(x: 16, y: 24),
      control2: CGPoint(x: 35, y: 8)
    )
    path.closeSubpath()
    return path
  }
}

/// The Ooze body outline as a `Shape`, for app-icon tiles, clip shapes, and
/// flat single-color renders (favicon / menubar template style).
struct BrandMarkShape: Shape {
  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / 100
    return BrandMark.bodyPath.applying(
      CGAffineTransform(scaleX: scale, y: scale)
        .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    )
  }
}

#Preview("Brand mark — sizes") {
  HStack(alignment: .bottom, spacing: BrandMetrics.Spacing.xl) {
    BrandMark(size: BrandMetrics.Mark.hero)
    BrandMark(size: BrandMetrics.Mark.large)
    BrandMark(size: BrandMetrics.Mark.medium)
    BrandMark(size: BrandMetrics.Mark.small)
  }
  .padding(BrandMetrics.Spacing.xl)
  .background(BrandColors.backgroundPrimary)
  .preferredColorScheme(.dark)
}

#Preview("Brand mark — alive") {
  VStack(spacing: BrandMetrics.Spacing.lg) {
    BrandMark(size: BrandMetrics.Mark.hero, isAnimated: true)
    Text("breathes every \(BrandMotion.Mascot.breatheDuration, specifier: "%.1f")s · blinks every \(BrandMotion.Mascot.blinkCycle, specifier: "%.0f")s")
      .font(BrandTypography.caption)
      .foregroundStyle(BrandColors.textTertiary)
  }
  .padding(BrandMetrics.Spacing.xl)
  .frame(width: 320, height: 280)
  .background(BrandColors.backgroundPrimary)
  .preferredColorScheme(.dark)
}
