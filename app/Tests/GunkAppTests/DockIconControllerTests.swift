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

  /// The Dock badge is disabled: a non-zero gunk count still drives the icon
  /// state (`.full`) but never surfaces a red badge label.
  func testGunkCountDrivesStateWithoutBadge() {
    let applicator = RecordingDockIconApplicator()
    let controller = DockIconController(applicator: applicator)

    controller.reflectGunkCount(3)

    XCTAssertEqual(controller.state, .full)
    XCTAssertEqual(controller.currentDescriptor.assetName, "DockBinFull")
    XCTAssertNil(controller.currentDescriptor.badgeLabel)
    XCTAssertNil(applicator.badgeLabel)

    controller.reflectGunkCount(0)

    XCTAssertEqual(controller.state, .empty)
    XCTAssertEqual(controller.currentDescriptor.assetName, "DockBinEmpty")
    XCTAssertNil(controller.currentDescriptor.badgeLabel)
    XCTAssertNil(applicator.badgeLabel)
  }

  /// The Dock badge is disabled, so no count is ever applied — idle or
  /// processing. A run beginning from a populated idle state stays badge-free
  /// the whole way through (and renders the processing icon).
  func testRunBeginNeverAppliesABadge() {
    let applicator = RecordingDockIconApplicator()
    let controller = DockIconController(applicator: applicator)
    let model = ProcessingModel(dockIconController: controller, gunkCount: { 12 })

    model.refreshIdleDockState() // idle: full, no badge
    XCTAssertNil(applicator.badgeLabel)
    applicator.resetHistory()

    model.begin(sourceId: 1) // a run starts, 0 modules found so far

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
