import AppKit
import XCTest
@testable import GunkApp

@MainActor
final class DockIconControllerTests: XCTestCase {
  func testEmptyStateUsesEmptyAsset() {
    let applicator = RecordingDockIconApplicator()
    let controller = DockIconController(applicator: applicator)

    controller.setState(.empty)

    XCTAssertEqual(controller.currentDescriptor.assetName, "DockBinEmpty")
    XCTAssertNil(controller.currentDescriptor.badgeLabel)
    XCTAssertEqual(applicator.badgeLabel, nil)
    XCTAssertNotNil(applicator.applicationIconImage)
  }

  func testProcessingStateUsesProcessingAsset() {
    let controller = DockIconController(applicator: RecordingDockIconApplicator())

    controller.setState(.processing)

    XCTAssertEqual(controller.currentDescriptor.assetName, "DockBinProcessing")
  }

  func testBadgeReflectsGunkCount() {
    let applicator = RecordingDockIconApplicator()
    let controller = DockIconController(applicator: applicator)

    controller.reflectGunkCount(3)

    XCTAssertEqual(controller.state, .full)
    XCTAssertEqual(controller.currentDescriptor.assetName, "DockBinFull")
    XCTAssertEqual(controller.currentDescriptor.badgeLabel, "3")
    XCTAssertEqual(applicator.badgeLabel, "3")

    controller.reflectGunkCount(0)

    XCTAssertEqual(controller.state, .empty)
    XCTAssertEqual(controller.currentDescriptor.assetName, "DockBinEmpty")
    XCTAssertNil(controller.currentDescriptor.badgeLabel)
    XCTAssertNil(applicator.badgeLabel)
  }
}

@MainActor
private final class RecordingDockIconApplicator: DockIconApplying {
  private(set) var applicationIconImage: NSImage?
  private(set) var badgeLabel: String?

  func setApplicationIconImage(_ image: NSImage?) {
    applicationIconImage = image
  }

  func setBadgeLabel(_ label: String?) {
    badgeLabel = label
  }
}
