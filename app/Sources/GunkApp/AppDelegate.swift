import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var dockIconController: DockIconController?
  private var menubarController: MenubarController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)

    do {
      let store = try Store(path: Store.defaultURL)
      let dockIconController = DockIconController()
      dockIconController.reflectGunkCount(try store.listGunks().count)

      self.dockIconController = dockIconController
      menubarController = MenubarController(store: store)
    } catch {
      NSApp.presentError(error)
    }
  }
}
