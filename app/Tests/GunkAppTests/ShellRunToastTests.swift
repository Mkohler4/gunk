import XCTest
@testable import GunkApp

/// The run-end toast's state is a pure derivation from the run's error
/// state plus the truthful store-diff summary (T-8.7). Failure carries no
/// numbers — engine telemetry never becomes a completion claim — and the
/// success View action applies the needs-approval scope only when the run
/// actually queued reviews.
final class ShellRunToastTests: XCTestCase {
  private func summary(added: Int, needsReview: Int) -> RunCompletionSummary {
    RunCompletionSummary(
      gunkIdsBeforeRun: [],
      gunkIdsAfterRun: Set((0..<added).map(Int64.init)),
      pendingReviewsAtRunStart: 0,
      pendingReviewsNow: needsReview
    )
  }

  // MARK: Derivation

  func testCleanRunDerivesSuccessCarryingTheSummary() {
    let summary = summary(added: 3, needsReview: 1)

    let toast = ShellRunToast.forRunEnd(errorMessage: nil, summary: summary)

    XCTAssertEqual(toast, .success(summary))
  }

  func testFailedRunDerivesFailureAndDropsTheSummary() {
    // Even if a partial run persisted modules, a failed run must read as a
    // failure — no success numbers on a failure toast.
    let toast = ShellRunToast.forRunEnd(
      errorMessage: "engine exited 1",
      summary: summary(added: 2, needsReview: 1)
    )

    XCTAssertEqual(toast, .failure)
  }

  func testRunThatAddedNothingDerivesNoModulesNotSuccess() {
    // "0 modules added" with a View button is a contradiction — a clean run
    // that persisted nothing is its own state.
    let toast = ShellRunToast.forRunEnd(
      errorMessage: nil,
      summary: summary(added: 0, needsReview: 0)
    )

    XCTAssertEqual(toast, .noModules)
  }

  // MARK: Copy

  func testSuccessMessageReadsAddedAndReviewCounts() {
    let toast = ShellRunToast.success(summary(added: 5, needsReview: 2))

    XCTAssertEqual(toast.message, "5 modules added · 2 need review")
    XCTAssertEqual(toast.actionLabel, "View")
  }

  func testSuccessMessageUsesSingularForms() {
    let toast = ShellRunToast.success(summary(added: 1, needsReview: 1))

    XCTAssertEqual(toast.message, "1 module added · 1 needs review")
  }

  func testSuccessMessageOmitsReviewSegmentAtZero() {
    let toast = ShellRunToast.success(summary(added: 3, needsReview: 0))

    XCTAssertEqual(toast.message, "3 modules added")
  }

  func testNoModulesMessageHasNoActionToView() {
    let toast = ShellRunToast.noModules

    XCTAssertEqual(toast.message, "Run finished — no new modules")
    // No action button: there is nothing new to view.
    XCTAssertNil(toast.actionLabel)
  }

  func testFailureMessageAndActionLabel() {
    let toast = ShellRunToast.failure

    XCTAssertEqual(toast.message, "Run failed")
    XCTAssertEqual(toast.actionLabel, "Inspect")
  }

  // MARK: View-action filter rule (M > 0)

  func testViewActionAppliesNeedsApprovalFilterOnlyWhenReviewsQueued() {
    let withReviews = ShellRunToast.success(summary(added: 4, needsReview: 2))
    let cleanRun = ShellRunToast.success(summary(added: 4, needsReview: 0))

    XCTAssertEqual(withReviews.approvalFilterForView, .needsApproval)
    XCTAssertNil(cleanRun.approvalFilterForView)
  }

  func testFailureNeverAppliesAnApprovalFilter() {
    XCTAssertNil(ShellRunToast.failure.approvalFilterForView)
  }
}
