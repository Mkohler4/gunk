import Foundation
import GRDB
import XCTest
@testable import GunkApp

@MainActor
final class BrowseModelTests: XCTestCase {
  func testGroupsByProjectByDefault() throws {
    let store = try makeStore()
    let apiSource = try store.insertSource(name: "api", path: "/tmp/api")
    let cliSource = try store.insertSource(name: "cli", path: "/tmp/cli")
    let auth = try insertGunk(
      store: store,
      source: apiSource,
      name: "auth-module",
      tags: ["auth", "api"],
      confidence: 0.91,
      extractedAt: 200
    )
    let cli = try insertGunk(
      store: store,
      source: cliSource,
      name: "cli-module",
      tags: ["cli"],
      confidence: 0.84,
      extractedAt: 300
    )
    let model = BrowseModel(
      store: store,
      extractGunk: { _ in }
    )

    model.refresh()

    let itemsBySection = Dictionary(uniqueKeysWithValues: model.sections.map { section in
      (section.tag, section.items.map(\.gunk.id))
    })

    XCTAssertEqual(model.filters.group, .project)
    XCTAssertEqual(itemsBySection["api"], [auth.id])
    XCTAssertEqual(itemsBySection["cli"], [cli.id])
    XCTAssertEqual(model.totalModuleCount, 2)
    XCTAssertTrue(model.approvalQueue.isEmpty)
  }

  func testFiltersModulesBySourceTagLanguageAndApproval() throws {
    let store = try makeStore()
    let apiSource = try store.insertSource(name: "api", path: "/tmp/api")
    let cliSource = try store.insertSource(name: "cli", path: "/tmp/cli")
    let apiModule = try insertGunk(
      store: store,
      source: apiSource,
      name: "api-auth",
      tags: ["auth", "sessions"],
      language: "Swift",
      confidence: 0.92,
      extractedAt: 200
    )
    _ = try insertGunk(
      store: store,
      source: cliSource,
      name: "cli-reports",
      tags: ["reports"],
      language: "Go",
      confidence: 0.81,
      extractedAt: 300
    )
    let model = BrowseModel(store: store)

    model.refresh()
    model.filters.sourceId = apiSource.id
    model.filters.tag = "auth"
    model.filters.language = "Swift"
    model.filters.approval = .autoAccepted

    XCTAssertEqual(model.sections.flatMap(\.items).map(\.gunk.id), [apiModule.id])
    XCTAssertEqual(model.availableTags, ["auth", "reports", "sessions"])
    XCTAssertEqual(model.availableLanguages, ["Go", "Swift"])
    XCTAssertEqual(model.availableSources.map(\.name), ["api", "cli"])
  }

  func testGroupsByExtractingModelWithUnknownBucket() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let claudeModule = try insertGunk(
      store: store,
      source: source,
      name: "claude-module",
      tags: [],
      confidence: 0.9,
      extractedAt: 200
    )
    let untraced = try insertGunk(
      store: store,
      source: source,
      name: "untraced-module",
      tags: [],
      confidence: 0.8,
      extractedAt: 300
    )
    // The untraced module's source has no trace either: insert the trace for
    // a different source id so only the explicit gunk-id match applies.
    let trace = makeTrace(
      runId: "run-1",
      sourceId: source.id + 99,
      provider: "anthropic",
      model: "claude-sonnet-4",
      gunkIds: [claudeModule.id]
    )
    let model = BrowseModel(store: store, loadRunTraces: { [trace] })

    model.refresh()
    model.filters.group = .model

    XCTAssertEqual(
      Dictionary(uniqueKeysWithValues: model.sections.map { ($0.tag, $0.items.map(\.gunk.id)) }),
      [
        "anthropic · claude-sonnet-4": [claudeModule.id],
        "Unknown model": [untraced.id],
      ]
    )
  }

  func testProvenancePrefersGunkTraceAndFallsBackToSourceTrace() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let traced = try insertGunk(
      store: store,
      source: source,
      name: "traced-module",
      tags: [],
      confidence: 0.9,
      extractedAt: 200
    )
    let sourceFallback = try insertGunk(
      store: store,
      source: source,
      name: "fallback-module",
      tags: [],
      confidence: 0.8,
      extractedAt: 300
    )
    // Newest-first trace order: the recent openai run names `traced` only;
    // an older anthropic source-level run covers the rest of the source.
    let traces = [
      makeTrace(
        runId: "run-2",
        sourceId: source.id,
        provider: "openai",
        model: "gpt-test",
        gunkIds: [traced.id],
        startedAtMs: 2
      ),
      makeTrace(
        runId: "run-1",
        sourceId: source.id,
        provider: "anthropic",
        model: "claude-sonnet-4",
        gunkIds: [],
        startedAtMs: 1
      ),
    ]
    let model = BrowseModel(store: store, loadRunTraces: { traces })

    model.refresh()
    let items = model.sections.flatMap(\.items)
    let tracedItem = try XCTUnwrap(items.first { $0.gunk.id == traced.id })
    let fallbackItem = try XCTUnwrap(items.first { $0.gunk.id == sourceFallback.id })

    XCTAssertEqual(
      model.provenance(for: tracedItem),
      BrowseProvenance(provider: "openai", model: "gpt-test")
    )
    // No gunk-level trace: the most recent trace for its source wins. (The
    // newest run-2 also carries sourceId, so the source fallback is run-2.)
    XCTAssertEqual(
      model.provenance(for: fallbackItem),
      BrowseProvenance(provider: "openai", model: "gpt-test")
    )
  }

  func testSearchQueryMatchesNamePurposeAndTagsCaseInsensitively() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let auth = try insertGunk(
      store: store,
      source: source,
      name: "OAuth-Login",
      tags: ["sessions"],
      confidence: 0.9,
      extractedAt: 200
    )
    let parser = try insertGunk(
      store: store,
      source: source,
      name: "epub-parser",
      tags: ["audiobook"],
      confidence: 0.8,
      extractedAt: 300
    )
    let model = BrowseModel(store: store)

    model.refresh()

    model.filters.query = "oauth"
    XCTAssertEqual(model.sections.flatMap(\.items).map(\.gunk.id), [auth.id])

    // Purpose match (insertGunk writes "<name> purpose").
    model.filters.query = "EPUB-PARSER PURPOSE"
    XCTAssertEqual(model.sections.flatMap(\.items).map(\.gunk.id), [parser.id])

    // Tag match.
    model.filters.query = "AudioBook"
    XCTAssertEqual(model.sections.flatMap(\.items).map(\.gunk.id), [parser.id])

    model.filters.query = "no-such-module"
    XCTAssertTrue(model.sections.isEmpty)

    model.filters.query = ""
    XCTAssertEqual(model.sections.flatMap(\.items).count, 2)
  }

  func testHeroRankPutsAgentReadyBeforeConfidenceThenName() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    // Not extracted, but the highest confidence in the group.
    let pendingHighConfidence = try insertGunk(
      store: store,
      source: source,
      name: "a-pending-module",
      tags: [],
      confidence: 0.99
    )
    let readyLow = try insertGunk(
      store: store,
      source: source,
      name: "b-ready-low",
      tags: [],
      confidence: 0.7,
      extractedAt: 200
    )
    let readyHigh = try insertGunk(
      store: store,
      source: source,
      name: "a-ready-high",
      tags: [],
      confidence: 0.9,
      extractedAt: 300
    )
    let readyTied = try insertGunk(
      store: store,
      source: source,
      name: "z-ready-tied",
      tags: [],
      confidence: 0.9,
      extractedAt: 400
    )
    let model = BrowseModel(store: store)

    model.refresh()
    let section = try XCTUnwrap(model.sections.first)

    // Agent-ready first, then confidence desc, then name; the first item is
    // the grid's hero.
    XCTAssertEqual(
      section.items.map(\.gunk.id),
      [readyHigh.id, readyTied.id, readyLow.id, pendingHighConfidence.id]
    )
  }

  /// Badge → scope wiring (T-8.4): the needs-approval filter must show
  /// exactly the modules in `approvalQueue` — the same rule the sidebar
  /// badge counts — so badge, scope chip, and grid can never disagree.
  func testNeedsApprovalScopeMatchesApprovalQueueMembership() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let queued = try insertGunk(
      store: store,
      source: source,
      name: "queued-module",
      tags: [],
      confidence: 0.42
    )
    _ = try insertGunk(
      store: store,
      source: source,
      name: "extracted-module",
      tags: [],
      confidence: 0.9,
      extractedAt: 200
    )
    // Low confidence but already extracted: not pending approval.
    _ = try insertGunk(
      store: store,
      source: source,
      name: "extracted-low-confidence",
      tags: [],
      confidence: 0.3,
      extractedAt: 300
    )
    let model = BrowseModel(store: store)

    model.refresh()
    model.filters.approval = .needsApproval

    XCTAssertEqual(model.approvalQueue.map(\.gunk.id), [queued.id])
    XCTAssertEqual(
      model.sections.flatMap(\.items).map(\.gunk.id),
      model.approvalQueue.map(\.gunk.id)
    )
  }

  /// The review copy derives its threshold from the same constant the queue
  /// rule gates on (T-8.4; B1: hard-coded 0.7 until Phase 11) — a module at
  /// the threshold is auto-accepted, one below it is queued.
  func testConfidenceThresholdExposedMatchesQueueGate() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let belowThreshold = try insertGunk(
      store: store,
      source: source,
      name: "below-threshold",
      tags: [],
      confidence: Extractor.defaultConfidenceThreshold - 0.01
    )
    _ = try insertGunk(
      store: store,
      source: source,
      name: "at-threshold",
      tags: [],
      confidence: Extractor.defaultConfidenceThreshold
    )
    let model = BrowseModel(store: store)

    model.refresh()

    XCTAssertEqual(model.confidenceThreshold, Extractor.defaultConfidenceThreshold)
    XCTAssertEqual(model.approvalQueue.map(\.gunk.id), [belowThreshold.id])
  }

  /// Approving under the needs-approval scope hides the cell but must not
  /// drop the module from the loaded set: the detail stays renderable so the
  /// post-approve feedback remains visible (T-8.4 item 3).
  func testApproveUnderNeedsApprovalScopeKeepsModuleLoaded() throws {
    let store = try makeStore(now: { 500 })
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let queued = try insertGunk(
      store: store,
      source: source,
      name: "queued-module",
      tags: [],
      confidence: 0.5
    )
    let model = BrowseModel(store: store, extractGunk: { _ in })

    model.refresh()
    model.filters.approval = .needsApproval
    XCTAssertEqual(model.sections.flatMap(\.items).map(\.gunk.id), [queued.id])

    model.approve(gunkId: queued.id)

    // The scope no longer shows the module (queue cleared)…
    XCTAssertTrue(model.approvalQueue.isEmpty)
    XCTAssertTrue(model.sections.isEmpty)
    // …but it still exists and its detail is still available.
    XCTAssertTrue(model.loadedGunkIds.contains(queued.id))
    XCTAssertNotNil(model.detail(for: queued.id))
    XCTAssertNotEqual(model.approvalFilter(for: try XCTUnwrap(
      model.detail(for: queued.id)?.item
    )), .needsApproval)
  }

  /// Reject is the destructive review path: the module is permanently
  /// removed from the store and the queue (T-8.4 item 2).
  func testRejectPermanentlyRemovesQueuedModule() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let queued = try insertGunk(
      store: store,
      source: source,
      name: "queued-module",
      tags: [],
      confidence: 0.4
    )
    let model = BrowseModel(store: store)

    model.refresh()
    XCTAssertEqual(model.approvalQueue.map(\.gunk.id), [queued.id])

    model.reject(gunkId: queued.id)

    XCTAssertNil(try store.gunk(id: queued.id))
    XCTAssertTrue(model.approvalQueue.isEmpty)
    XCTAssertFalse(model.loadedGunkIds.contains(queued.id))
    XCTAssertNil(model.detail(for: queued.id))
  }

  func testApproveMarksApprovedAt() throws {
    let store = try makeStore(now: { 500 })
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let lowConfidence = try insertGunk(
      store: store,
      source: source,
      name: "maybe-auth",
      tags: ["auth"],
      confidence: 0.42
    )
    var extractedIds: [Int64] = []
    let model = BrowseModel(
      store: store,
      extractGunk: { gunk in
        extractedIds.append(gunk.id)
      }
    )

    model.refresh()
    XCTAssertEqual(model.approvalQueue.map(\.gunk.id), [lowConfidence.id])

    model.approve(gunkId: lowConfidence.id)

    XCTAssertEqual(try store.gunk(id: lowConfidence.id)?.approvedAt, 500)
    XCTAssertEqual(extractedIds, [lowConfidence.id])
    XCTAssertTrue(model.approvalQueue.isEmpty)
    XCTAssertEqual(model.sections.flatMap(\.items).map(\.gunk.id), [lowConfidence.id])
  }

  func testDeleteRemovesModule() throws {
    let store = try makeStore(now: { 700 })
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let removed = try insertGunk(
      store: store,
      source: source,
      name: "old-auth",
      tags: ["auth"],
      confidence: 0.8,
      extractedAt: 300
    )
    let active = try insertGunk(
      store: store,
      source: source,
      name: "active-cli",
      tags: ["cli"],
      confidence: 0.8,
      extractedAt: 400
    )
    let model = BrowseModel(store: store)
    model.refresh()

    model.delete(gunkId: removed.id)

    XCTAssertNil(try store.gunk(id: removed.id))
    XCTAssertEqual(try store.listGunks().map(\.id), [active.id])
    XCTAssertEqual(model.sections.flatMap(\.items).map(\.gunk.id), [active.id])
  }

  func testReclassifyTargetsSource() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    var reclassifiedSourceIds: [Int64] = []
    let model = BrowseModel(
      store: store,
      reclassifySource: { sourceId in
        reclassifiedSourceIds.append(sourceId)
      }
    )

    model.reclassify(sourceId: source.id)

    XCTAssertEqual(reclassifiedSourceIds, [source.id])
  }

  func testReclassifyRefreshesModulesAfterSourceRun() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let model = BrowseModel(
      store: store,
      reclassifySource: { sourceId in
        _ = try store.insertGunk(
          sourceId: sourceId,
          name: "rerun-module",
          purpose: "created by re-run",
          confidence: 0.91
        )
      }
    )

    model.refresh()
    XCTAssertTrue(model.sections.isEmpty)

    model.reclassify(sourceId: source.id)

    XCTAssertEqual(model.sections.flatMap(\.items).map(\.gunk.name), ["rerun-module"])
  }

  func testDetailUsesTraceForRunabilityAndSharedDependencies() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let gunk = try insertGunk(
      store: store,
      source: source,
      name: "oauth-login",
      tags: ["auth"],
      confidence: 0.93,
      extractedAt: 300,
      files: ["src/auth.ts", "src/types.ts"]
    )
    let trace = RunTrace(
      runId: "run-1",
      sourceId: source.id,
      sourceName: source.name,
      provider: "openai",
      model: "gpt-test",
      startedAtMs: 1,
      finishedAtMs: 2,
      status: "succeeded",
      error: nil,
      stages: [],
      refinements: [
        RunTrace.Refinement(
          capability: "oauth-login",
          accepted: true,
          rejectReason: nil,
          module: RunTrace.Module(
            name: "oauth-login",
            ownedFiles: ["src/auth.ts"],
            sharedDeps: ["src/types.ts"],
            surface: [
              RunTrace.Surface(path: "src/auth.ts", symbol: "authCallback")
            ]
          )
        )
      ],
      verification: RunTrace.Verification(
        build: [
          RunTrace.BuildResult(
            bundlePath: "/tmp/modules/oauth-login",
            language: "typeScript",
            built: false,
            skipped: false,
            command: "tsc --noEmit src/auth.ts",
            log: "missing package"
          )
        ],
        selfContainment: [
          RunTrace.SelfContainmentResult(
            moduleName: "oauth-login",
            imports: "pass",
            entrypoint: "pass",
            danglingImports: [],
            missingEntrypoints: []
          )
        ]
      ),
      summary: RunTrace.Summary(
        accepted: 1,
        needsApproval: 0,
        rejected: 0,
        gunkIds: [gunk.id]
      )
    )
    let model = BrowseModel(store: store, loadRunTraces: { [trace] })

    model.refresh()
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    XCTAssertEqual(detail.ownedFiles, ["src/auth.ts"])
    XCTAssertEqual(detail.sharedDependencies, ["src/types.ts"])
    XCTAssertEqual(detail.entrypoints, [BrowseEntrypoint(path: "src/auth.ts", symbol: "authCallback")])
    XCTAssertEqual(detail.selfContainment?.passed, true)
    XCTAssertEqual(detail.buildVerification?.built, false)
    XCTAssertEqual(detail.buildVerification?.command, "tsc --noEmit src/auth.ts")
  }

  func testDetailFallsBackToStoreFilesAndManifestEntrypoints() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let tempDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: tempDirectory)
    }

    let manifestURL = tempDirectory.appendingPathComponent("gunk.yml")
    try """
    schema_version: 0
    entrypoints:
      - path: "src/main.swift"
        symbol: "run"
    """.write(to: manifestURL, atomically: true, encoding: .utf8)

    let gunk = try store.insertGunk(
      sourceId: source.id,
      name: "runner",
      purpose: "runner purpose",
      language: "Swift",
      confidence: 0.88,
      bundlePath: tempDirectory.path,
      manifestPath: manifestURL.path,
      extractedAt: 300
    )
    try store.addGunkFile(gunkId: gunk.id, relpath: "src/main.swift", size: 42)
    let model = BrowseModel(store: store, loadRunTraces: { [] })

    model.refresh()
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    XCTAssertEqual(detail.ownedFiles, ["src/main.swift"])
    XCTAssertEqual(detail.entrypoints, [BrowseEntrypoint(path: "src/main.swift", symbol: "run")])
    XCTAssertNil(detail.selfContainment)
    XCTAssertNil(detail.buildVerification)
  }

  private func makeStore(now: @escaping () -> Int64 = { 100 }) throws -> Store {
    try Store(databaseQueue: DatabaseQueue(), now: now)
  }

  private func makeTrace(
    runId: String,
    sourceId: Int64?,
    provider: String,
    model: String,
    gunkIds: [Int64],
    startedAtMs: Double = 1
  ) -> RunTrace {
    RunTrace(
      runId: runId,
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

  private func insertGunk(
    store: Store,
    source: Source,
    name: String,
    tags: [String],
    language: String? = "Swift",
    confidence: Double,
    extractedAt: Int64? = nil,
    files: [String] = []
  ) throws -> Gunk {
    let gunk = try store.insertGunk(
      sourceId: source.id,
      name: name,
      purpose: "\(name) purpose",
      language: language,
      confidence: confidence,
      bundlePath: extractedAt.map { _ in "/tmp/modules/\(name)" },
      manifestPath: extractedAt.map { _ in "/tmp/modules/\(name)/gunk.yml" },
      extractedAt: extractedAt
    )

    for tagName in tags {
      let tag = try store.addTag(name: tagName)
      try store.addGunkTag(gunkId: gunk.id, tagId: tag.id, confidence: confidence)
    }

    for file in files {
      try store.addGunkFile(gunkId: gunk.id, relpath: file, size: nil)
    }

    return gunk
  }
}
