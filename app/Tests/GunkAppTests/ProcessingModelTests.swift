import AppKit
import XCTest
@testable import GunkApp

final class ProcessingModelTests: XCTestCase {
  @MainActor
  func testProcessingModelTransitionsAndBadges() {
    var finalGunkCount = 3
    let applicator = RecordingDockIconApplicator()
    let dockIconController = DockIconController(applicator: applicator)
    let model = ProcessingModel(
      dockIconController: dockIconController,
      gunkCount: { finalGunkCount }
    )

    model.begin(sourceId: 42)

    XCTAssertTrue(model.isProcessing)
    XCTAssertEqual(model.progressBySource[42], 0)
    XCTAssertEqual(dockIconController.state, .processing)
    XCTAssertNil(applicator.badgeLabel)

    model.update(sourceId: 42, progress: 0.45, modulesFound: 2)

    XCTAssertEqual(model.progressBySource[42], 0.45)
    XCTAssertEqual(model.modulesFound, 2)
    XCTAssertEqual(dockIconController.state, .processing)
    XCTAssertEqual(applicator.badgeLabel, "2")

    model.moduleFound(sourceId: 42)

    XCTAssertEqual(model.modulesFound, 3)
    XCTAssertEqual(applicator.badgeLabel, "3")

    model.complete(sourceId: 42)

    XCTAssertFalse(model.isProcessing)
    XCTAssertTrue(model.progressBySource.isEmpty)
    XCTAssertEqual(model.modulesFound, 0)
    XCTAssertEqual(dockIconController.state, .full)
    XCTAssertEqual(applicator.badgeLabel, "3")

    finalGunkCount = 0
    model.refreshIdleDockState()

    XCTAssertEqual(dockIconController.state, .empty)
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
