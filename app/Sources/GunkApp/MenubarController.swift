import AppKit

@MainActor
final class MenubarController {
  private let statusItem: NSStatusItem
  private let openMainWindow: () -> Void

  init(openMainWindow: @escaping () -> Void) {
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.openMainWindow = openMainWindow

    configureStatusItem()
  }

  private func configureStatusItem() {
    guard let button = statusItem.button else {
      return
    }

    button.title = "G"
    button.toolTip = "Open gunk"
    button.target = self
    button.action = #selector(openWindow)
  }

  @objc
  private func openWindow() {
    openMainWindow()
  }
}
