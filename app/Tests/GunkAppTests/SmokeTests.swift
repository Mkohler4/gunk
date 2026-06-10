import AppKit
import XCTest
@testable import GunkApp

@MainActor
final class SmokeTests: XCTestCase {
  func testAppDelegateInitializes() {
    let delegate = AppDelegate()

    XCTAssertNotNil(delegate)
  }

  func testAppDelegateDisablesWindowRestoration() {
    let delegate = AppDelegate()

    XCTAssertFalse(delegate.application(NSApplication.shared, shouldSaveApplicationState: NSCoder()))
    XCTAssertFalse(delegate.application(NSApplication.shared, shouldRestoreApplicationState: NSCoder()))
  }
}
