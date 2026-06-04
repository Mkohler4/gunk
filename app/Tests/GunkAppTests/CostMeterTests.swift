import AppKit
import GRDB
import XCTest
@testable import GunkApp

final class CostMeterTests: XCTestCase {
  func testAggregatesTodayAndAllTime() throws {
    let store = try Store(databaseQueue: DatabaseQueue(), now: { 100 })
    let calendar = utcCalendar()
    let now = try XCTUnwrap(calendar.date(from: DateComponents(
      year: 2026,
      month: 6,
      day: 4,
      hour: 12
    )))
    let today = try XCTUnwrap(calendar.date(from: DateComponents(
      year: 2026,
      month: 6,
      day: 4,
      hour: 9
    )))
    let yesterday = try XCTUnwrap(calendar.date(from: DateComponents(
      year: 2026,
      month: 6,
      day: 3,
      hour: 23
    )))

    _ = try store.recordLLMRun(
      sourceId: nil,
      provider: "openai",
      model: "gpt-5",
      inputTokens: 100,
      outputTokens: 50,
      costUsd: 0.03,
      startedAt: milliseconds(yesterday)
    )
    _ = try store.recordLLMRun(
      sourceId: nil,
      provider: "anthropic",
      model: "claude",
      inputTokens: 200,
      outputTokens: 25,
      costUsd: 0.07,
      startedAt: milliseconds(today)
    )

    let snapshot = CostMeterAggregator.snapshot(
      runs: try store.listLLMRuns(),
      now: now,
      calendar: calendar
    )

    XCTAssertEqual(snapshot.today.inputTokens, 200)
    XCTAssertEqual(snapshot.today.outputTokens, 25)
    XCTAssertEqual(snapshot.today.totalTokens, 225)
    XCTAssertEqual(snapshot.today.costUsd, 0.07, accuracy: 0.0001)
    XCTAssertEqual(snapshot.allTime.inputTokens, 300)
    XCTAssertEqual(snapshot.allTime.outputTokens, 75)
    XCTAssertEqual(snapshot.allTime.totalTokens, 375)
    XCTAssertEqual(snapshot.allTime.costUsd, 0.10, accuracy: 0.0001)
  }

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

  private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private func milliseconds(_ date: Date) -> Int64 {
    Int64(date.timeIntervalSince1970 * 1_000)
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
