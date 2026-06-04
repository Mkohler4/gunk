import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var menubarController: MenubarController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    do {
      let store = try Store(path: Store.defaultURL)
      menubarController = MenubarController(store: store)
    } catch {
      NSApp.presentError(error)
    }
  }
}
