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
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
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
