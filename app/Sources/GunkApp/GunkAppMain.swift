import AppKit

@main
enum GunkAppMain {
  @MainActor
  static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()

    application.delegate = delegate
    application.mainMenu = MainMenuFactory.makeMainMenu()
    application.setActivationPolicy(.regular)
    application.run()
  }
}
