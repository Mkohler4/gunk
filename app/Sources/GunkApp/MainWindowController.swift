import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject {
  static let shared = MainWindowController()
  static let mainWindowID = "main"

  private weak var mainWindow: NSWindow?
  private var hostedWindow: NSWindow?

  func register(window: NSWindow) {
    mainWindow = window
    window.identifier = NSUserInterfaceItemIdentifier(Self.mainWindowID)
    // D13: the window title is always the product, never the section. The
    // shell hides the in-toolbar title text (the sidebar wordmark already
    // reads "gunk"); this still names the window for Mission Control/⌘-Tab.
    window.title = "gunk"
    window.isRestorable = false
    window.setFrameAutosaveName("gunk-main-window")
  }

  @objc
  func showMainWindow(_ sender: Any? = nil) {
    showMainWindow()
  }

  func showMainWindow() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    if focusMainWindow() {
      return
    }

    makeHostedMainWindow()
  }

  @discardableResult
  private func focusMainWindow() -> Bool {
    if let mainWindow {
      mainWindow.makeKeyAndOrderFront(nil)
      return true
    }

    if let window = NSApp.windows.first(where: { window in
      window.identifier?.rawValue == Self.mainWindowID
        || window.title == "gunk"
    }) {
      register(window: window)
      window.makeKeyAndOrderFront(nil)
      return true
    }

    return false
  }

  private func makeHostedMainWindow() {
    let hostingController = NSHostingController(
      rootView: AppLaunchView(runtime: AppRuntime.shared)
    )
    // Let SwiftUI drive *only* the minimum size from `AppLaunchView`'s
    // `.frame(minWidth:minHeight:)`. `.minSize` enforces the floor while
    // leaving the ceiling open, so the window stays freely resizable upward —
    // the page's own dead-margin cap was the real "not resizable" bug, not this.
    // The default `.preferredContentSize` would instead pin the window to the
    // view's ideal size; an empty set drops the minimum entirely.
    hostingController.sizingOptions = [.minSize]
    // Default first-launch frame per ux §4.6; the autosave name set in
    // `register` keeps the user's last size on subsequent launches.
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )

    window.contentViewController = hostingController
    // Enforce the floor at the window level (AppKit, not SwiftUI); the ceiling
    // is left at AppKit's default (unbounded) so the page resizes freely up to
    // the display.
    window.contentMinSize = NSSize(width: 960, height: 600)
    // Enable native full-screen (the green button → fill the screen) and let
    // the window zoom to the full visible frame.
    window.collectionBehavior.insert(.fullScreenPrimary)
    window.center()
    register(window: window)
    hostedWindow = window
    window.makeKeyAndOrderFront(nil)
  }
}
