import AppKit

@MainActor
protocol DockIconApplying: AnyObject {
  func setApplicationIconImage(_ image: NSImage?)
  func setBadgeLabel(_ label: String?)
  /// Forces the Dock tile to redraw now (B2): setting `badgeLabel` /
  /// `applicationIconImage` does not reliably repaint the on-screen badge
  /// during the rapid processing→feedback transitions, so each apply ends
  /// with an explicit `display()`.
  func displayDockTile()
}

@MainActor
final class ApplicationDockIconApplicator: DockIconApplying {
  private let application: NSApplication

  init(application: NSApplication) {
    self.application = application
  }

  func setApplicationIconImage(_ image: NSImage?) {
    application.applicationIconImage = image
  }

  func setBadgeLabel(_ label: String?) {
    application.dockTile.badgeLabel = label
  }

  func displayDockTile() {
    application.dockTile.display()
  }
}

@MainActor
final class DockIconController {
  enum State {
    case empty
    case full
    case processing

    var assetName: String {
      switch self {
      case .empty:
        return "DockBinEmpty"
      case .full:
        return "DockBinFull"
      case .processing:
        return "DockBinProcessing"
      }
    }

    var assetFilename: String {
      switch self {
      case .empty:
        return "dock-bin-empty"
      case .full:
        return "dock-bin-full"
      case .processing:
        return "dock-bin-processing"
      }
    }
  }

  struct Descriptor: Equatable {
    let assetName: String
    let badgeLabel: String?
  }

  private let applicator: DockIconApplying
  private let bundle: Bundle
  private var badgeCount = 0

  private(set) var state: State
  private(set) var currentDescriptor: Descriptor

  convenience init(
    initialState: State = .empty,
    bundle: Bundle = .module
  ) {
    self.init(
      initialState: initialState,
      applicator: ApplicationDockIconApplicator(application: .shared),
      bundle: bundle
    )
  }

  init(
    initialState: State = .empty,
    applicator: DockIconApplying,
    bundle: Bundle = .module
  ) {
    self.state = initialState
    self.applicator = applicator
    self.bundle = bundle
    self.currentDescriptor = DockIconController.descriptor(
      state: initialState,
      badgeCount: 0
    )

    applyCurrentState()
  }

  func setState(_ state: State) {
    self.state = state
    applyCurrentState()
  }

  func badge(count: Int) {
    badgeCount = max(0, count)
    applyCurrentState()
  }

  /// Applies a new icon state **and** badge in a single render pass (B2 fix).
  ///
  /// The processing/feedback call sites used to call `setState(_:)` then
  /// `badge(count:)` — two separate `applyCurrentState()` passes. At the start
  /// of a run the first pass rendered the new **processing** icon while the
  /// badge still held the **previous idle count**, so a stale count flashed on
  /// the processing icon for one pass before the second pass cleared it.
  /// Setting both before a single apply removes that intermediate.
  func transition(to state: State, badgeCount count: Int) {
    self.state = state
    badgeCount = max(0, count)
    applyCurrentState()
  }

  func reflectGunkCount(_ count: Int) {
    state = count > 0 ? .full : .empty
    badgeCount = max(0, count)
    applyCurrentState()
  }

  static func descriptor(state: State, badgeCount: Int) -> Descriptor {
    // The Dock badge (the red count indicator) is intentionally disabled: the
    // icon state alone (empty/full/processing) communicates status without a
    // notification badge. `badgeCount` is still tracked for state logic but
    // never surfaces as a badge label.
    Descriptor(
      assetName: state.assetName,
      badgeLabel: nil
    )
  }

  private func applyCurrentState() {
    currentDescriptor = DockIconController.descriptor(
      state: state,
      badgeCount: badgeCount
    )

    applicator.setApplicationIconImage(image(for: state))
    applicator.setBadgeLabel(currentDescriptor.badgeLabel)
    // Force the redraw so the badge never lags the icon during the rapid
    // begin → moduleFound → complete transitions (B2).
    applicator.displayDockTile()
  }

  private func image(for state: State) -> NSImage? {
    if let image = bundle.image(forResource: NSImage.Name(state.assetName)) {
      return image
    }

    if let url = bundle.url(
      forResource: state.assetFilename,
      withExtension: "png",
      subdirectory: "Assets.xcassets/\(state.assetName).imageset"
    ), let image = NSImage(contentsOf: url) {
      return image
    }

    return fallbackImage(for: state)
  }

  private func fallbackImage(for state: State) -> NSImage {
    let size = NSSize(width: 512, height: 512)
    let image = NSImage(size: size)

    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()

    let stroke: NSColor
    let fill: NSColor
    switch state {
    case .empty:
      stroke = NSColor.systemGray
      fill = NSColor.systemGray.withAlphaComponent(0.12)
    case .full:
      stroke = NSColor.systemGreen
      fill = NSColor.systemGreen.withAlphaComponent(0.32)
    case .processing:
      stroke = NSColor.systemBlue
      fill = NSColor.systemBlue.withAlphaComponent(0.24)
    }

    let body = NSBezierPath(
      roundedRect: NSRect(x: 128, y: 96, width: 256, height: 288),
      xRadius: 24,
      yRadius: 24
    )
    fill.setFill()
    body.fill()
    stroke.setStroke()
    body.lineWidth = 28
    body.stroke()

    let lid = NSBezierPath(
      roundedRect: NSRect(x: 104, y: 384, width: 304, height: 42),
      xRadius: 16,
      yRadius: 16
    )
    stroke.setFill()
    lid.fill()

    if state == .processing {
      let ring = NSBezierPath(ovalIn: NSRect(x: 192, y: 184, width: 128, height: 128))
      NSColor.white.withAlphaComponent(0.85).setStroke()
      ring.lineWidth = 22
      ring.stroke()
    }

    return image
  }
}
