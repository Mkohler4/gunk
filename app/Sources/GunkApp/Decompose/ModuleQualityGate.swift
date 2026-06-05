import Foundation

struct ModuleQualityGateOptions: Equatable, Sendable {
  let confidenceThreshold: Double
  let cohesionThreshold: Double
  let duplicateOverlapThreshold: Double

  init(
    confidenceThreshold: Double = 0.7,
    cohesionThreshold: Double = 0.35,
    duplicateOverlapThreshold: Double = 0.85
  ) {
    self.confidenceThreshold = confidenceThreshold
    self.cohesionThreshold = cohesionThreshold
    self.duplicateOverlapThreshold = duplicateOverlapThreshold
  }
}

enum ModuleQualityGateDecision: Equatable, Sendable {
  case accepted
  case needsApproval
  case rejected
}

enum ModuleQualityGateReason: String, Equatable, Hashable, Sendable {
  case belowConfidenceThreshold
  case duplicateOverlap
  case generatedOnly
  case lowCohesion
  case missingFiles
  case missingSurface
  case singleFileWithoutOwnedSurface
  case typeOnly
  case utilityOnly
  case configOnly
}

enum ModuleFileKind: String, Equatable, Hashable, Sendable {
  case config
  case generated
  case source
  case typeOnly
  case utility
}

struct ModuleQualityGateEvaluation: Equatable, Sendable {
  let module: Module
  let decision: ModuleQualityGateDecision
  let reasons: [ModuleQualityGateReason]
  let cohesionScore: Double?
  let fileKinds: [String: ModuleFileKind]

  var isAccepted: Bool {
    decision == .accepted
  }

  var isPendingApproval: Bool {
    decision == .needsApproval
  }
}

struct ModuleQualityGate: Sendable {
  let options: ModuleQualityGateOptions

  init(options: ModuleQualityGateOptions = ModuleQualityGateOptions()) {
    self.options = options
  }

  func evaluate(
    module: Module,
    fingerprints: [CapabilityFingerprint] = [],
    graph: CodeGraph? = nil,
    contentsByPath: [String: String] = [:]
  ) -> ModuleQualityGateEvaluation {
    let moduleFiles = module.files.uniqued()
    let fileKinds = fileKinds(for: moduleFiles, contentsByPath: contentsByPath)
    let cohesionScore = graph.map { cohesion(for: moduleFiles, graph: $0) }
    var reasons: [ModuleQualityGateReason] = []

    if moduleFiles.isEmpty {
      reasons.append(.missingFiles)
    }

    if !hasSurface(module: module, fingerprints: fingerprints) {
      reasons.append(.missingSurface)
    }

    if moduleFiles.count == 1 && !singleFileOwnsSurface(module: module, fingerprints: fingerprints) {
      reasons.append(.singleFileWithoutOwnedSurface)
    }

    if moduleFiles.count > 1,
       let cohesionScore,
       cohesionScore < options.cohesionThreshold {
      reasons.append(.lowCohesion)
    }

    reasons.append(contentsOf: trivialityReasons(fileKinds: fileKinds))

    let rejectionReasons = reasons.uniqued().sorted { $0.rawValue < $1.rawValue }
    if !rejectionReasons.isEmpty {
      return ModuleQualityGateEvaluation(
        module: module,
        decision: .rejected,
        reasons: rejectionReasons,
        cohesionScore: cohesionScore,
        fileKinds: fileKinds
      )
    }

    if module.confidence < options.confidenceThreshold {
      return ModuleQualityGateEvaluation(
        module: module,
        decision: .needsApproval,
        reasons: [.belowConfidenceThreshold],
        cohesionScore: cohesionScore,
        fileKinds: fileKinds
      )
    }

    return ModuleQualityGateEvaluation(
      module: module,
      decision: .accepted,
      reasons: [],
      cohesionScore: cohesionScore,
      fileKinds: fileKinds
    )
  }

  func evaluate(
    modules: [Module],
    fingerprints: [CapabilityFingerprint] = [],
    graph: CodeGraph? = nil,
    contentsByPath: [String: String] = [:]
  ) -> [ModuleQualityGateEvaluation] {
    var evaluations = modules.map {
      evaluate(module: $0, fingerprints: fingerprints, graph: graph, contentsByPath: contentsByPath)
    }

    let duplicateIndexes = duplicateEvaluationIndexes(evaluations)
    for index in duplicateIndexes {
      let evaluation = evaluations[index]
      let reasons = (evaluation.reasons + [.duplicateOverlap]).uniqued().sorted { $0.rawValue < $1.rawValue }
      evaluations[index] = ModuleQualityGateEvaluation(
        module: evaluation.module,
        decision: .rejected,
        reasons: reasons,
        cohesionScore: evaluation.cohesionScore,
        fileKinds: evaluation.fileKinds
      )
    }

    return evaluations
  }

  private func hasSurface(module: Module, fingerprints: [CapabilityFingerprint]) -> Bool {
    if !module.surface.isEmpty || !module.anchors.isEmpty {
      return true
    }

    return fingerprintsForModule(module, fingerprints: fingerprints).contains { fingerprint in
      !fingerprint.routes.isEmpty
        || !fingerprint.publicExports.isEmpty
        || !fingerprint.importedDependencies.isEmpty
        || !fingerprint.envVars.isEmpty
        || !fingerprint.configKeys.isEmpty
        || !fingerprint.capabilityHints.isEmpty
    }
  }

  private func singleFileOwnsSurface(module: Module, fingerprints: [CapabilityFingerprint]) -> Bool {
    guard let file = module.files.first else {
      return false
    }

    if module.surface.contains(where: { $0.path == file }) {
      return true
    }

    return fingerprints.filter { $0.filePath == file }.contains { fingerprint in
      !fingerprint.routes.isEmpty || !fingerprint.publicExports.isEmpty
    }
  }

  private func fingerprintsForModule(
    _ module: Module,
    fingerprints: [CapabilityFingerprint]
  ) -> [CapabilityFingerprint] {
    let files = Set(module.files)
    return fingerprints.filter { files.contains($0.filePath) }
  }

  private func cohesion(for files: [String], graph: CodeGraph) -> Double {
    guard files.count > 1 else {
      return 1
    }

    let fileSet = Set(files)
    var internalEdgeCount = 0
    var externalEdgeCount = 0

    for edge in graph.edges {
      let fromInModule = fileSet.contains(edge.from.filePath)
      let toInModule = fileSet.contains(edge.to.filePath)

      if fromInModule && toInModule {
        if edge.from.filePath != edge.to.filePath {
          internalEdgeCount += 1
        }
      } else if fromInModule || toInModule {
        externalEdgeCount += 1
      }
    }

    let total = internalEdgeCount + externalEdgeCount
    guard total > 0 else {
      return 0
    }

    return Double(internalEdgeCount) / Double(total)
  }

  private func fileKinds(
    for files: [String],
    contentsByPath: [String: String]
  ) -> [String: ModuleFileKind] {
    Dictionary(uniqueKeysWithValues: files.map { path in
      (path, classify(path: path, contents: contentsByPath[path] ?? ""))
    })
  }

  private func classify(path: String, contents: String) -> ModuleFileKind {
    let lowercasedPath = path.lowercased()
    let components = lowercasedPath.split(separator: "/").map(String.init)
    let filename = components.last ?? lowercasedPath
    let normalizedContents = contents.lowercased()

    if components.contains("generated")
      || filename.contains("generated")
      || normalizedContents.contains("@generated")
      || normalizedContents.contains("code generated")
      || normalizedContents.contains("auto-generated")
      || normalizedContents.contains("do not edit") {
      return .generated
    }

    if components.contains("config")
      || filename == "config.ts"
      || filename == "config.js"
      || filename == "settings.py"
      || filename == "env.ts"
      || filename == "env.js" {
      return .config
    }

    if components.contains("utils")
      || components.contains("util")
      || filename.contains("util")
      || filename.contains("helper")
      || filename == "format.ts"
      || filename == "format.js" {
      return .utility
    }

    if isTypeFile(path: lowercasedPath, contents: contents) {
      return .typeOnly
    }

    return .source
  }

  private func isTypeFile(path: String, contents: String) -> Bool {
    let components = path.split(separator: "/").map(String.init)
    let filename = components.last ?? path

    if filename.hasPrefix("types.")
      || filename.hasSuffix(".d.ts")
      || components.contains("types") {
      return true
    }

    let meaningfulLines = contents
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { line in
        !line.isEmpty
          && !line.hasPrefix("//")
          && !line.hasPrefix("/*")
          && !line.hasPrefix("*")
      }

    guard !meaningfulLines.isEmpty else {
      return false
    }

    return meaningfulLines.allSatisfy { line in
      line.hasPrefix("import ")
        || line.hasPrefix("export type ")
        || line.hasPrefix("export interface ")
        || line.hasPrefix("export enum ")
        || line.hasPrefix("type ")
        || line.hasPrefix("interface ")
        || line.hasPrefix("enum ")
        || line == "}"
        || line == "};"
    }
  }

  private func trivialityReasons(fileKinds: [String: ModuleFileKind]) -> [ModuleQualityGateReason] {
    let kinds = Set(fileKinds.values)

    if kinds.isEmpty {
      return []
    }

    if kinds == [.generated] {
      return [.generatedOnly]
    }
    if kinds == [.typeOnly] {
      return [.typeOnly]
    }
    if kinds == [.utility] {
      return [.utilityOnly]
    }
    if kinds == [.config] {
      return [.configOnly]
    }
    if kinds.isSubset(of: [.typeOnly, .utility]) {
      return [.typeOnly, .utilityOnly]
    }
    if kinds.isSubset(of: [.config, .typeOnly]) {
      return [.configOnly, .typeOnly]
    }

    return []
  }

  private func duplicateEvaluationIndexes(_ evaluations: [ModuleQualityGateEvaluation]) -> Set<Int> {
    var duplicateIndexes: Set<Int> = []

    for lhsIndex in evaluations.indices {
      guard evaluations[lhsIndex].decision != .rejected else {
        continue
      }

      for rhsIndex in evaluations.indices where rhsIndex > lhsIndex {
        guard evaluations[rhsIndex].decision != .rejected else {
          continue
        }

        let lhsFiles = Set(evaluations[lhsIndex].module.files)
        let rhsFiles = Set(evaluations[rhsIndex].module.files)
        guard !lhsFiles.isEmpty, !rhsFiles.isEmpty else {
          continue
        }

        let overlap = Double(lhsFiles.intersection(rhsFiles).count) / Double(min(lhsFiles.count, rhsFiles.count))
        guard overlap >= options.duplicateOverlapThreshold else {
          continue
        }

        let loserIndex = duplicateLoserIndex(lhsIndex, rhsIndex, evaluations: evaluations)
        duplicateIndexes.insert(loserIndex)
      }
    }

    return duplicateIndexes
  }

  private func duplicateLoserIndex(
    _ lhsIndex: Int,
    _ rhsIndex: Int,
    evaluations: [ModuleQualityGateEvaluation]
  ) -> Int {
    let lhs = evaluations[lhsIndex].module
    let rhs = evaluations[rhsIndex].module

    if lhs.confidence != rhs.confidence {
      return lhs.confidence < rhs.confidence ? lhsIndex : rhsIndex
    }
    if lhs.files.count != rhs.files.count {
      return lhs.files.count < rhs.files.count ? lhsIndex : rhsIndex
    }

    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending ? rhsIndex : lhsIndex
  }
}

private extension Array where Element: Hashable {
  func uniqued() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
