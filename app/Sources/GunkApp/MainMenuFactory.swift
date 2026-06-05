import AppKit

enum MainMenuFactory {
  static func makeMainMenu() -> NSMenu {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    appMenuItem.submenu = makeAppMenu()

    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    editMenuItem.submenu = makeEditMenu()

    return mainMenu
  }

  private static func makeAppMenu() -> NSMenu {
    let appMenu = NSMenu(title: "gunk")
    appMenu.addItem(
      withTitle: "Quit gunk",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    return appMenu
  }

  private static func makeEditMenu() -> NSMenu {
    let editMenu = NSMenu(title: "Edit")

    editMenu.addItem(
      withTitle: "Cut",
      action: #selector(NSText.cut(_:)),
      keyEquivalent: "x"
    )
    editMenu.addItem(
      withTitle: "Copy",
      action: #selector(NSText.copy(_:)),
      keyEquivalent: "c"
    )
    editMenu.addItem(
      withTitle: "Paste",
      action: #selector(NSText.paste(_:)),
      keyEquivalent: "v"
    )
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(
      withTitle: "Select All",
      action: #selector(NSText.selectAll(_:)),
      keyEquivalent: "a"
    )

    return editMenu
  }
}
