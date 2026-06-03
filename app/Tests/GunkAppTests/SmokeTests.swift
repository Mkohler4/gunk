import XCTest
@testable import GunkApp

@MainActor
final class SmokeTests: XCTestCase {
  func testAppDelegateInitializes() {
    let delegate = AppDelegate()

    XCTAssertNotNil(delegate)
  }
}
