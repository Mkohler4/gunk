import XCTest
@testable import GunkApp

final class CapabilityExpanderTests: XCTestCase {
  func testClosureIncludesCollaborators() {
    let graph = graph(
      paths: [
        "src/auth/route.ts",
        "src/auth/service.ts",
        "src/auth/googleClient.ts",
        "src/types/auth.ts"
      ],
      edges: [
        edge("src/auth/route.ts", "src/auth/service.ts", .import),
        edge("src/auth/service.ts", "src/auth/googleClient.ts", .call),
        edge("src/auth/service.ts", "src/types/auth.ts", .reference)
      ]
    )

    let expansions = CapabilityExpander(
      options: CapabilityExpansionOptions(maxDepth: 2, maxFilesPerCapability: 10)
    ).expand(
      hypotheses: [
        hypothesis(name: "Google OAuth login", seedFiles: ["src/auth/route.ts"])
      ],
      graph: graph
    )

    XCTAssertEqual(expansions.count, 1)
    XCTAssertEqual(
      expansions[0].closureFiles,
      [
        "src/auth/googleClient.ts",
        "src/auth/route.ts",
        "src/auth/service.ts",
        "src/types/auth.ts"
      ]
    )
    XCTAssertEqual(expansions[0].ownedFiles, expansions[0].closureFiles)
    XCTAssertEqual(expansions[0].sharedDependencyFiles, [])
    XCTAssertTrue(
      expansions[0].edgeEvidence.contains(
        CapabilityExpansionEdgeEvidence(
          fromPath: "src/auth/service.ts",
          toPath: "src/auth/googleClient.ts",
          kind: .call,
          depth: 2
        )
      )
    )
  }

  func testSharedUtilNotOwnedByMultipleModules() throws {
    let graph = graph(
      paths: [
        "src/auth/route.ts",
        "src/auth/service.ts",
        "src/billing/route.ts",
        "src/billing/service.ts",
        "src/lib/db.ts"
      ],
      edges: [
        edge("src/auth/route.ts", "src/auth/service.ts", .import),
        edge("src/auth/service.ts", "src/lib/db.ts", .import),
        edge("src/billing/route.ts", "src/billing/service.ts", .import),
        edge("src/billing/service.ts", "src/lib/db.ts", .import)
      ]
    )

    let expansions = CapabilityExpander(
      options: CapabilityExpansionOptions(maxDepth: 2, maxFilesPerCapability: 10)
    ).expand(
      hypotheses: [
        hypothesis(name: "Google OAuth login", seedFiles: ["src/auth/route.ts"]),
        hypothesis(name: "Stripe billing", seedFiles: ["src/billing/route.ts"])
      ],
      graph: graph
    )

    let auth = try XCTUnwrap(expansions.first { $0.hypothesis.name == "Google OAuth login" })
    let billing = try XCTUnwrap(expansions.first { $0.hypothesis.name == "Stripe billing" })

    XCTAssertEqual(auth.sharedDependencyFiles, ["src/lib/db.ts"])
    XCTAssertEqual(billing.sharedDependencyFiles, ["src/lib/db.ts"])
    XCTAssertFalse(auth.ownedFiles.contains("src/lib/db.ts"))
    XCTAssertFalse(billing.ownedFiles.contains("src/lib/db.ts"))
    XCTAssertEqual(auth.ownedFiles, ["src/auth/route.ts", "src/auth/service.ts"])
    XCTAssertEqual(billing.ownedFiles, ["src/billing/route.ts", "src/billing/service.ts"])
  }

  func testRespectsClosureBound() throws {
    let graph = graph(
      paths: [
        "src/upload/route.ts",
        "src/upload/service.ts",
        "src/upload/storage.ts",
        "src/upload/image.ts"
      ],
      edges: [
        edge("src/upload/route.ts", "src/upload/service.ts", .import),
        edge("src/upload/service.ts", "src/upload/storage.ts", .import),
        edge("src/upload/storage.ts", "src/upload/image.ts", .import)
      ]
    )

    let expansions = CapabilityExpander(
      options: CapabilityExpansionOptions(maxDepth: 10, maxFilesPerCapability: 2)
    ).expand(
      hypotheses: [
        hypothesis(name: "S3 upload", seedFiles: ["src/upload/route.ts"])
      ],
      graph: graph
    )

    let expansion = try XCTUnwrap(expansions.first { $0.hypothesis.name == "S3 upload" })
    XCTAssertEqual(expansion.closureFiles, ["src/upload/route.ts", "src/upload/service.ts"])
    XCTAssertEqual(
      expansion.excludedFiles,
      [
        CapabilityExpansionExcludedFile(
          path: "src/upload/storage.ts",
          reason: "closure file limit reached"
        )
      ]
    )
    XCTAssertFalse(expansion.closureFiles.contains("src/upload/storage.ts"))
    XCTAssertFalse(expansion.closureFiles.contains("src/upload/image.ts"))
  }

  private func graph(paths: [String], edges: [CodeGraphEdge]) -> CodeGraph {
    CodeGraph(
      nodes: Set(paths.map(CodeGraphNode.file)),
      edges: Set(edges),
      externalDependencies: [:]
    )
  }

  private func edge(
    _ from: String,
    _ to: String,
    _ kind: CodeGraphEdgeKind
  ) -> CodeGraphEdge {
    CodeGraphEdge(from: CodeGraphNode.file(from), to: CodeGraphNode.file(to), kind: kind)
  }

  private func hypothesis(name: String, seedFiles: [String]) -> CapabilityHypothesis {
    CapabilityHypothesis(
      name: name,
      rationale: "\(name) rationale",
      anchors: ["route"],
      seedFiles: seedFiles,
      expectedCollaborators: [],
      granularity: "feature",
      priority: .normal
    )
  }

}
