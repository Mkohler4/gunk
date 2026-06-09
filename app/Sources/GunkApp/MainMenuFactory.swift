import AppKit

@MainActor
enum MainMenuFactory {
  static func makeMainMenu() -> NSMenu {
    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    appMenuItem.submenu = makeAppMenu()

    let fileMenuItem = NSMenuItem()
    mainMenu.addItem(fileMenuItem)
    fileMenuItem.submenu = makeFileMenu()

    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    editMenuItem.submenu = makeEditMenu()

    let windowMenuItem = NSMenuItem()
    mainMenu.addItem(windowMenuItem)
    let windowMenu = makeWindowMenu()
    windowMenuItem.submenu = windowMenu
    NSApplication.shared.windowsMenu = windowMenu

    return mainMenu
  }

  private static func makeAppMenu() -> NSMenu {
    let appMenu = NSMenu(title: "gunk")
    appMenu.addItem(
      withTitle: "About gunk",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: ""
    )
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(
      withTitle: "Hide gunk",
      action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h"
    )
    let hideOthers = appMenu.addItem(
      withTitle: "Hide Others",
      action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h"
    )
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(
      withTitle: "Show All",
      action: #selector(NSApplication.unhideAllApplications(_:)),
      keyEquivalent: ""
    )
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(
      withTitle: "Quit gunk",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    return appMenu
  }

  private static func makeFileMenu() -> NSMenu {
    let fileMenu = NSMenu(title: "File")
    let openItem = fileMenu.addItem(
      withTitle: "Open gunk",
      action: #selector(MainWindowController.showMainWindow(_:)),
      keyEquivalent: "0"
    )
    openItem.target = MainWindowController.shared
    return fileMenu
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

  private static func makeWindowMenu() -> NSMenu {
    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(
      withTitle: "Minimize",
      action: #selector(NSWindow.performMiniaturize(_:)),
      keyEquivalent: "m"
    )
    windowMenu.addItem(
      withTitle: "Zoom",
      action: #selector(NSWindow.performZoom(_:)),
      keyEquivalent: ""
    )
    windowMenu.addItem(NSMenuItem.separator())

    let showItem = windowMenu.addItem(
      withTitle: "Show gunk",
      action: #selector(MainWindowController.showMainWindow(_:)),
      keyEquivalent: "1"
    )
    showItem.target = MainWindowController.shared

    windowMenu.addItem(
      withTitle: "Bring All to Front",
      action: #selector(NSApplication.arrangeInFront(_:)),
      keyEquivalent: ""
    )

    return windowMenu
  }
}
