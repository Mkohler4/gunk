import Foundation

enum DecompositionPipelineStage: String, Equatable, Sendable {
  case scan
  case symbols
  case graph
  case fingerprints
  case repoMap
  case survey
  case expansion
  case refine
  case qualityGates
  case persist
  case extract
}

struct DecompositionPipelineProgress: Equatable, Sendable {
  let stage: DecompositionPipelineStage
  let fraction: Double
  let modulesFound: Int?
}

struct DecompositionPipelineOptions: Equatable, Sendable {
  let contextBudgetTokens: Int
  let confidenceThreshold: Double

  init(
    contextBudgetTokens: Int = 20_000,
    confidenceThreshold: Double = Extractor.defaultConfidenceThreshold
  ) {
    self.contextBudgetTokens = contextBudgetTokens
    self.confidenceThreshold = confidenceThreshold
  }
}

final class DecompositionPipeline {
  typealias ProgressHandler = (DecompositionPipelineProgress) -> Void

  private let store: Store
  private let provider: LLMProvider
  private let model: String
  private let options: DecompositionPipelineOptions
  private let fileManager: FileManager
  private let gunkHome: URL
  private let symbolExtractor: SymbolExtractor
  private let manifestParser: DependencyManifestParser
  private let fingerprintBuilder: CapabilityFingerprintBuilder
  private let embeddingIndex: EmbeddingIndex?
  private let progress: ProgressHandler

  init(
    store: Store,
    provider: LLMProvider,
    model: String,
    options: DecompositionPipelineOptions = DecompositionPipelineOptions(),
    fileManager: FileManager = .default,
    gunkHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gunk"),
    symbolExtractor: SymbolExtractor = TreeSitterSymbolExtractor(),
    manifestParser: DependencyManifestParser = DependencyManifestParser(),
    fingerprintBuilder: CapabilityFingerprintBuilder = CapabilityFingerprintBuilder(),
    embeddingIndex: EmbeddingIndex? = nil,
    progress: @escaping ProgressHandler = { _ in }
  ) {
    self.store = store
    self.provider = provider
    self.model = model
    self.options = options
    self.fileManager = fileManager
    self.gunkHome = gunkHome
    self.symbolExtractor = symbolExtractor
    self.manifestParser = manifestParser
    self.fingerprintBuilder = fingerprintBuilder
    self.embeddingIndex = embeddingIndex
    self.progress = progress
  }

  func run(source: Source, using client: LLMClient) async throws -> [Gunk] {
    let sourceURL = URL(fileURLWithPath: source.path)
    let scannedFiles = try SourceScanner(
      fileManager: fileManager,
      store: store,
      sourceId: source.id
    ).scan(folder: sourceURL)
    report(.scan, 0.10)

    let contentsByPath = try readContents(files: scannedFiles)
    let fileSymbols = scannedFiles.map { file in
      symbols(for: file, contents: contentsByPath[file.relpath] ?? "")
    }
    report(.symbols, 0.20)

    let resolver = ImportResolver(config: .init(sourceFiles: Set(scannedFiles.map(\.relpath))))
    let graph = CodeGraphBuilder(resolver: resolver).build(
      files: fileSymbols,
      contentsByPath: contentsByPath
    )
    report(.graph, 0.30)

    let manifests = manifestParser.parse(manifests: manifestContents(contentsByPath))
    let fingerprints = fingerprintBuilder.fingerprints(
      files: fileSymbols,
      manifests: manifests,
      contentsByPath: contentsByPath
    )
    report(.fingerprints, 0.38)

    let repoMap = try ContextBuilder(
      fileManager: fileManager,
      symbolExtractor: symbolExtractor,
      manifestParser: manifestParser,
      fingerprintBuilder: fingerprintBuilder
    )
    .buildRepoMap(files: scannedFiles)
    .serialized(budgetTokens: options.contextBudgetTokens)
    report(.repoMap, 0.48)

    let hypotheses = try await CapabilitySurvey(
      store: store,
      provider: provider,
      model: model
    )
    .survey(source: source, repoMap: repoMap, using: client)
    report(.survey, 0.58)

    let expansions = CapabilityExpander().expand(hypotheses: hypotheses, graph: graph)
    report(.expansion, 0.66)

    let modules = try await CapabilityRefiner(
      store: store,
      provider: provider,
      model: model
    )
    .refine(
      source: source,
      expansions: expansions,
      contentsByPath: contentsByPath,
      using: client
    )
    report(.refine, 0.78, modulesFound: modules.count)

    let evaluations = ModuleQualityGate(
      options: ModuleQualityGateOptions(confidenceThreshold: options.confidenceThreshold)
    )
    .evaluate(
      modules: modules,
      fingerprints: fingerprints,
      graph: graph,
      contentsByPath: contentsByPath
    )
    let persistableEvaluations = evaluations.filter { evaluation in
      evaluation.decision == .accepted || evaluation.decision == .needsApproval
    }
    report(.qualityGates, 0.84, modulesFound: persistableEvaluations.count)

    let persisted = try persist(evaluations: persistableEvaluations, source: source)
    report(.persist, 0.92, modulesFound: persisted.count)

    let gunks = try await extractAcceptedGunks(persisted)
    report(.extract, 1, modulesFound: gunks.count)

    return gunks
  }

  private func readContents(files: [ScannedFile]) throws -> [String: String] {
    try Dictionary(uniqueKeysWithValues: files.map { file in
      let data = try Data(contentsOf: file.url)
      return (file.relpath, String(decoding: data, as: UTF8.self))
    })
  }

  private func symbols(for file: ScannedFile, contents: String) -> FileSymbols {
    do {
      return try symbolExtractor.extract(file: SymbolFile(path: file.relpath, contents: contents))
    } catch {
      return FileSymbols(
        path: file.relpath,
        language: LanguageKind(path: file.relpath),
        symbols: [],
        imports: [],
        exports: []
      )
    }
  }

  private func manifestContents(_ contentsByPath: [String: String]) -> [String: String] {
    contentsByPath.filter { path, _ in
      let basename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
      return [
        "package.json",
        "package.swift",
        "pyproject.toml",
        "requirements.txt",
        "go.mod",
        "cargo.toml"
      ].contains(basename)
    }
  }

  private func persist(
    evaluations: [ModuleQualityGateEvaluation],
    source: Source
  ) throws -> [PersistedModule] {
    let sourceFileByPath = Dictionary(
      uniqueKeysWithValues: try store.filesForSource(sourceId: source.id).map { ($0.relpath, $0) }
    )
    let tagByName = Dictionary(uniqueKeysWithValues: try store.listTags().map { ($0.name, $0) })
    var persisted: [PersistedModule] = []

    for evaluation in evaluations {
      let module = evaluation.module
      let gunk = try store.insertGunk(
        sourceId: source.id,
        name: module.name,
        purpose: module.purpose,
        language: module.language,
        confidence: module.confidence
      )

      for tagName in module.tags {
        guard let tag = tagByName[tagName] else {
          continue
        }

        try store.addGunkTag(
          gunkId: gunk.id,
          tagId: tag.id,
          confidence: module.confidence
        )
      }

      for relpath in module.files.uniqued() {
        try store.addGunkFile(
          gunkId: gunk.id,
          relpath: relpath,
          size: sourceFileByPath[relpath]?.size
        )
      }

      persisted.append(PersistedModule(gunk: gunk, evaluation: evaluation))
    }

    return persisted
  }

  private func extractAcceptedGunks(_ persisted: [PersistedModule]) async throws -> [Gunk] {
    let extractor = Extractor(
      store: store,
      gunkHome: gunkHome,
      confidenceThreshold: options.confidenceThreshold,
      fileManager: fileManager
    )
    var gunks: [Gunk] = []

    for persistedModule in persisted {
      let gunk = persistedModule.gunk

      if persistedModule.evaluation.decision == .accepted {
        _ = try extractor.extract(gunk: gunk)
        let extracted = try store.gunk(id: gunk.id) ?? gunk
        if let embeddingIndex {
          _ = try? await embeddingIndex.index(gunk: extracted)
        }
        gunks.append(extracted)
      } else {
        gunks.append(gunk)
      }
    }

    return gunks
  }

  private func report(
    _ stage: DecompositionPipelineStage,
    _ fraction: Double,
    modulesFound: Int? = nil
  ) {
    progress(
      DecompositionPipelineProgress(
        stage: stage,
        fraction: fraction.clamped(to: 0...1),
        modulesFound: modulesFound
      )
    )
  }
}

private struct PersistedModule {
  let gunk: Gunk
  let evaluation: ModuleQualityGateEvaluation
}

private extension Array where Element: Hashable {
  func uniqued() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}

private extension Double {
  func clamped(to range: ClosedRange<Double>) -> Double {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
