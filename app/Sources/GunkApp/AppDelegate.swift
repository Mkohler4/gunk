import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var menubarController: MenubarController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    menubarController = MenubarController()
  }
}
