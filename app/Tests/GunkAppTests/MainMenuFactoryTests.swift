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
