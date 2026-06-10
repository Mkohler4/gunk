import AppKit
import XCTest
@testable import GunkApp

@MainActor
final class MainMenuFactoryTests: XCTestCase {
  func testMainMenuIncludesStandardEditCommands() {
    let menu = MainMenuFactory.makeMainMenu()
    let editMenu = menu.items.first { $0.submenu?.title == "Edit" }?.submenu

    XCTAssertNotNil(editMenu)
    XCTAssertNotNil(item(title: "Cut", keyEquivalent: "x", in: editMenu))
    XCTAssertNotNil(item(title: "Copy", keyEquivalent: "c", in: editMenu))
    XCTAssertNotNil(item(title: "Paste", keyEquivalent: "v", in: editMenu))
    XCTAssertNotNil(item(title: "Select All", keyEquivalent: "a", in: editMenu))
  }

  func testMainMenuIncludesWindowAndLaunchCommands() {
    let menu = MainMenuFactory.makeMainMenu()
    let fileMenu = menu.items.first { $0.submenu?.title == "File" }?.submenu
    let windowMenu = menu.items.first { $0.submenu?.title == "Window" }?.submenu

    let openItem = item(title: "Open gunk", keyEquivalent: "0", in: fileMenu)
    XCTAssertNotNil(openItem)
    XCTAssertTrue(openItem?.target === MainWindowController.shared)

    let showItem = item(title: "Show gunk", keyEquivalent: "1", in: windowMenu)
    XCTAssertNotNil(showItem)
    XCTAssertTrue(showItem?.target === MainWindowController.shared)

    XCTAssertNotNil(item(title: "Minimize", keyEquivalent: "m", in: windowMenu))
    XCTAssertNotNil(item(title: "Bring All to Front", keyEquivalent: "", in: windowMenu))
  }

  private func item(
    title: String,
    keyEquivalent: String,
    in menu: NSMenu?
  ) -> NSMenuItem? {
    menu?.items.first {
      $0.title == title && $0.keyEquivalent == keyEquivalent
    }
  }
}
