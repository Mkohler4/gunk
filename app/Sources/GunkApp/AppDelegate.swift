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

    // Dev-only (T-7.4): with GUNK_DESIGN_GALLERY=1 the gallery opens at
    // launch so the CP2 surface is one step away. No-op in normal launches.
    if ComponentGalleryLauncher.isEnabled {
      ComponentGalleryLauncher.shared.showGallery()
    }
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
