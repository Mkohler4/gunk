import XCTest
@testable import GunkApp

/// The "N modules added" completion claim must be a store diff, never the
/// engine's mid-run telemetry: the engine reports pre-gate candidate counts
/// that only correct downward, which once produced "14 modules added" on a
/// run that persisted zero.
final class RunCompletionSummaryTests: XCTestCase {
  func testRunThatPersistsNothingReportsZeroAdded() {
    let summary = RunCompletionSummary(
      gunkIdsBeforeRun: [1, 2, 3],
      gunkIdsAfterRun: [1, 2, 3],
      pendingReviewsAtRunStart: 0,
      pendingReviewsNow: 0
    )

    XCTAssertEqual(summary.modulesAdded, 0)
    XCTAssertEqual(summary.needsReview, 0)
  }

  func testCountsOnlyModulesNewSinceRunStart() {
    let summary = RunCompletionSummary(
      gunkIdsBeforeRun: [1, 2],
      gunkIdsAfterRun: [1, 2, 10, 11, 12],
      pendingReviewsAtRunStart: 1,
      pendingReviewsNow: 3
    )

    XCTAssertEqual(summary.modulesAdded, 3)
    XCTAssertEqual(summary.needsReview, 2)
  }

  func testModuleRemovedDuringRunNeverGoesNegative() {
    // A module deleted mid-run (e.g. a re-classify replacing rows) must not
    // drag the added count below the truly new ids.
    let summary = RunCompletionSummary(
      gunkIdsBeforeRun: [1, 2, 3],
      gunkIdsAfterRun: [1, 2, 20],
      pendingReviewsAtRunStart: 5,
      pendingReviewsNow: 2
    )

    XCTAssertEqual(summary.modulesAdded, 1)
    // Queue shrank during the run (reviews resolved): clamps at zero, never
    // negative.
    XCTAssertEqual(summary.needsReview, 0)
  }

  func testFreshLibraryCountsEverythingTheRunProduced() {
    let summary = RunCompletionSummary(
      gunkIdsBeforeRun: [],
      gunkIdsAfterRun: [1, 2],
      pendingReviewsAtRunStart: 0,
      pendingReviewsNow: 1
    )

    XCTAssertEqual(summary.modulesAdded, 2)
    XCTAssertEqual(summary.needsReview, 1)
  }
}
