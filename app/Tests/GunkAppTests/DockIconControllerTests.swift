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

  /// B2 regression: a run beginning from a badged idle state must never flash
  /// the stale idle count on the processing icon. The old call site applied
  /// `setState(.processing)` (rendering the new icon with the previous badge
  /// still attached) and only then `badge(count:)`, so the badge label was
  /// applied twice — "12" then nil. The atomic `transition(to:badgeCount:)`
  /// applies it once.
  func testRunBeginDoesNotFlashStaleIdleBadge() {
    let applicator = RecordingDockIconApplicator()
    let controller = DockIconController(applicator: applicator)
    let model = ProcessingModel(dockIconController: controller, gunkCount: { 12 })

    model.refreshIdleDockState() // idle: full + "12"
    XCTAssertEqual(applicator.badgeLabel, "12")
    applicator.resetHistory()

    model.begin(sourceId: 1) // a run starts, 0 modules found so far

    // No stale "12" on the way to the cleared processing badge — exactly one
    // badge apply, straight to nil.
    XCTAssertEqual(applicator.badgeLabelHistory, [nil])
    XCTAssertEqual(controller.currentDescriptor.assetName, "DockBinProcessing")
    XCTAssertNil(applicator.badgeLabel)
  }

  /// B2 regression: every apply forces a Dock-tile redraw so the badge can't
  /// lag the icon during the processing/feedback transitions.
  func testEachApplyForcesDockTileRedraw() {
    let applicator = RecordingDockIconApplicator()
    let controller = DockIconController(applicator: applicator)

    let before = applicator.displayCount
    controller.transition(to: .processing, badgeCount: 3)

    XCTAssertEqual(applicator.displayCount, before + 1)
  }
}

@MainActor
private final class RecordingDockIconApplicator: DockIconApplying {
  private(set) var applicationIconImage: NSImage?
  private(set) var badgeLabel: String?
  /// Every badge label applied since the last reset, in order — so a test can
  /// catch a stale intermediate, not just the final value.
  private(set) var badgeLabelHistory: [String?] = []
  private(set) var displayCount = 0

  func setApplicationIconImage(_ image: NSImage?) {
    applicationIconImage = image
  }

  func setBadgeLabel(_ label: String?) {
    badgeLabel = label
    badgeLabelHistory.append(label)
  }

  func displayDockTile() {
    displayCount += 1
  }

  func resetHistory() {
    badgeLabelHistory.removeAll()
  }
}
