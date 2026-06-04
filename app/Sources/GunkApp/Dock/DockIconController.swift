import AppKit

@MainActor
protocol DockIconApplying: AnyObject {
  func setApplicationIconImage(_ image: NSImage?)
  func setBadgeLabel(_ label: String?)
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

  func reflectGunkCount(_ count: Int) {
    state = count > 0 ? .full : .empty
    badgeCount = max(0, count)
    applyCurrentState()
  }

  static func descriptor(state: State, badgeCount: Int) -> Descriptor {
    Descriptor(
      assetName: state.assetName,
      badgeLabel: badgeCount > 0 ? String(badgeCount) : nil
    )
  }

  private func applyCurrentState() {
    currentDescriptor = DockIconController.descriptor(
      state: state,
      badgeCount: badgeCount
    )

    applicator.setApplicationIconImage(image(for: state))
    applicator.setBadgeLabel(currentDescriptor.badgeLabel)
  }

  private func image(for state: State) -> NSImage? {
    if let image = bundle.image(forResource: NSImage.Name(state.assetName)) {
      return image
    }

    if let url = bundle.url(
      forResource: state.assetFilename,
      withExtension: "svg",
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
