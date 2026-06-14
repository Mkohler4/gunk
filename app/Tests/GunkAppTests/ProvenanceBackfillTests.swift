import Foundation
import GRDB
import XCTest
@testable import GunkApp

final class ProvenanceBackfillTests: XCTestCase {
  func testBackfillPopulatesFromGunkLevelTrace() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let gunk = try store.insertGunk(sourceId: source.id, name: "module", confidence: 0.9, extractedAt: 200)

    let trace = makeTrace(
      sourceId: source.id + 99, // not the source — only the gunk-id match applies
      provider: "anthropic",
      model: "claude-sonnet-4",
      gunkIds: [gunk.id]
    )

    let count = try ProvenanceBackfill.run(store: store, traces: [trace])

    XCTAssertEqual(count, 1)
    let stored = try XCTUnwrap(try store.gunk(id: gunk.id))
    XCTAssertEqual(stored.provider, "anthropic")
    XCTAssertEqual(stored.model, "claude-sonnet-4")
  }

  func testBackfillFallsBackToSourceTrace() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let gunk = try store.insertGunk(sourceId: source.id, name: "module", confidence: 0.9, extractedAt: 200)

    // No gunk-id match — the source's most recent run resolves it.
    let trace = makeTrace(
      sourceId: source.id,
      provider: "openai",
      model: "gpt-test",
      gunkIds: []
    )

    try ProvenanceBackfill.run(store: store, traces: [trace])

    let stored = try XCTUnwrap(try store.gunk(id: gunk.id))
    XCTAssertEqual(stored.provider, "openai")
    XCTAssertEqual(stored.model, "gpt-test")
  }

  func testBackfillLeavesNullWhenNoResolvableTrace() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let gunk = try store.insertGunk(sourceId: source.id, name: "module", confidence: 0.9, extractedAt: 200)

    // A trace for an unrelated source/gunk: nothing resolves.
    let trace = makeTrace(
      sourceId: source.id + 1,
      provider: "anthropic",
      model: "claude-sonnet-4",
      gunkIds: [gunk.id + 1]
    )

    let count = try ProvenanceBackfill.run(store: store, traces: [trace])

    XCTAssertEqual(count, 0)
    let stored = try XCTUnwrap(try store.gunk(id: gunk.id))
    XCTAssertNil(stored.provider)
    XCTAssertNil(stored.model)
  }

  func testBackfillDoesNotOverwriteStoredValue() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    // Already attributed (e.g. written at extraction time).
    let gunk = try store.insertGunk(
      sourceId: source.id,
      name: "module",
      confidence: 0.9,
      extractedAt: 200,
      provider: "anthropic",
      model: "claude-sonnet-4"
    )

    // A different trace must not clobber the durable value.
    let trace = makeTrace(
      sourceId: source.id,
      provider: "openai",
      model: "gpt-test",
      gunkIds: [gunk.id]
    )

    let count = try ProvenanceBackfill.run(store: store, traces: [trace])

    XCTAssertEqual(count, 0)
    let stored = try XCTUnwrap(try store.gunk(id: gunk.id))
    XCTAssertEqual(stored.provider, "anthropic")
    XCTAssertEqual(stored.model, "claude-sonnet-4")
  }

  func testProvenanceIndexPrefersGunkOverSourceAndNewestRun() {
    let index = RunTraceProvenanceIndex(traces: [
      // newest-first
      makeTrace(sourceId: 1, provider: "openai", model: "gpt-test", gunkIds: [10]),
      makeTrace(sourceId: 1, provider: "anthropic", model: "claude-sonnet-4", gunkIds: []),
    ])

    // Gunk-level match wins.
    XCTAssertEqual(
      index.provenance(gunkId: 10, sourceId: 1),
      BrowseProvenance(provider: "openai", model: "gpt-test")
    )
    // No gunk match → most recent source run.
    XCTAssertEqual(
      index.provenance(gunkId: 99, sourceId: 1),
      BrowseProvenance(provider: "openai", model: "gpt-test")
    )
    // Nothing resolves.
    XCTAssertNil(index.provenance(gunkId: 99, sourceId: 2))
  }

  private func makeStore() throws -> Store {
    try Store(databaseQueue: DatabaseQueue(), now: { 100 })
  }

  private func makeTrace(
    sourceId: Int64?,
    provider: String,
    model: String,
    gunkIds: [Int64],
    startedAtMs: Double = 1
  ) -> RunTrace {
    RunTrace(
      runId: "run-\(provider)-\(startedAtMs)",
      sourceId: sourceId,
      sourceName: "source",
      provider: provider,
      model: model,
      startedAtMs: startedAtMs,
      finishedAtMs: startedAtMs + 1,
      status: "succeeded",
      error: nil,
      stages: [],
      refinements: nil,
      verification: nil,
      summary: RunTrace.Summary(
        accepted: gunkIds.count,
        needsApproval: 0,
        rejected: 0,
        gunkIds: gunkIds
      )
    )
  }
}
