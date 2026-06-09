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
    XCTAssertEqual(model.sourceStatuses[42], .processing)
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
    XCTAssertEqual(model.sourceStatuses[42], .complete)
    XCTAssertTrue(model.progressBySource.isEmpty)
    XCTAssertEqual(model.modulesFound, 0)
    XCTAssertEqual(dockIconController.state, .full)
    XCTAssertEqual(applicator.badgeLabel, "3")

    finalGunkCount = 0
    model.refreshIdleDockState()

    XCTAssertEqual(dockIconController.state, .empty)
    XCTAssertNil(applicator.badgeLabel)
  }

  @MainActor
  func testSourceImportStatusTransitions() {
    let model = ProcessingModel(
      dockIconController: DockIconController(applicator: RecordingDockIconApplicator()),
      gunkCount: { 0 }
    )
    let source = Source(
      id: 7,
      name: "fixture",
      path: "/tmp/fixture",
      droppedAt: 100,
      removedAt: nil
    )

    XCTAssertEqual(model.status(for: source), .complete)

    model.queue(sourceId: source.id)

    XCTAssertEqual(model.status(for: source), .queued)
    XCTAssertNil(model.progress(for: source))
    XCTAssertNil(model.error(for: source))

    model.begin(sourceId: source.id)
    model.update(sourceId: source.id, progress: 1.4)

    XCTAssertEqual(model.status(for: source), .processing)
    XCTAssertEqual(model.progress(for: source), 1)

    model.complete(sourceId: source.id)

    XCTAssertEqual(model.status(for: source), .complete)
    XCTAssertNil(model.progress(for: source))
    XCTAssertNil(model.error(for: source))
  }

  @MainActor
  func testFailedSourceTracksErrorMessage() {
    let model = ProcessingModel(
      dockIconController: DockIconController(applicator: RecordingDockIconApplicator()),
      gunkCount: { 0 }
    )
    let source = Source(
      id: 9,
      name: "fixture",
      path: "/tmp/fixture",
      droppedAt: 100,
      removedAt: nil
    )

    model.begin(sourceId: source.id)
    model.fail(sourceId: source.id, error: TestError(message: "No API key configured."))

    XCTAssertEqual(model.status(for: source), .failed)
    XCTAssertEqual(model.error(for: source), "No API key configured.")
    XCTAssertNil(model.progress(for: source))
    XCTAssertFalse(model.isProcessing)
  }
}

private struct TestError: LocalizedError {
  let message: String

  var errorDescription: String? {
    message
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
