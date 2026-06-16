import Foundation
import XCTest
@testable import GunkApp

/// The coverage sign-off rule (T-10.11, CP-J). The *ready to connect* sign-off
/// is locked to **happy path + at least one of your own inputs**, nothing
/// failing — edge/adversarial deepen coverage but never gate it, and a lone
/// synthesized happy-path pass is never sufficient on its own.
final class CoverageStateTests: XCTestCase {
  // MARK: Builders

  private func example(
    id: Int64 = 1,
    name: String = "case",
    inputClass: ExampleInputClass,
    verdict: RunVerdict? = nil,
    expectedOutput: String? = nil,
    note: String? = nil
  ) -> ModuleExample {
    ModuleExample(
      id: id,
      gunkId: 1,
      name: name,
      input: "--in x",
      inputClass: inputClass,
      isGolden: false,
      verdict: verdict,
      expectedOutput: expectedOutput,
      note: note,
      createdAt: 0
    )
  }

  private func run(passed: Bool?) -> SmokeRunRecord {
    SmokeRunRecord(
      id: 1,
      gunkId: 1,
      exampleId: nil,
      command: "python x.py",
      runnability: .terminalRunnable,
      origin: .human,
      exitCode: passed == true ? 0 : 1,
      passed: passed,
      timedOut: false,
      durationMs: 1,
      outputArtifactPath: nil,
      log: "",
      verdict: nil,
      createdAt: 0
    )
  }

  // MARK: Tests

  func testNothingCoveredIsNotReady() {
    let state = CoverageState.derive(examples: [], lastRun: nil)
    XCTAssertFalse(state.happy)
    XCTAssertFalse(state.yours)
    XCTAssertFalse(state.readyToConnect)
    XCTAssertEqual(state.classesCovered, 0)
  }

  func testLoneHappyPassIsNeverSufficient() {
    // A single synthesized happy-path pass (no developer-brought input).
    let state = CoverageState.derive(examples: [], lastRun: run(passed: true))
    XCTAssertTrue(state.happy)
    XCTAssertFalse(state.yours)
    XCTAssertFalse(state.readyToConnect, "happy alone must not unlock the sign-off")
  }

  func testYoursAloneIsNotReady() {
    let state = CoverageState.derive(
      examples: [example(inputClass: .yours, verdict: .right)],
      lastRun: nil
    )
    XCTAssertTrue(state.yours)
    XCTAssertFalse(state.happy)
    XCTAssertFalse(state.readyToConnect, "your own input without happy path is not enough")
  }

  func testHappyPlusYoursIsReady() {
    let state = CoverageState.derive(
      examples: [
        example(id: 1, inputClass: .happy, verdict: .right),
        example(id: 2, inputClass: .yours, verdict: .right),
      ],
      lastRun: nil
    )
    XCTAssertTrue(state.readyToConnect)
  }

  func testHappyFromLastRunPlusYoursIsReady() {
    let state = CoverageState.derive(
      examples: [example(inputClass: .yours, verdict: .right)],
      lastRun: run(passed: true)
    )
    XCTAssertTrue(state.happy)
    XCTAssertTrue(state.yours)
    XCTAssertTrue(state.readyToConnect)
  }

  func testFailingCaseBlocksSignOff() {
    let state = CoverageState.derive(
      examples: [
        example(id: 1, inputClass: .happy, verdict: .right),
        example(id: 2, inputClass: .yours, verdict: .right),
        // A pinned correction (expected output) is a failing case.
        example(id: 3, inputClass: .edge, expectedOutput: "should be X", note: "wrong order"),
      ],
      lastRun: nil
    )
    XCTAssertTrue(state.hasFailing)
    XCTAssertFalse(state.readyToConnect, "an open failing case must block the sign-off")
  }

  func testWrongVerdictIsFailingAndNotCoverage() {
    let state = CoverageState.derive(
      examples: [example(inputClass: .yours, verdict: .wrong)],
      lastRun: run(passed: true)
    )
    XCTAssertTrue(state.hasFailing)
    XCTAssertFalse(state.yours, "a wrong-verdict example is not a passing check")
    XCTAssertFalse(state.readyToConnect)
  }

  func testEdgeAndAdversarialDoNotUnlockSignOff() {
    // Edge covered + a known limit recorded, but no happy and no yours.
    let state = CoverageState.derive(
      examples: [
        example(id: 1, inputClass: .edge, verdict: .right),
        example(id: 2, inputClass: .adversarial, note: "known not to handle: empty file"),
      ],
      lastRun: nil
    )
    XCTAssertTrue(state.edge)
    XCTAssertTrue(state.adversarial)
    XCTAssertEqual(state.classesCovered, 2)
    XCTAssertFalse(state.readyToConnect, "edge + adversarial alone never reach the sign-off")
  }

  func testAdversarialNeedsANoteToCount() {
    let state = CoverageState.derive(
      examples: [example(inputClass: .adversarial, note: nil)],
      lastRun: nil
    )
    XCTAssertFalse(state.adversarial, "an adversarial example with no note is not a recorded limit")
  }

  func testAllFourClassesCovered() {
    let state = CoverageState.derive(
      examples: [
        example(id: 1, inputClass: .happy, verdict: .right),
        example(id: 2, inputClass: .yours, verdict: .right),
        example(id: 3, inputClass: .edge, verdict: .right),
        example(id: 4, inputClass: .adversarial, note: "empty file"),
      ],
      lastRun: nil
    )
    XCTAssertEqual(state.classesCovered, 4)
    XCTAssertTrue(state.readyToConnect)
  }
}
