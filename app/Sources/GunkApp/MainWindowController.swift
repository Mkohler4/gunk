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
    // Default first-launch frame per ux §4.6; the autosave name set in
    // `register` keeps the user's last size on subsequent launches.
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )

    window.contentViewController = hostingController
    window.center()
    register(window: window)
    hostedWindow = window
    window.makeKeyAndOrderFront(nil)
  }
}
