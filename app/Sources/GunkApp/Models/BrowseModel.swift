import Foundation
import Observation

struct BrowseItem: Equatable, Identifiable, Sendable {
  let gunk: Gunk
  let source: Source
  let tags: [String]
  let files: [GunkFile]

  var id: Int64 {
    gunk.id
  }
}

struct BrowseSection: Equatable, Identifiable, Sendable {
  let tag: String
  let items: [BrowseItem]

  var id: String {
    tag
  }
}

struct BrowseEntrypoint: Equatable, Identifiable, Sendable {
  let path: String
  let symbol: String?

  var id: String {
    if let symbol {
      return "\(path)#\(symbol)"
    }

    return path
  }

  var label: String {
    if let symbol {
      return "\(path) · \(symbol)"
    }

    return path
  }
}

/// A generated, copyable "how do I use this" snippet (T-10.5), derived purely
/// from a module's stored entrypoint + symbol + language. Read-only/derived:
/// no schema, no store writes — it just shapes what `BrowseModel` already
/// knows into a one-glance call the developer can paste.
struct CallItSnippet: Equatable, Identifiable, Sendable {
  /// The entrypoint this snippet demonstrates (the primary one when a module
  /// exposes several — the page shows a quiet switcher for the rest).
  let entrypoint: BrowseEntrypoint
  /// The rendered code, ready for the mono block and the clipboard.
  let code: String

  var id: String {
    entrypoint.id
  }
}

/// Pure generator for the "Call it" snippet (T-10.5). Builds a short (≈2-line)
/// example call from the dominant entrypoint + symbol and language (Hard data
/// fact 4): a leading `# <purpose>` comment, then an import + a call. Where no
/// symbol exists it falls back to the path-based import; for languages it does
/// not model precisely it emits an honest, path-referencing fallback rather
/// than inventing a wrong call. No I/O, no state — trivially testable.
enum CallItSnippetGenerator {
  /// One snippet per entrypoint, in the entrypoint order the model resolved
  /// (so `.first` is the primary / dominant one the page shows by default).
  static func snippets(
    for entrypoints: [BrowseEntrypoint],
    language: String?,
    purpose: String?
  ) -> [CallItSnippet] {
    entrypoints.map { snippet(for: $0, language: language, purpose: purpose) }
  }

  static func snippet(
    for entrypoint: BrowseEntrypoint,
    language: String?,
    purpose: String?
  ) -> CallItSnippet {
    let kind = SnippetLanguage(language)
    let lines = [purposeComment(purpose, prefix: kind.commentPrefix)]
      + kind.body(for: entrypoint)
    let code = lines.compactMap { $0 }.joined(separator: "\n")
    return CallItSnippet(entrypoint: entrypoint, code: code)
  }

  /// The leading `# <purpose>` comment, collapsed to one line so a multi-line
  /// purpose never breaks the snippet. `nil` (omitted) when there is none.
  private static func purposeComment(_ purpose: String?, prefix: String) -> String? {
    guard
      let firstLine = purpose?
        .split(whereSeparator: \.isNewline)
        .first
        .map(String.init)?
        .trimmingCharacters(in: .whitespaces),
      !firstLine.isEmpty
    else {
      return nil
    }
    return "\(prefix) \(firstLine)"
  }

  /// How the snippet is shaped for a module's language. Python and Node are
  /// modeled precisely (Hard data fact 4); everything else gets a generic,
  /// honest fallback keyed only by its comment marker.
  private enum SnippetLanguage {
    case python
    case node
    case generic(commentPrefix: String)

    init(_ language: String?) {
      let normalized = (language ?? "").lowercased()
      if normalized.contains("python") {
        self = .python
      } else if normalized.contains("typescript")
        || normalized.contains("javascript")
        || normalized.contains("node")
        || normalized == "ts"
        || normalized == "js" {
        self = .node
      } else {
        self = .generic(commentPrefix: Self.commentPrefix(forHashLanguage: normalized))
      }
    }

    var commentPrefix: String {
      switch self {
      case .python:
        return "#"
      case .node:
        return "//"
      case let .generic(commentPrefix):
        return commentPrefix
      }
    }

    func body(for entrypoint: BrowseEntrypoint) -> [String] {
      switch self {
      case .python:
        let module = Self.pythonModule(from: entrypoint.path)
        if let symbol = entrypoint.symbol {
          return [
            "from \(module) import \(symbol)",
            "result = \(symbol)(...)",
          ]
        }
        return ["import \(module)"]
      case .node:
        let module = Self.nodeModule(from: entrypoint.path)
        if let symbol = entrypoint.symbol {
          return [
            "import { \(symbol) } from \"\(module)\";",
            "const result = \(symbol)(...);",
          ]
        }
        return ["import \"\(module)\";"]
      case let .generic(commentPrefix):
        if let symbol = entrypoint.symbol {
          return [
            "\(commentPrefix) from \(entrypoint.path)",
            "\(symbol)(...)",
          ]
        }
        return ["\(commentPrefix) see \(entrypoint.path)"]
      }
    }

    /// `#`-style comment languages (so the fallback reads natively); the
    /// default is `//`, which covers Swift/Go/Rust/Java/C-family/Kotlin/etc.
    private static func commentPrefix(forHashLanguage normalized: String) -> String {
      let hashLanguages = ["ruby", "shell", "bash", "sh", "zsh", "perl", "r", "yaml", "toml", "elixir"]
      return hashLanguages.contains(where: normalized.contains) ? "#" : "//"
    }

    /// Derives an importable Python module path from a bundle-relative file
    /// path: drop a leading `src/`, drop the `.py` extension (and a trailing
    /// `__init__` so a package imports as the package), and join segments with
    /// dots. `audiobook_content_parsing/parser.py` → `audiobook_content_parsing.parser`.
    static func pythonModule(from path: String) -> String {
      var segments = normalizedSegments(from: path)
      if segments.first == "src" {
        segments.removeFirst()
      }
      if let last = segments.last {
        segments[segments.count - 1] = stripExtension(last)
      }
      if segments.last == "__init__" {
        segments.removeLast()
      }
      let module = segments.joined(separator: ".")
      return module.isEmpty ? "module" : module
    }

    /// Derives a JS/TS import specifier: keep the relative path, drop the
    /// extension, and ensure a leading `./` so it reads as a local import.
    /// `src/index.ts` → `./src/index`.
    static func nodeModule(from path: String) -> String {
      let segments = normalizedSegments(from: path)
      guard !segments.isEmpty else {
        return "./module"
      }
      var trimmed = segments
      trimmed[trimmed.count - 1] = stripExtension(trimmed[trimmed.count - 1])
      let joined = trimmed.joined(separator: "/")
      return joined.hasPrefix(".") ? joined : "./\(joined)"
    }

    private static func normalizedSegments(from path: String) -> [String] {
      path
        .replacingOccurrences(of: "\\", with: "/")
        .split(separator: "/")
        .map(String.init)
        .filter { $0 != "." && !$0.isEmpty }
    }

    private static func stripExtension(_ filename: String) -> String {
      guard let dot = filename.lastIndex(of: "."), dot != filename.startIndex else {
        return filename
      }
      return String(filename[filename.startIndex..<dot])
    }
  }
}

struct BrowseSelfContainmentResult: Equatable, Sendable {
  let imports: String
  let entrypoint: String
  let danglingImports: [RunTrace.DanglingImport]
  let missingEntrypoints: [RunTrace.MissingEntrypoint]

  var passed: Bool {
    imports == "pass" && entrypoint == "pass"
  }
}

struct BrowseBuildVerificationResult: Equatable, Sendable {
  let language: String
  let built: Bool
  let skipped: Bool
  let command: String?
  let log: String
}

struct BrowseModuleDetail: Equatable, Sendable {
  let item: BrowseItem
  let ownedFiles: [String]
  let sharedDependencies: [String]
  let entrypoints: [BrowseEntrypoint]
  let bundlePath: String?
  let selfContainment: BrowseSelfContainmentResult?
  let buildVerification: BrowseBuildVerificationResult?
  /// The portability readout (T-10.6), read from the bundle's `gunk.yml`.
  /// `nil` for bundles extracted before the block existed — the page then
  /// shows `none` honestly rather than inventing requirements.
  let requirements: ModuleRequirements?
}

private struct BrowseTraceModuleRecord: Equatable {
  let ownedFiles: [String]
  let sharedDependencies: [String]
  let entrypoints: [BrowseEntrypoint]
}

/// The toolbox-v2 grouping toggle: by source project or by the model that
/// extracted each module. (The old Tag/Source/Language/Approval *grouping*
/// is replaced by this; those dimensions survive as filters.)
enum BrowseGroup: String, CaseIterable, Identifiable, Sendable {
  case project
  case model

  var id: String {
    rawValue
  }

  var label: String {
    switch self {
    case .project:
      return "Project"
    case .model:
      return "Model"
    }
  }
}

/// Which provider · model extracted a module. Prefers the durable stored
/// value (T-9.2); falls back to the `RunTrace`-derived lookup when a module
/// predates attribution.
struct BrowseProvenance: Equatable, Sendable {
  let provider: String
  let model: String

  var label: String {
    "\(provider) · \(model)"
  }
}

enum BrowseApprovalFilter: String, CaseIterable, Identifiable, Sendable {
  case all
  case autoAccepted
  case approved
  case needsApproval

  var id: String {
    rawValue
  }

  var label: String {
    switch self {
    case .all:
      return "All"
    case .autoAccepted:
      return "Auto accepted"
    case .approved:
      return "Approved"
    case .needsApproval:
      return "Needs approval"
    }
  }
}

struct BrowseFilters: Equatable, Sendable {
  var group: BrowseGroup = .project
  var query: String = ""
  var sourceId: Int64?
  var tag: String?
  var language: String?
  var approval: BrowseApprovalFilter = .all
}

@MainActor
@Observable
final class BrowseModel {
  typealias ExtractGunk = @MainActor (Gunk) throws -> Void
  typealias ReclassifySource = @MainActor (Int64) throws -> Void
  typealias LoadRunTraces = @MainActor () -> [RunTrace]

  private let store: Store
  /// The auto-accept gate the approval queue is computed from
  /// (`isPendingApproval`). Exposed so review copy ("62% — below the 70%
  /// auto-accept threshold") derives from the same constant the queue rule
  /// gates on and the two can never disagree. Note B1: this is hard-coded
  /// to `Extractor.defaultConfidenceThreshold` (0.7) today; the Settings
  /// slider is cosmetic until Phase 11.
  let confidenceThreshold: Double
  private let extractGunk: ExtractGunk
  private let reclassifySource: ReclassifySource
  private let loadRunTraces: LoadRunTraces
  /// The sandbox runner that executes a module's entrypoint (T-10.2). Injected
  /// so the smoke-run orchestration is testable with a canned executor; the
  /// production default wraps runs in `sandbox-exec` (ADR-0016).
  private let smokeRunner: SmokeRunner

  private(set) var sections: [BrowseSection] = []
  private(set) var approvalQueue: [BrowseItem] = []
  private(set) var availableSources: [Source] = []
  private(set) var availableTags: [String] = []
  private(set) var availableLanguages: [String] = []
  private(set) var errorMessage: String?
  var filters = BrowseFilters() {
    didSet {
      applyFilters()
    }
  }

  private var items: [BrowseItem] = []

  /// Every loaded module id, regardless of the active filters. The Library
  /// grid diffs this across a run to give freshly created modules the arrival
  /// highlight (ux §4.4, moved here from the retired Sources surface).
  var loadedGunkIds: Set<Int64> {
    Set(items.map(\.id))
  }

  private var traceModuleRecords: [Int64: BrowseTraceModuleRecord] = [:]
  private var selfContainmentByGunkId: [Int64: BrowseSelfContainmentResult] = [:]
  private var buildVerificationByBundlePath: [String: BrowseBuildVerificationResult] = [:]
  /// Trace-derived provenance, used only as the fallback when a module has no
  /// durable stored value (T-9.2). Shared resolution with `ProvenanceBackfill`.
  private var traceProvenance = RunTraceProvenanceIndex(traces: [])

  init(
    store: Store,
    confidenceThreshold: Double = Extractor.defaultConfidenceThreshold,
    extractGunk: ExtractGunk? = nil,
    reclassifySource: @escaping ReclassifySource = { _ in },
    loadRunTraces: @escaping LoadRunTraces = {
      RunTraceStore().recentTraces(limit: 250)
    },
    smokeRunner: SmokeRunner = SmokeRunner()
  ) {
    self.store = store
    self.confidenceThreshold = confidenceThreshold
    self.extractGunk = extractGunk ?? { gunk in
      _ = try Extractor(
        store: store,
        confidenceThreshold: 0
      ).extract(gunk: gunk)
    }
    self.reclassifySource = reclassifySource
    self.loadRunTraces = loadRunTraces
    self.smokeRunner = smokeRunner
  }

  func refresh() {
    do {
      let items = try loadItems()
      self.items = items
      indexTraces(loadRunTraces(), items: items)
      approvalQueue = items
        .filter(isPendingApproval)
        .sorted(by: itemSort)
      availableSources = availableSources(from: items)
      availableTags = availableTags(from: items)
      availableLanguages = availableLanguages(from: items)
      sanitizeFilters()
      applyFilters()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func approve(gunkId: Int64) {
    do {
      try store.approveGunk(id: gunkId)

      if let approved = try store.gunk(id: gunkId) {
        try extractGunk(approved)
      }

      refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func delete(gunkId: Int64) {
    do {
      try store.removeGunk(id: gunkId)
      refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func reject(gunkId: Int64) {
    delete(gunkId: gunkId)
  }

  func reclassify(sourceId: Int64) {
    do {
      try reclassifySource(sourceId)
      refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Total modules loaded, regardless of filters — the Library header's
  /// count chip.
  var totalModuleCount: Int {
    items.count
  }

  /// The distinct source project/folder names for a set of loaded gunk ids,
  /// sorted for stable copy. Used by the run-end toast's View action to scope
  /// the Library to the project(s) a run actually added modules to.
  func projectNames(for gunkIds: Set<Int64>) -> [String] {
    let names = items
      .filter { gunkIds.contains($0.id) }
      .map(\.source.name)
    return Array(Set(names)).sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }
  }

  /// The provider · model that extracted this module. Prefers the **durable
  /// stored value** (T-9.2) so attribution survives trace pruning; falls back
  /// to the trace-derived lookup (gunk-id, then the source's most recent run)
  /// so nothing regresses for modules not yet attributed.
  func provenance(for item: BrowseItem) -> BrowseProvenance? {
    if let provider = item.gunk.provider, let model = item.gunk.model {
      return BrowseProvenance(provider: provider, model: model)
    }

    return traceProvenance.provenance(gunkId: item.gunk.id, sourceId: item.source.id)
  }

  func detail(for gunkId: Int64) -> BrowseModuleDetail? {
    guard let item = items.first(where: { $0.gunk.id == gunkId }) else {
      return nil
    }

    let traceRecord = traceModuleRecords[gunkId]
    let ownedFiles = nonEmpty(
      traceRecord?.ownedFiles,
      fallback: item.files.map(\.relpath)
    )
    let entrypoints = nonEmpty(
      traceRecord?.entrypoints,
      fallback: manifestEntrypoints(for: item.gunk)
    )

    return BrowseModuleDetail(
      item: item,
      ownedFiles: ownedFiles,
      sharedDependencies: traceRecord?.sharedDependencies ?? [],
      entrypoints: entrypoints,
      bundlePath: item.gunk.bundlePath,
      selfContainment: selfContainmentByGunkId[gunkId],
      buildVerification: buildVerification(for: item.gunk),
      requirements: manifestRequirements(for: item.gunk)
    )
  }

  /// The "Call it" snippets (T-10.5) for a module — one per stored entrypoint,
  /// primary first. A read-only derivation over the entrypoints + language the
  /// detail already carries; no store state.
  func callItSnippets(for detail: BrowseModuleDetail) -> [CallItSnippet] {
    CallItSnippetGenerator.snippets(
      for: detail.entrypoints,
      language: detail.item.gunk.language,
      purpose: detail.item.gunk.purpose
    )
  }

  // MARK: - Smoke run ("Try it") orchestration (T-10.7)

  /// Assembles the runner's `RunInput` for a module's smoke run from its stored
  /// bundle, language, entrypoints, and declared packages (the dependency list
  /// the classifier keys on — never installed here). Returns `nil` when the
  /// module has no extracted bundle to stage, so the page shows nothing to run
  /// rather than guessing.
  func smokeRunInput(for detail: BrowseModuleDetail, origin: RunOrigin = .human) -> RunInput? {
    guard let bundlePath = detail.bundlePath else {
      return nil
    }

    return RunInput(
      gunkId: detail.item.gunk.id,
      bundlePath: URL(fileURLWithPath: bundlePath),
      language: ModuleLanguage(rawLanguage: detail.item.gunk.language ?? ""),
      entrypoints: detail.entrypoints.map { Entrypoint(path: $0.path, symbol: $0.symbol) },
      dependencies: detail.requirements?.packages ?? [],
      origin: origin
    )
  }

  /// The runnability classification (T-10.2) for a module, computed up front so
  /// the page offers a Run button only for `.terminalRunnable` modules and
  /// renders an honest, neutral "runnable here: not yet" state for everything
  /// else (never a failure). `nil` bundle → `.cannotDetermine`.
  func runnability(for detail: BrowseModuleDetail) -> Runnability {
    guard let input = smokeRunInput(for: detail) else {
      return .cannotDetermine
    }

    return RunnabilityClassifier.classify(input)
  }

  /// The resolved command line a smoke run would execute, for the first-run
  /// consent treatment. `nil` when no command can be derived.
  func resolvedRunCommand(for detail: BrowseModuleDetail) -> String? {
    guard let input = smokeRunInput(for: detail) else {
      return nil
    }

    return EntrypointResolver.resolve(input)?.display
  }

  /// The most recent smoke-run receipt for a module — the resting state shown
  /// on re-visit (T-10.3). `nil` when the module has never been tried.
  func lastSmokeRun(for gunkId: Int64) -> SmokeRunRecord? {
    (try? store.mostRecentSmokeRun(gunkId: gunkId)) ?? nil
  }

  /// Whether the developer has already consented to and run this module, so the
  /// first-run consent treatment is not shown again. Inferred from the presence
  /// of any persisted receipt — which only exists *after* a consented run — so
  /// consent survives an app relaunch without a separate consent table.
  func hasRunBefore(gunkId: Int64) -> Bool {
    lastSmokeRun(for: gunkId) != nil
  }

  /// Runs a module's smoke test in **streaming** mode: forwards every runner
  /// event to `emit` (incremental stdout/stderr for the live terminal), then
  /// persists the receipt (T-10.3) and returns it. Returns `nil` only when
  /// there is nothing to run (no bundle). The runner itself does no store
  /// writes — persistence lives here (the console's door) and in the MCP tool
  /// (T-10.12).
  @discardableResult
  func runSmokeTest(
    for detail: BrowseModuleDetail,
    origin: RunOrigin = .human,
    emit: @escaping (RunStreamEvent) -> Void
  ) async -> SmokeRunRecord? {
    guard let input = smokeRunInput(for: detail, origin: origin) else {
      return nil
    }

    var finalResult: SmokeRunResult?
    do {
      for try await event in smokeRunner.runStreaming(input) {
        emit(event)
        if case .finished(let result) = event {
          finalResult = result
        }
      }
    } catch {
      errorMessage = error.localizedDescription
    }

    guard let result = finalResult else {
      return nil
    }

    do {
      return try store.recordSmokeRun(gunkId: detail.item.gunk.id, result: result)
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }

  private func loadItems() throws -> [BrowseItem] {
    let sourcesById = Dictionary(uniqueKeysWithValues: try store.listSources().map { ($0.id, $0) })

    return try store.listGunks().compactMap { gunk in
      var source = sourcesById[gunk.sourceId]

      if source == nil {
        source = try store.source(id: gunk.sourceId)
      }

      guard let source else {
        return nil
      }

      return BrowseItem(
        gunk: gunk,
        source: source,
        tags: try store.listGunkTags(gunkId: gunk.id).map(\.tag),
        files: try store.filesForGunk(gunkId: gunk.id)
      )
    }
  }

  private func indexTraces(_ traces: [RunTrace], items: [BrowseItem]) {
    traceModuleRecords = [:]
    selfContainmentByGunkId = [:]
    buildVerificationByBundlePath = [:]
    traceProvenance = RunTraceProvenanceIndex(traces: traces)

    // Traces arrive newest-first (`RunTraceStore.recentTraces`); first-wins
    // below therefore means "most recent run".
    for trace in traces {
      indexBuildVerification(trace)

      let traceGunkIds = Set(trace.summary.gunkIds)
      let traceItems: [BrowseItem]
      if traceGunkIds.isEmpty, let sourceId = trace.sourceId {
        traceItems = items.filter { $0.source.id == sourceId }
      } else {
        traceItems = items.filter { traceGunkIds.contains($0.gunk.id) }
      }
      guard !traceItems.isEmpty else {
        continue
      }

      let refinementsByName = Dictionary(grouping: trace.refinements ?? []) { refinement in
        refinement.module?.name ?? refinement.capability
      }
      let selfContainmentByName = Dictionary(
        grouping: trace.verification?.selfContainment ?? [],
        by: \.moduleName
      )

      for item in traceItems {
        if traceModuleRecords[item.gunk.id] == nil,
           let module = refinementsByName[item.gunk.name]?.compactMap(\.module).first {
          traceModuleRecords[item.gunk.id] = BrowseTraceModuleRecord(
            ownedFiles: module.ownedFiles ?? [],
            sharedDependencies: module.sharedDeps ?? [],
            entrypoints: (module.surface ?? []).map {
              BrowseEntrypoint(path: $0.path, symbol: $0.symbol)
            }
          )
        }

        if selfContainmentByGunkId[item.gunk.id] == nil,
           let result = selfContainmentByName[item.gunk.name]?.first {
          selfContainmentByGunkId[item.gunk.id] = BrowseSelfContainmentResult(
            imports: result.imports,
            entrypoint: result.entrypoint,
            danglingImports: result.danglingImports,
            missingEntrypoints: result.missingEntrypoints
          )
        }
      }
    }
  }

  private func indexBuildVerification(_ trace: RunTrace) {
    for result in trace.verification?.build ?? [] {
      let key = normalizedPath(result.bundlePath)
      guard buildVerificationByBundlePath[key] == nil else {
        continue
      }

      buildVerificationByBundlePath[key] = BrowseBuildVerificationResult(
        language: result.language,
        built: result.built,
        skipped: result.skipped,
        command: result.command,
        log: result.log
      )
    }
  }

  private func buildVerification(for gunk: Gunk) -> BrowseBuildVerificationResult? {
    guard let bundlePath = gunk.bundlePath else {
      return nil
    }

    return buildVerificationByBundlePath[normalizedPath(bundlePath)]
  }

  private func manifestEntrypoints(for gunk: Gunk) -> [BrowseEntrypoint] {
    guard let manifestPath = gunk.manifestPath,
          let contents = try? String(contentsOfFile: manifestPath, encoding: .utf8) else {
      return []
    }

    var entrypoints: [BrowseEntrypoint] = []
    var inEntrypoints = false
    var pendingPath: String?

    for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
      if line == "entrypoints:" {
        inEntrypoints = true
        continue
      }

      if inEntrypoints && !line.hasPrefix(" ") {
        break
      }

      guard inEntrypoints else {
        continue
      }

      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("- path:") {
        if let pendingPath {
          entrypoints.append(BrowseEntrypoint(path: pendingPath, symbol: nil))
        }
        pendingPath = yamlValue(after: "- path:", in: trimmed)
      } else if trimmed.hasPrefix("symbol:"),
                let path = pendingPath {
        entrypoints.append(
          BrowseEntrypoint(path: path, symbol: yamlValue(after: "symbol:", in: trimmed))
        )
        pendingPath = nil
      }
    }

    if let pendingPath {
      entrypoints.append(BrowseEntrypoint(path: pendingPath, symbol: nil))
    }

    return entrypoints
  }

  /// Reads the `requirements:` block (T-10.6) from the bundle's `gunk.yml`,
  /// using the same lightweight line parser as `manifestEntrypoints`. Returns
  /// `nil` when the block is absent (older bundles) so the page degrades to
  /// `none` instead of inventing requirements.
  private func manifestRequirements(for gunk: Gunk) -> ModuleRequirements? {
    guard let manifestPath = gunk.manifestPath,
          let contents = try? String(contentsOfFile: manifestPath, encoding: .utf8) else {
      return nil
    }

    var inRequirements = false
    var sawBlock = false
    var runtime: String?
    var packages: [String] = []
    var env: [String] = []
    // Which nested list the indented `- value` lines currently belong to.
    var currentList: String?

    for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine)
      if line == "requirements:" {
        inRequirements = true
        sawBlock = true
        continue
      }

      guard inRequirements else {
        continue
      }

      // A non-indented line ends the block.
      if !line.hasPrefix(" ") {
        break
      }

      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Keys directly under `requirements:` are indented two spaces; list items
      // are indented four. Distinguish them so `- foo` is not read as a key.
      if line.hasPrefix("  ") && !line.hasPrefix("    ") {
        if trimmed.hasPrefix("runtime:") {
          runtime = yamlValue(after: "runtime:", in: trimmed)
          currentList = nil
        } else if trimmed.hasPrefix("packages:") {
          currentList = yamlIsInlineEmptyList(after: "packages:", in: trimmed) ? nil : "packages"
        } else if trimmed.hasPrefix("env:") {
          currentList = yamlIsInlineEmptyList(after: "env:", in: trimmed) ? nil : "env"
        } else {
          currentList = nil
        }
      } else if trimmed.hasPrefix("-"), let currentList,
                let value = yamlValue(after: "-", in: trimmed) {
        switch currentList {
        case "packages":
          packages.append(value)
        case "env":
          env.append(value)
        default:
          break
        }
      }
    }

    guard sawBlock else {
      return nil
    }

    return ModuleRequirements(runtime: runtime, packages: packages, env: env)
  }

  private func yamlIsInlineEmptyList(after prefix: String, in line: String) -> Bool {
    line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces) == "[]"
  }

  private func yamlValue(after prefix: String, in line: String) -> String? {
    let value = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    if value == "null" || value.isEmpty {
      return nil
    }

    guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else {
      return value
    }

    let body = value.dropFirst().dropLast()
    return body
      .replacingOccurrences(of: "\\n", with: "\n")
      .replacingOccurrences(of: "\\\"", with: "\"")
      .replacingOccurrences(of: "\\\\", with: "\\")
  }

  private func normalizedPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
  }

  private func nonEmpty<Value>(_ values: [Value]?, fallback: [Value]) -> [Value] {
    guard let values, !values.isEmpty else {
      return fallback
    }

    return values
  }

  static let unknownModelSection = "Unknown model"

  private func groupedSections(from items: [BrowseItem]) -> [BrowseSection] {
    var buckets: [String: [BrowseItem]] = [:]

    for item in items {
      let groupName: String
      switch filters.group {
      case .project:
        groupName = item.source.name
      case .model:
        groupName = provenance(for: item)?.label ?? Self.unknownModelSection
      }

      buckets[groupName, default: []].append(item)
    }

    // Section items are hero-rank ordered: the grid promotes the first item
    // of each group to the hero cell.
    return buckets
      .map { groupName, items in
        BrowseSection(tag: groupName, items: items.sorted(by: heroRank))
      }
      .sorted { lhs, rhs in
        lhs.tag.localizedStandardCompare(rhs.tag) == .orderedAscending
      }
  }

  /// Hero election order within a group: agent-ready (extracted) first, then
  /// confidence descending, then name. All-equal groups fall through to name
  /// order; a single-item group makes that item the hero.
  /// FUTURE: rank by uses/week once usage telemetry exists — swap only this
  /// comparator.
  func heroRank(_ lhs: BrowseItem, _ rhs: BrowseItem) -> Bool {
    let lhsReady = lhs.gunk.extractedAt != nil
    let rhsReady = rhs.gunk.extractedAt != nil
    if lhsReady != rhsReady {
      return lhsReady
    }

    return itemSort(lhs, rhs)
  }

  private func applyFilters() {
    sections = groupedSections(from: filteredItems())
  }

  private func filteredItems() -> [BrowseItem] {
    let query = filters.query.trimmingCharacters(in: .whitespaces)

    return items.filter { item in
      if !query.isEmpty, !matches(item, query: query) {
        return false
      }

      if let sourceId = filters.sourceId, item.source.id != sourceId {
        return false
      }

      if let tag = filters.tag, !item.tags.contains(tag) {
        return false
      }

      if let language = filters.language, item.gunk.language != language {
        return false
      }

      switch filters.approval {
      case .all:
        return true
      case .autoAccepted:
        return approvalFilter(for: item) == .autoAccepted
      case .approved:
        return approvalFilter(for: item) == .approved
      case .needsApproval:
        return approvalFilter(for: item) == .needsApproval
      }
    }
  }

  /// Case-insensitive search across name, purpose, tags, and the source
  /// project/folder name (so typing a folder name scopes the grid to that
  /// project — the same string the project grouping headers and the run-end
  /// View action use).
  private func matches(_ item: BrowseItem, query: String) -> Bool {
    var haystack = [item.gunk.name, item.source.name] + item.tags
    if let purpose = item.gunk.purpose {
      haystack.append(purpose)
    }

    return haystack.contains { value in
      value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }

  private func sanitizeFilters() {
    if let sourceId = filters.sourceId,
       !availableSources.contains(where: { $0.id == sourceId }) {
      filters.sourceId = nil
    }

    if let tag = filters.tag,
       !availableTags.contains(tag) {
      filters.tag = nil
    }

    if let language = filters.language,
       !availableLanguages.contains(language) {
      filters.language = nil
    }
  }

  private func availableSources(from items: [BrowseItem]) -> [Source] {
    Dictionary(grouping: items.map(\.source), by: \.id)
      .compactMap { _, sources in sources.first }
      .sorted { lhs, rhs in
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
      }
  }

  private func availableTags(from items: [BrowseItem]) -> [String] {
    Array(Set(items.flatMap(\.tags)))
      .sorted { lhs, rhs in
        lhs.localizedStandardCompare(rhs) == .orderedAscending
      }
  }

  private func availableLanguages(from items: [BrowseItem]) -> [String] {
    Array(Set(items.compactMap(\.gunk.language)))
      .sorted { lhs, rhs in
        lhs.localizedStandardCompare(rhs) == .orderedAscending
      }
  }

  private func isPendingApproval(_ item: BrowseItem) -> Bool {
    (item.gunk.confidence ?? 0) < confidenceThreshold
      && item.gunk.approvedAt == nil
      && item.gunk.extractedAt == nil
  }

  func approvalFilter(for item: BrowseItem) -> BrowseApprovalFilter {
    if isPendingApproval(item) {
      return .needsApproval
    }

    if item.gunk.approvedAt != nil {
      return .approved
    }

    return .autoAccepted
  }

  func approvalLabel(for item: BrowseItem) -> String {
    approvalFilter(for: item).label
  }

  func languageLabel(for item: BrowseItem) -> String {
    item.gunk.language ?? "Unknown language"
  }

  private func itemSort(_ lhs: BrowseItem, _ rhs: BrowseItem) -> Bool {
    let lhsConfidence = lhs.gunk.confidence ?? 0
    let rhsConfidence = rhs.gunk.confidence ?? 0

    if lhsConfidence != rhsConfidence {
      return lhsConfidence > rhsConfidence
    }

    return lhs.gunk.name.localizedStandardCompare(rhs.gunk.name) == .orderedAscending
  }
}
