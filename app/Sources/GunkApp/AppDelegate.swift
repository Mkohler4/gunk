import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var menubarController: MenubarController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.mainMenu = MainMenuFactory.makeMainMenu()

    menubarController = MenubarController {
      MainWindowController.shared.showMainWindow()
    }

    MainWindowController.shared.showMainWindow()
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    MainWindowController.shared.showMainWindow()
    return false
  }

  func application(
    _ application: NSApplication,
    shouldSaveApplicationState coder: NSCoder
  ) -> Bool {
    false
  }

  func application(
    _ application: NSApplication,
    shouldRestoreApplicationState coder: NSCoder
  ) -> Bool {
    false
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    AppRuntime.shared.handleOpenURLs(urls)
    MainWindowController.shared.showMainWindow()
  }
}
