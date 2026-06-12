import XCTest
@testable import GunkApp

/// T-8.6: the inspector opens *on* something useful for every entry point
/// (sources panel → that source's latest run; failure element → the failed
/// run), and trace numbers are formatted for humans.
final class RunInspectorTests: XCTestCase {
  // MARK: Initial selection

  func testSourceContextSelectsMostRecentRunForThatSource() {
    let traces = [
      makeTrace(runId: "newest-other", sourceId: 2, startedAtMs: 4_000),
      makeTrace(runId: "latest-for-source", sourceId: 1, startedAtMs: 3_000),
      makeTrace(runId: "older-for-source", sourceId: 1, startedAtMs: 2_000),
    ]

    XCTAssertEqual(
      RunInspectorContext.source(1).initialRunId(in: traces),
      "latest-for-source"
    )
  }

  func testSourceContextFallsBackToMostRecentWhenSourceHasNoRuns() {
    let traces = [
      makeTrace(runId: "newest", sourceId: 2, startedAtMs: 2_000),
      makeTrace(runId: "older", sourceId: 3, startedAtMs: 1_000),
    ]

    XCTAssertEqual(
      RunInspectorContext.source(99).initialRunId(in: traces),
      "newest"
    )
  }

  func testFailureContextSelectsMostRecentFailedRun() {
    let traces = [
      makeTrace(runId: "newest-success", sourceId: 1, startedAtMs: 3_000),
      makeTrace(runId: "the-failure", sourceId: 1, startedAtMs: 2_000, status: "failed"),
      makeTrace(runId: "older-failure", sourceId: 1, startedAtMs: 1_000, status: "failed"),
    ]

    XCTAssertEqual(
      RunInspectorContext.mostRecentFailure.initialRunId(in: traces),
      "the-failure"
    )
  }

  func testFailureContextFallsBackToMostRecentWhenNothingFailed() {
    let traces = [
      makeTrace(runId: "newest", sourceId: 1, startedAtMs: 2_000),
      makeTrace(runId: "older", sourceId: 1, startedAtMs: 1_000),
    ]

    XCTAssertEqual(
      RunInspectorContext.mostRecentFailure.initialRunId(in: traces),
      "newest"
    )
  }

  func testAllContextSelectsMostRecentRun() {
    let traces = [
      makeTrace(runId: "newest", sourceId: 1, startedAtMs: 2_000),
      makeTrace(runId: "older", sourceId: 2, startedAtMs: 1_000),
    ]

    XCTAssertEqual(RunInspectorContext.all.initialRunId(in: traces), "newest")
    XCTAssertNil(RunInspectorContext.all.initialRunId(in: []))
  }

  // MARK: Human formatting

  func testDurationFormatsMillisecondsAsSeconds() {
    XCTAssertEqual(RunTraceFormat.duration(ms: 83_214), "83.2s")
    XCTAssertEqual(RunTraceFormat.duration(ms: 437), "0.4s")
    XCTAssertEqual(RunTraceFormat.duration(ms: 0), "0.0s")
  }

  func testTimestampIncludesDateOnlyWhenNotToday() {
    let calendar = Calendar.current
    let now = Date()
    let earlierToday = calendar.date(byAdding: .minute, value: -1, to: now)!
    let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

    XCTAssertFalse(RunTraceFormat.includesDate(earlierToday, now: now, calendar: calendar))
    XCTAssertTrue(RunTraceFormat.includesDate(yesterday, now: now, calendar: calendar))
  }

  // MARK: Fixtures

  private func makeTrace(
    runId: String,
    sourceId: Int64?,
    startedAtMs: Double,
    status: String = "succeeded"
  ) -> RunTrace {
    RunTrace(
      runId: runId,
      sourceId: sourceId,
      sourceName: "Source \(sourceId.map(String.init) ?? "?")",
      provider: "anthropic",
      model: "claude-test",
      startedAtMs: startedAtMs,
      finishedAtMs: startedAtMs + 1_000,
      status: status,
      error: status == "failed" ? "stage exploded" : nil,
      stages: [],
      refinements: nil,
      verification: nil,
      summary: RunTrace.Summary(accepted: 0, needsApproval: 0, rejected: 0, gunkIds: [])
    )
  }
}
