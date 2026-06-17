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

  /// T-9.2: a durable stored provider/model wins over the trace-derived
  /// lookup, so attribution survives even when traces disagree or are pruned.
  func testProvenancePrefersStoredValueOverTrace() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    // Stored attribution says anthropic…
    let gunk = try store.insertGunk(
      sourceId: source.id,
      name: "stored-module",
      purpose: "stored purpose",
      confidence: 0.9,
      extractedAt: 200,
      provider: "anthropic",
      model: "claude-sonnet-4"
    )
    // …while the trace says openai. The stored value must win.
    let trace = makeTrace(
      runId: "run-1",
      sourceId: source.id,
      provider: "openai",
      model: "gpt-test",
      gunkIds: [gunk.id]
    )
    let model = BrowseModel(store: store, loadRunTraces: { [trace] })

    model.refresh()
    let item = try XCTUnwrap(model.sections.flatMap(\.items).first { $0.gunk.id == gunk.id })

    XCTAssertEqual(
      model.provenance(for: item),
      BrowseProvenance(provider: "anthropic", model: "claude-sonnet-4")
    )
  }

  func testSearchQueryMatchesNamePurposeTagsAndProjectCaseInsensitively() throws {
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

    // Project/folder match: typing the source name scopes to its modules.
    model.filters.query = "SOURCE"
    XCTAssertEqual(
      Set(model.sections.flatMap(\.items).map(\.gunk.id)),
      [auth.id, parser.id]
    )

    model.filters.query = "no-such-module"
    XCTAssertTrue(model.sections.isEmpty)

    model.filters.query = ""
    XCTAssertEqual(model.sections.flatMap(\.items).count, 2)
  }

  func testProjectNamesForAddedGunkIdsAreDistinctAndSorted() throws {
    let store = try makeStore()
    let api = try store.insertSource(name: "api", path: "/tmp/api")
    let cli = try store.insertSource(name: "cli", path: "/tmp/cli")
    let auth = try insertGunk(store: store, source: api, name: "auth", tags: [], confidence: 0.9, extractedAt: 1)
    let routing = try insertGunk(store: store, source: api, name: "routing", tags: [], confidence: 0.9, extractedAt: 2)
    let parser = try insertGunk(store: store, source: cli, name: "parser", tags: [], confidence: 0.9, extractedAt: 3)
    let model = BrowseModel(store: store)

    model.refresh()

    // Two ids from the same project collapse to one name; the cli id adds a
    // second, returned sorted.
    XCTAssertEqual(
      model.projectNames(for: [auth.id, routing.id, parser.id]),
      ["api", "cli"]
    )
    XCTAssertEqual(model.projectNames(for: [auth.id, routing.id]), ["api"])
    XCTAssertEqual(model.projectNames(for: []), [])
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

  // MARK: Requirements readout (T-10.6)

  func testDetailReadsRequirementsFromManifest() throws {
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
    deps:
      package_managers: []
      packages: []
    requirements:
      runtime: "Python ≥ 3.11"
      packages:
        - "ebooklib"
        - "markdownify"
      env:
        - "OUTPUT_DIR"
    entrypoints:
      - path: "convert.py"
        symbol: null
    """.write(to: manifestURL, atomically: true, encoding: .utf8)

    let gunk = try store.insertGunk(
      sourceId: source.id,
      name: "convert",
      purpose: "EPUB to markdown",
      language: "Python",
      confidence: 0.92,
      bundlePath: tempDirectory.path,
      manifestPath: manifestURL.path,
      extractedAt: 300
    )
    try store.addGunkFile(gunkId: gunk.id, relpath: "convert.py", size: 42)
    let model = BrowseModel(store: store, loadRunTraces: { [] })

    model.refresh()
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    XCTAssertEqual(detail.requirements?.runtime, "Python ≥ 3.11")
    XCTAssertEqual(detail.requirements?.packages, ["ebooklib", "markdownify"])
    XCTAssertEqual(detail.requirements?.env, ["OUTPUT_DIR"])
  }

  func testDetailReadsEmptyRequirementsAsNonNilEmptyLists() throws {
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
    requirements:
      runtime: null
      packages: []
      env: []
    entrypoints: []
    """.write(to: manifestURL, atomically: true, encoding: .utf8)

    let gunk = try store.insertGunk(
      sourceId: source.id,
      name: "bare",
      purpose: nil,
      language: nil,
      confidence: 0.92,
      bundlePath: tempDirectory.path,
      manifestPath: manifestURL.path,
      extractedAt: 300
    )
    let model = BrowseModel(store: store, loadRunTraces: { [] })

    model.refresh()
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    XCTAssertEqual(detail.requirements?.runtime, nil)
    XCTAssertEqual(detail.requirements?.packages, [])
    XCTAssertEqual(detail.requirements?.env, [])
  }

  func testDetailRequirementsNilWhenBlockAbsent() throws {
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
    entrypoints: []
    """.write(to: manifestURL, atomically: true, encoding: .utf8)

    let gunk = try store.insertGunk(
      sourceId: source.id,
      name: "legacy",
      purpose: nil,
      language: "Swift",
      confidence: 0.92,
      bundlePath: tempDirectory.path,
      manifestPath: manifestURL.path,
      extractedAt: 300
    )
    let model = BrowseModel(store: store, loadRunTraces: { [] })

    model.refresh()
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    XCTAssertNil(detail.requirements)
  }

  // MARK: How this works analysis (T-10.14)

  func testAnalysisNilUntilGenerated() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "src", path: "/tmp/src")
    let gunk = try insertGunk(store: store, source: source, name: "mod", tags: [], confidence: 0.9)
    let model = BrowseModel(store: store, loadRunTraces: { [] })

    model.refresh()

    XCTAssertNil(model.analysis(for: gunk.id))
    XCTAssertFalse(model.isAnalyzing(gunk.id))
  }

  func testAnalysisInputCarriesModuleSignals() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "src", path: "/tmp/src")
    let gunk = try insertGunk(
      store: store,
      source: source,
      name: "mod",
      tags: [],
      language: "Python",
      confidence: 0.9,
      files: ["src/a.py", "src/b.py"]
    )
    let model = BrowseModel(store: store, loadRunTraces: { [] })
    model.refresh()
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    let input = model.analysisInput(for: detail)
    XCTAssertEqual(input.name, "mod")
    XCTAssertEqual(input.purpose, "mod purpose")
    XCTAssertEqual(input.language, "Python")
    XCTAssertEqual(input.ownedFiles, ["src/a.py", "src/b.py"])
  }

  func testGenerateAnalysisCachesAndPersists() async throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "src", path: "/tmp/src")
    let gunk = try insertGunk(
      store: store, source: source, name: "mod", tags: [], confidence: 0.9, files: ["src/a.py"]
    )
    let content = ModuleAnalysisContent(
      summary: "Summary.", dataFlow: ["one"], keyFunctions: [], touches: [], limits: []
    )
    let model = BrowseModel(
      store: store,
      loadRunTraces: { [] },
      generateAnalysis: { _ in GeneratedAnalysis(content: content, model: "test-model") }
    )
    model.refresh()
    let detail = try XCTUnwrap(model.detail(for: gunk.id))
    XCTAssertNil(model.analysis(for: gunk.id))

    let produced = await model.generateAnalysis(for: detail)

    XCTAssertEqual(produced?.content, content)
    XCTAssertEqual(model.analysis(for: gunk.id)?.content, content)
    XCTAssertEqual(model.analysis(for: gunk.id)?.model, "test-model")
    XCTAssertFalse(model.isAnalyzing(gunk.id))

    // Durable: a fresh model reads it back from the store after a refresh.
    let reopened = BrowseModel(store: store, loadRunTraces: { [] })
    reopened.refresh()
    XCTAssertEqual(reopened.analysis(for: gunk.id)?.content, content)
  }

  func testGenerateAnalysisSurfacesErrorAndLeavesCacheEmpty() async throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "src", path: "/tmp/src")
    let gunk = try insertGunk(store: store, source: source, name: "mod", tags: [], confidence: 0.9)
    let model = BrowseModel(
      store: store,
      loadRunTraces: { [] },
      generateAnalysis: { _ in throw ModuleAnalysisError.emptyAnalysis }
    )
    model.refresh()
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    let produced = await model.generateAnalysis(for: detail)

    XCTAssertNil(produced)
    XCTAssertNil(model.analysis(for: gunk.id))
    XCTAssertNotNil(model.errorMessage)
  }

  // MARK: Call it snippet (T-10.5)

  func testCallItSnippetPythonWithSymbolImportsAndCalls() {
    let snippet = CallItSnippetGenerator.snippet(
      for: BrowseEntrypoint(path: "src/audiobook_content_parsing/parser.py", symbol: "parse_epub"),
      language: "Python",
      purpose: "Parse an EPUB into markdown"
    )

    XCTAssertEqual(
      snippet.code,
      """
      # Parse an EPUB into markdown
      from audiobook_content_parsing.parser import parse_epub
      result = parse_epub(...)
      """
    )
  }

  func testCallItSnippetPythonWithoutSymbolFallsBackToPathImport() {
    let snippet = CallItSnippetGenerator.snippet(
      for: BrowseEntrypoint(path: "tools/convert.py", symbol: nil),
      language: "Python",
      purpose: nil
    )

    XCTAssertEqual(snippet.code, "import tools.convert")
  }

  func testCallItSnippetPythonPackageInitImportsAsPackage() {
    let snippet = CallItSnippetGenerator.snippet(
      for: BrowseEntrypoint(path: "slugify/__init__.py", symbol: "slugify"),
      language: "python",
      purpose: nil
    )

    XCTAssertEqual(
      snippet.code,
      """
      from slugify import slugify
      result = slugify(...)
      """
    )
  }

  func testCallItSnippetNodeWithSymbolUsesEsmImport() {
    let snippet = CallItSnippetGenerator.snippet(
      for: BrowseEntrypoint(path: "src/index.ts", symbol: "slugify"),
      language: "TypeScript",
      purpose: "Slugify a string"
    )

    XCTAssertEqual(
      snippet.code,
      """
      // Slugify a string
      import { slugify } from "./src/index";
      const result = slugify(...);
      """
    )
  }

  func testCallItSnippetNodeWithoutSymbolFallsBackToSideEffectImport() {
    let snippet = CallItSnippetGenerator.snippet(
      for: BrowseEntrypoint(path: "lib/run.js", symbol: nil),
      language: "JavaScript",
      purpose: nil
    )

    XCTAssertEqual(snippet.code, "import \"./lib/run\";")
  }

  func testCallItSnippetGenericLanguageEmitsHonestFallback() {
    let withSymbol = CallItSnippetGenerator.snippet(
      for: BrowseEntrypoint(path: "Sources/Slug/Slug.swift", symbol: "slugify"),
      language: "Swift",
      purpose: "Slugify"
    )
    XCTAssertEqual(
      withSymbol.code,
      """
      // Slugify
      // from Sources/Slug/Slug.swift
      slugify(...)
      """
    )

    let hashLanguage = CallItSnippetGenerator.snippet(
      for: BrowseEntrypoint(path: "bin/deploy.sh", symbol: nil),
      language: "Shell",
      purpose: nil
    )
    XCTAssertEqual(hashLanguage.code, "# see bin/deploy.sh")
  }

  func testCallItSnippetsPreserveEntrypointOrderWithPrimaryFirst() {
    let snippets = CallItSnippetGenerator.snippets(
      for: [
        BrowseEntrypoint(path: "src/primary.py", symbol: "main"),
        BrowseEntrypoint(path: "src/secondary.py", symbol: "helper"),
      ],
      language: "Python",
      purpose: nil
    )

    XCTAssertEqual(snippets.map(\.entrypoint.path), ["src/primary.py", "src/secondary.py"])
    XCTAssertTrue(snippets[0].code.contains("from primary import main"))
  }

  func testCallItSnippetsEmptyWhenNoEntrypoints() {
    XCTAssertTrue(
      CallItSnippetGenerator.snippets(for: [], language: "Python", purpose: "x").isEmpty
    )
  }

  func testCallItSnippetsModelMethodDerivesFromDetailLanguage() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "source", path: "/tmp/source")
    let gunk = try insertGunk(
      store: store,
      source: source,
      name: "slugifier",
      tags: [],
      language: "Python",
      confidence: 0.9,
      extractedAt: 200
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
          capability: "slugifier",
          accepted: true,
          rejectReason: nil,
          module: RunTrace.Module(
            name: "slugifier",
            ownedFiles: ["slugify.py"],
            sharedDeps: [],
            surface: [RunTrace.Surface(path: "slugify.py", symbol: "slugify")]
          )
        )
      ],
      verification: nil,
      summary: RunTrace.Summary(accepted: 1, needsApproval: 0, rejected: 0, gunkIds: [gunk.id])
    )
    let model = BrowseModel(store: store, loadRunTraces: { [trace] })

    model.refresh()
    let detail = try XCTUnwrap(model.detail(for: gunk.id))
    let snippets = model.callItSnippets(for: detail)

    XCTAssertEqual(snippets.count, 1)
    XCTAssertEqual(
      snippets[0].code,
      """
      # slugifier purpose
      from slugify import slugify
      result = slugify(...)
      """
    )
  }

  // MARK: - Smoke run ("Try it") orchestration (T-10.7)

  func testSmokeRunInputBuildsFromDetail() throws {
    let store = try makeStore()
    let bundle = try makeBundle()
    let (model, gunk) = try makeRunnableModule(store: store, bundle: bundle)
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    let input = try XCTUnwrap(model.smokeRunInput(for: detail))
    XCTAssertEqual(input.gunkId, gunk.id)
    XCTAssertEqual(input.bundlePath.path, bundle.path)
    XCTAssertEqual(input.language, .python)
    XCTAssertEqual(input.entrypoints, [Entrypoint(path: "main.py", symbol: nil)])
    XCTAssertEqual(input.origin, .human)
  }

  func testSmokeRunInputNilWithoutBundle() throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "src", path: "/tmp/src")
    let gunk = try insertGunk(store: store, source: source, name: "no-bundle", tags: [], confidence: 0.4)
    let model = BrowseModel(store: store)
    model.refresh()
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    XCTAssertNil(model.smokeRunInput(for: detail))
    XCTAssertEqual(model.runnability(for: detail), .cannotDetermine)
  }

  func testRunnabilityTerminalForPythonEntrypoint() throws {
    let store = try makeStore()
    let bundle = try makeBundle()
    let (model, gunk) = try makeRunnableModule(store: store, bundle: bundle)
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    XCTAssertEqual(model.runnability(for: detail), .terminalRunnable)
    XCTAssertEqual(model.resolvedRunCommand(for: detail), "python3 main.py")
  }

  func testRunSmokeTestStreamsAndPersistsPassedReceipt() async throws {
    let store = try makeStore()
    let bundle = try makeBundle()
    let runner = StubProcessRunner(stdout: "parsed 1 chapter\n", exitCode: 0)
    let (model, gunk) = try makeRunnableModule(store: store, bundle: bundle, runner: runner)
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    XCTAssertFalse(model.hasRunBefore(gunkId: gunk.id))
    XCTAssertNil(model.lastSmokeRun(for: gunk.id))

    var streamed = ""
    let record = await model.runSmokeTest(for: detail) { event in
      if case .stdout(let text) = event {
        streamed += text
      }
    }

    let receipt = try XCTUnwrap(record)
    XCTAssertEqual(receipt.passed, true)
    XCTAssertEqual(receipt.exitCode, 0)
    XCTAssertEqual(receipt.runnability, .terminalRunnable)
    XCTAssertEqual(receipt.origin, .human)
    XCTAssertEqual(streamed, "parsed 1 chapter\n")
    XCTAssertTrue(receipt.log.contains("parsed 1 chapter"))

    // The receipt is now the durable resting state, and consent is not re-asked.
    XCTAssertTrue(model.hasRunBefore(gunkId: gunk.id))
    XCTAssertEqual(model.lastSmokeRun(for: gunk.id)?.passed, true)
  }

  func testRunSmokeTestPersistsFailedReceipt() async throws {
    let store = try makeStore()
    let bundle = try makeBundle()
    let runner = StubProcessRunner(stderr: "Traceback...\n", exitCode: 3)
    let (model, gunk) = try makeRunnableModule(store: store, bundle: bundle, runner: runner)
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    let record = await model.runSmokeTest(for: detail) { _ in }

    let receipt = try XCTUnwrap(record)
    XCTAssertEqual(receipt.passed, false)
    XCTAssertEqual(receipt.exitCode, 3)
    XCTAssertFalse(receipt.timedOut)
    XCTAssertTrue(receipt.log.contains("Traceback"))
  }

  func testRunSmokeTestNilWhenNothingToRun() async throws {
    let store = try makeStore()
    let source = try store.insertSource(name: "src", path: "/tmp/src")
    let gunk = try insertGunk(store: store, source: source, name: "no-bundle", tags: [], confidence: 0.4)
    let model = BrowseModel(store: store)
    model.refresh()
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    let record = await model.runSmokeTest(for: detail) { _ in }
    XCTAssertNil(record)
    XCTAssertFalse(model.hasRunBefore(gunkId: gunk.id))
  }

  // MARK: - Typed input surface (T-10.8)

  func testInputSignatureInfersFileFieldFromPurpose() {
    let signature = InputSignatureInference.infer(
      entrypoints: [BrowseEntrypoint(path: "parser.py", symbol: "parse_epub")],
      language: "Python",
      purpose: "Parse an EPUB into markdown",
      requirements: nil
    )

    XCTAssertTrue(signature.reliable)
    XCTAssertEqual(signature.fields.count, 1)
    let field = try? XCTUnwrap(signature.fields.first)
    XCTAssertEqual(field?.kind, .file(extensions: ["epub"]))
    XCTAssertFalse(field?.required ?? true)
  }

  func testInputSignatureInfersFileFieldFromEntrypointFilename() {
    let signature = InputSignatureInference.infer(
      entrypoints: [BrowseEntrypoint(path: "tools/convert_pdf.py", symbol: nil)],
      language: "python",
      purpose: nil,
      requirements: nil
    )

    XCTAssertEqual(signature.fields.first?.kind, .file(extensions: ["pdf"]))
  }

  func testInputSignatureInfersTextFieldForStringUtility() {
    let signature = InputSignatureInference.infer(
      entrypoints: [BrowseEntrypoint(path: "slugify.py", symbol: "slugify")],
      language: "Python",
      purpose: "Slugify a string",
      requirements: nil
    )

    XCTAssertTrue(signature.reliable)
    XCTAssertEqual(signature.fields.first?.kind, .text)
  }

  func testInputSignatureUnreliableForVagueModule() {
    let signature = InputSignatureInference.infer(
      entrypoints: [BrowseEntrypoint(path: "main.py", symbol: "run")],
      language: "Python",
      purpose: "Do the thing",
      requirements: nil
    )

    XCTAssertFalse(signature.reliable)
    XCTAssertTrue(signature.isEmpty)
  }

  func testInputSignatureUnreliableForNonRunnableLanguage() {
    let signature = InputSignatureInference.infer(
      entrypoints: [BrowseEntrypoint(path: "Slug.swift", symbol: "slugify")],
      language: "Swift",
      purpose: "Slugify a string",
      requirements: nil
    )

    XCTAssertFalse(signature.reliable)
  }

  func testSignatureComposesPresentValuesAsPositionalArguments() {
    let signature = InputSignature(
      fields: [
        InputField(id: "input-file", label: "Input file", kind: .file(extensions: ["epub"])),
        InputField(id: "format", label: "Format", kind: .choice(options: ["md", "txt"])),
      ],
      reliable: true
    )

    // Empty values contribute nothing (the zero-touch floor: bare command).
    XCTAssertEqual(signature.arguments(from: [:]), [])
    // Present values compose in field order; whitespace-only is treated empty.
    XCTAssertEqual(
      signature.arguments(from: ["input-file": "/tmp/book.epub", "format": "  "]),
      ["/tmp/book.epub"]
    )
    XCTAssertEqual(
      signature.arguments(from: ["input-file": "/tmp/book.epub", "format": "md"]),
      ["/tmp/book.epub", "md"]
    )
  }

  func testInputValidatorFlagsMissingWrongTypeTooLargeAndNonNumber() {
    let requiredFile = InputField(
      id: "f", label: "Input file", kind: .file(extensions: ["epub"]), required: true
    )
    XCTAssertEqual(InputValidator.validate(field: requiredFile, value: ""), .missing)
    XCTAssertEqual(
      InputValidator.validate(field: requiredFile, value: "/tmp/notes.txt"),
      .wrongFileType(expected: ["epub"])
    )
    XCTAssertEqual(
      InputValidator.validate(
        field: requiredFile,
        value: "/tmp/book.epub",
        fileSizeBytes: InputLimits.maxFileBytes + 1
      ),
      .tooLarge(limitBytes: InputLimits.maxFileBytes)
    )
    XCTAssertEqual(InputValidator.validate(field: requiredFile, value: "/tmp/book.epub"), .ok)

    let number = InputField(id: "n", label: "Count", kind: .number)
    XCTAssertEqual(InputValidator.validate(field: number, value: "abc"), .notANumber)
    XCTAssertEqual(InputValidator.validate(field: number, value: "42"), .ok)
    // An optional empty field is fine (the demo-less default).
    XCTAssertEqual(InputValidator.validate(field: number, value: ""), .ok)
  }

  func testSmokeRunInputThreadsComposedArguments() throws {
    let store = try makeStore()
    let bundle = try makeBundle()
    let (model, gunk) = try makeRunnableModule(store: store, bundle: bundle)
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    let input = try XCTUnwrap(model.smokeRunInput(for: detail, arguments: ["book.epub"]))
    XCTAssertEqual(input.arguments, ["book.epub"])
    XCTAssertEqual(model.resolvedRunCommand(for: detail, arguments: ["book.epub"]), "python3 main.py book.epub")
  }

  func testRunSmokeTestUsesComposedArgumentsInReceiptCommand() async throws {
    let store = try makeStore()
    let bundle = try makeBundle()
    let (model, gunk) = try makeRunnableModule(store: store, bundle: bundle)
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    let record = await model.runSmokeTest(for: detail, arguments: ["book.epub"]) { _ in }
    let receipt = try XCTUnwrap(record)
    XCTAssertEqual(receipt.command, "python3 main.py book.epub")
  }

  func testSaveExamplePersistsDeveloperInputAsYoursClass() throws {
    let store = try makeStore()
    let bundle = try makeBundle()
    let (model, gunk) = try makeRunnableModule(store: store, bundle: bundle)
    let detail = try XCTUnwrap(model.detail(for: gunk.id))

    let saved = model.saveExample(for: detail, name: "My book", input: "book.epub")

    XCTAssertEqual(saved?.name, "My book")
    XCTAssertEqual(saved?.inputClass, .yours)
    let examples = try store.listExamples(gunkId: gunk.id)
    XCTAssertEqual(examples.map(\.name), ["My book"])
    XCTAssertEqual(examples.first?.input, "book.epub")
  }

  /// Inserts an extracted Python module whose entrypoint (`main.py`) lives in a
  /// real on-disk bundle the runner can stage, wired to a `BrowseModel` with an
  /// injected (canned) smoke runner.
  private func makeRunnableModule(
    store: Store,
    bundle: URL,
    runner: SandboxedProcessRunner = StubProcessRunner(stdout: "ok\n", exitCode: 0),
    language: String = "Python"
  ) throws -> (BrowseModel, Gunk) {
    let source = try store.insertSource(name: "src", path: "/tmp/src")
    let gunk = try store.insertGunk(
      sourceId: source.id,
      name: "parser",
      purpose: "Parse things",
      language: language,
      confidence: 0.9,
      bundlePath: bundle.path,
      manifestPath: nil,
      extractedAt: 200
    )
    let trace = RunTrace(
      runId: "run-smoke",
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
          capability: "parser",
          accepted: true,
          rejectReason: nil,
          module: RunTrace.Module(
            name: "parser",
            ownedFiles: ["main.py"],
            sharedDeps: [],
            surface: [RunTrace.Surface(path: "main.py", symbol: nil)]
          )
        )
      ],
      verification: nil,
      summary: RunTrace.Summary(accepted: 1, needsApproval: 0, rejected: 0, gunkIds: [gunk.id])
    )
    let model = BrowseModel(
      store: store,
      loadRunTraces: { [trace] },
      smokeRunner: makeSmokeRunner(runner)
    )
    model.refresh()
    return (model, gunk)
  }

  private func makeBundle(file: String = "main.py", contents: String = "print('ok')") throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let bundle = root.appendingPathComponent("bundle")
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try contents.write(to: bundle.appendingPathComponent(file), atomically: true, encoding: .utf8)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    return bundle
  }

  private func makeSmokeRunner(_ runner: SandboxedProcessRunner) -> SmokeRunner {
    let runsRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    addTeardownBlock { try? FileManager.default.removeItem(at: runsRoot) }
    return SmokeRunner(
      runsRoot: runsRoot,
      processRunner: runner,
      interpreterLocator: { _ in URL(fileURLWithPath: "/usr/bin/true") },
      useSandbox: false,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
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

/// A canned sandbox executor for the smoke-run orchestration tests: emits fixed
/// stdout/stderr through the streaming callback and returns a fixed outcome, so
/// `BrowseModel.runSmokeTest` is exercised without spawning a real process.
private final class StubProcessRunner: SandboxedProcessRunner, @unchecked Sendable {
  private let stdout: String
  private let stderr: String
  private let exitCode: Int32?
  private let timedOut: Bool

  init(stdout: String = "", stderr: String = "", exitCode: Int32? = 0, timedOut: Bool = false) {
    self.stdout = stdout
    self.stderr = stderr
    self.exitCode = exitCode
    self.timedOut = timedOut
  }

  func run(
    executable: URL,
    arguments: [String],
    workingDirectory: URL,
    environment: [String: String],
    timeoutSeconds: Double,
    onChunk: @escaping @Sendable (RunOutputChunk) -> Void
  ) async -> ProcessOutcome {
    if !stdout.isEmpty {
      onChunk(.stdout(stdout))
    }
    if !stderr.isEmpty {
      onChunk(.stderr(stderr))
    }
    return ProcessOutcome(exitCode: exitCode, timedOut: timedOut, launchError: nil)
  }
}
