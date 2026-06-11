import AppKit

@main
enum GunkAppMain {
  @MainActor
  static func main() {
    // Dev-only (T-7.5): GUNK_RENDER_APPICON=<dir> / GUNK_RENDER_DOCKBIN=<dir>
    // render the icon and Dock-bin PNGs and exit without starting the UI
    // (see `make icon`).
    let renderedAppIcon = AppIconExporter.runIfRequested()
    let renderedDockBins = DockBinExporter.runIfRequested()
    if renderedAppIcon || renderedDockBins {
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
