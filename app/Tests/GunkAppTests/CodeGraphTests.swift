import XCTest
@testable import GunkApp

final class CodeGraphTests: XCTestCase {
  func testResolvesRelativeAndAliasImports() {
    let resolver = ImportResolver(
      config: .init(
        sourceFiles: [
          "src/auth/login.ts",
          "src/auth/types.ts",
          "src/config/env.ts",
          "src/shared/oauth.ts"
        ],
        tsconfigPaths: ["@/*": ["src/*"]]
      )
    )

    XCTAssertEqual(resolver.resolve("./types", from: "src/auth/login.ts"), "src/auth/types.ts")
    XCTAssertEqual(resolver.resolve("@/shared/oauth", from: "src/auth/login.ts"), "src/shared/oauth.ts")
    XCTAssertEqual(resolver.resolve("src/config/env", from: "src/auth/login.ts"), "src/config/env.ts")
    XCTAssertNil(resolver.resolve("react", from: "src/auth/login.ts"))
  }

  func testConnectedComponentsSeparateFeatures() {
    let files = [
      fileSymbols(path: "src/auth/route.ts", imports: [ImportRef(moduleSpecifier: "./service", resolvedTarget: nil, line: 1)]),
      fileSymbols(path: "src/auth/service.ts"),
      fileSymbols(path: "src/billing/route.ts", imports: [ImportRef(moduleSpecifier: "./service", resolvedTarget: nil, line: 1)]),
      fileSymbols(path: "src/billing/service.ts")
    ]
    let graph = graph(files: files)
    let clusters = GraphClustering(graph: graph).connectedComponents()

    XCTAssertEqual(Set(clusters.map(\.filePaths)), [
      ["src/auth/route.ts", "src/auth/service.ts"],
      ["src/billing/route.ts", "src/billing/service.ts"]
    ])
    XCTAssertEqual(clusters.map(\.cohesionScore), [1, 1])
  }

  func testSharedUtilIsHighFanInBridge() {
    let files = [
      fileSymbols(path: "src/auth/service.ts", imports: [ImportRef(moduleSpecifier: "../shared/oauth", resolvedTarget: nil, line: 1)]),
      fileSymbols(path: "src/billing/service.ts", imports: [ImportRef(moduleSpecifier: "../shared/oauth", resolvedTarget: nil, line: 1)]),
      fileSymbols(path: "src/shared/oauth.ts")
    ]
    let graph = graph(files: files)
    let bridgeFiles = GraphClustering(graph: graph).highFanInBridgeFiles(minInbound: 2)

    XCTAssertEqual(bridgeFiles, [CodeGraphNode.file("src/shared/oauth.ts")])
    XCTAssertEqual(graph.inboundEdges(to: CodeGraphNode.file("src/shared/oauth.ts"), kinds: [.import]).count, 2)
  }

  func testClosureAndSymbolEdges() {
    let files = [
      fileSymbols(
        path: "src/auth/controller.ts",
        imports: [ImportRef(moduleSpecifier: "./service", resolvedTarget: nil, line: 1)]
      ),
      fileSymbols(
        path: "src/auth/service.ts",
        symbols: [Symbol(name: "createSession", kind: .function, line: 1)],
        exports: [ExportRef(name: "createSession", kind: .function, line: 1)]
      ),
      fileSymbols(
        path: "src/auth/base.ts",
        symbols: [Symbol(name: "BaseHandler", kind: .class, line: 1)],
        exports: [ExportRef(name: "BaseHandler", kind: .class, line: 1)]
      )
    ]
    let graph = graph(
      files: files,
      contentsByPath: [
        "src/auth/controller.ts": """
        import { createSession } from "./service";
        class LoginHandler extends BaseHandler {
          run() { createSession(); }
        }
        """
      ]
    )

    let controller = CodeGraphNode.file("src/auth/controller.ts")
    XCTAssertTrue(graph.edges.contains(CodeGraphEdge(from: controller, to: CodeGraphNode.file("src/auth/service.ts"), kind: .import)))
    XCTAssertTrue(graph.edges.contains(CodeGraphEdge(from: controller, to: CodeGraphNode.symbol(Symbol(name: "createSession", kind: .function, line: 1), in: "src/auth/service.ts"), kind: .call)))
    XCTAssertTrue(graph.edges.contains(CodeGraphEdge(from: controller, to: CodeGraphNode.symbol(Symbol(name: "BaseHandler", kind: .class, line: 1), in: "src/auth/base.ts"), kind: .inherit)))
    XCTAssertEqual(graph.transitiveClosure(from: controller, maxDepth: 1, kinds: [.import]), [CodeGraphNode.file("src/auth/service.ts")])
  }

  private func graph(files: [FileSymbols], contentsByPath: [String: String] = [:]) -> CodeGraph {
    let resolver = ImportResolver(config: .init(sourceFiles: Set(files.map(\.path))))
    return CodeGraphBuilder(resolver: resolver).build(files: files, contentsByPath: contentsByPath)
  }

  private func fileSymbols(
    path: String,
    symbols: [Symbol] = [],
    imports: [ImportRef] = [],
    exports: [ExportRef] = []
  ) -> FileSymbols {
    FileSymbols(path: path, language: LanguageKind(path: path), symbols: symbols, imports: imports, exports: exports)
  }
}
