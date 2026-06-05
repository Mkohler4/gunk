import Foundation

struct ExpectedDecomposition: Decodable, Equatable {
  let modules: [ExpectedModule]
  let mustNotBeModules: [String]

  static func load(from url: URL) throws -> ExpectedDecomposition {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(ExpectedDecomposition.self, from: Data(contentsOf: url))
  }
}

struct ExpectedModule: Decodable, Equatable {
  let name: String
  let tags: [String]
  let files: [String]
}

enum DecompositionEval {
  static func score(actual: [Module], expected: ExpectedDecomposition) -> Scorecard {
    var unusedActual = Array(actual.enumerated())
    var moduleScores: [ModuleScore] = []

    for expectedModule in expected.modules {
      let match = bestMatch(for: expectedModule, in: unusedActual)

      if let match {
        unusedActual.removeAll { $0.offset == match.offset }
        moduleScores.append(score(expected: expectedModule, actual: match.element))
      } else {
        moduleScores.append(
          ModuleScore(
            expectedName: expectedModule.name,
            actualName: nil,
            filePrecision: 0,
            fileRecall: 0,
            tagAccuracy: 0,
            matchedFiles: [],
            missingFiles: expectedModule.files.sorted(),
            extraFiles: []
          )
        )
      }
    }

    let falsePositiveModules = actual.filter {
      isTrivialModule($0, mustNotBeModules: expected.mustNotBeModules)
    }

    return Scorecard(
      moduleScores: moduleScores,
      expectedModuleCount: expected.modules.count,
      actualModuleCount: actual.count,
      moduleCountDelta: actual.count - expected.modules.count,
      trivialModuleFalsePositiveCount: falsePositiveModules.count,
      trivialModuleFalsePositiveRate: falsePositiveRate(
        falsePositiveCount: falsePositiveModules.count,
        trapCount: expected.mustNotBeModules.count
      )
    )
  }

  private static func bestMatch(
    for expected: ExpectedModule,
    in actual: [(offset: Int, element: Module)]
  ) -> (offset: Int, element: Module)? {
    actual
      .map { candidate in
        (
          candidate: candidate,
          overlap: Set(expected.files).intersection(candidate.element.files).count,
          nameMatches: candidate.element.name == expected.name
        )
      }
      .filter { $0.overlap > 0 || $0.nameMatches }
      .max { lhs, rhs in
        if lhs.overlap == rhs.overlap {
          return !lhs.nameMatches && rhs.nameMatches
        }

        return lhs.overlap < rhs.overlap
      }?
      .candidate
  }

  private static func score(expected: ExpectedModule, actual: Module) -> ModuleScore {
    let expectedFiles = Set(expected.files)
    let actualFiles = Set(actual.files)
    let matchedFiles = expectedFiles.intersection(actualFiles)
    let missingFiles = expectedFiles.subtracting(actualFiles)
    let extraFiles = actualFiles.subtracting(expectedFiles)
    let expectedTags = Set(expected.tags)
    let actualTags = Set(actual.tags)

    return ModuleScore(
      expectedName: expected.name,
      actualName: actual.name,
      filePrecision: ratio(matchedFiles.count, actualFiles.count),
      fileRecall: ratio(matchedFiles.count, expectedFiles.count),
      tagAccuracy: ratio(expectedTags.intersection(actualTags).count, expectedTags.count),
      matchedFiles: matchedFiles.sorted(),
      missingFiles: missingFiles.sorted(),
      extraFiles: extraFiles.sorted()
    )
  }

  private static func isTrivialModule(_ module: Module, mustNotBeModules: [String]) -> Bool {
    guard !module.files.isEmpty else {
      return false
    }

    return module.files.allSatisfy { file in
      mustNotBeModules.contains { trap in
        matchesTrap(file: file, trap: trap)
      }
    }
  }

  private static func matchesTrap(file: String, trap: String) -> Bool {
    if trap.hasSuffix("/") {
      return file.hasPrefix(trap)
    }

    return file == trap
  }

  private static func falsePositiveRate(falsePositiveCount: Int, trapCount: Int) -> Double {
    guard trapCount > 0 else {
      return 0
    }

    return ratio(falsePositiveCount, trapCount)
  }

  private static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
    guard denominator > 0 else {
      return 0
    }

    return Double(numerator) / Double(denominator)
  }
}

struct Scorecard: Equatable {
  let moduleScores: [ModuleScore]
  let expectedModuleCount: Int
  let actualModuleCount: Int
  let moduleCountDelta: Int
  let trivialModuleFalsePositiveCount: Int
  let trivialModuleFalsePositiveRate: Double

  var filePrecision: Double {
    average(moduleScores.map(\.filePrecision))
  }

  var fileRecall: Double {
    average(moduleScores.map(\.fileRecall))
  }

  var tagAccuracy: Double {
    average(moduleScores.map(\.tagAccuracy))
  }

  var summary: String {
    """
    file_precision: \(filePrecision.percentString)
    file_recall: \(fileRecall.percentString)
    tag_accuracy: \(tagAccuracy.percentString)
    expected_modules: \(expectedModuleCount)
    actual_modules: \(actualModuleCount)
    module_count_delta: \(moduleCountDelta)
    trivial_module_false_positives: \(trivialModuleFalsePositiveCount)
    trivial_module_false_positive_rate: \(trivialModuleFalsePositiveRate.percentString)
    """
  }

  private func average(_ values: [Double]) -> Double {
    guard !values.isEmpty else {
      return 0
    }

    return values.reduce(0, +) / Double(values.count)
  }
}

struct ModuleScore: Equatable {
  let expectedName: String
  let actualName: String?
  let filePrecision: Double
  let fileRecall: Double
  let tagAccuracy: Double
  let matchedFiles: [String]
  let missingFiles: [String]
  let extraFiles: [String]
}

private extension Double {
  var percentString: String {
    String(format: "%.2f", self)
  }
}
