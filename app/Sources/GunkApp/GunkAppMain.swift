import AppKit

@main
enum GunkAppMain {
  @MainActor
  static func main() {
    // Dev-only (T-7.5): GUNK_RENDER_APPICON=<dir> renders the app-icon PNGs
    // and exits without starting the UI (see `make icon`).
    if AppIconExporter.runIfRequested() {
      return
    }

    let application = NSApplication.shared
    let delegate = AppDelegate()

    application.delegate = delegate
    application.mainMenu = MainMenuFactory.makeMainMenu()
    application.setActivationPolicy(.regular)
    application.run()
  }
}
