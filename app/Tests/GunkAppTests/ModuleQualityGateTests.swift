import XCTest
@testable import GunkApp

final class ModuleQualityGateTests: XCTestCase {
  func testRejectsLoneTypesFile() {
    let evaluation = ModuleQualityGate().evaluate(
      module: Module(
        name: "Shared types",
        purpose: "Type definitions.",
        tags: ["api"],
        files: ["src/types.ts"],
        language: "TypeScript",
        confidence: 0.9,
        anchors: ["types"]
      ),
      contentsByPath: [
        "src/types.ts": """
        export interface User {
          id: string;
        }
        export type Role = "admin" | "user";
        """
      ]
    )

    XCTAssertEqual(evaluation.decision, .rejected)
    XCTAssertTrue(evaluation.reasons.contains(.typeOnly))
    XCTAssertEqual(evaluation.fileKinds["src/types.ts"], .typeOnly)
  }

  func testRejectsUtilOnlyAndConfigOnly() {
    let gate = ModuleQualityGate()
    let utilEvaluation = gate.evaluate(
      module: Module(
        name: "Format utilities",
        purpose: "Formats strings.",
        tags: ["api"],
        files: ["src/utils/format.ts"],
        language: "TypeScript",
        confidence: 0.95,
        anchors: ["format"]
      ),
      contentsByPath: [
        "src/utils/format.ts": "export function formatCurrency(value: number) { return String(value); }"
      ]
    )
    let configEvaluation = gate.evaluate(
      module: Module(
        name: "Auth config",
        purpose: "Stores auth config.",
        tags: ["auth"],
        files: ["src/config/auth.ts"],
        language: "TypeScript",
        confidence: 0.95,
        anchors: ["auth"]
      ),
      contentsByPath: [
        "src/config/auth.ts": "export const googleClientId = process.env.GOOGLE_CLIENT_ID;"
      ]
    )

    XCTAssertEqual(utilEvaluation.decision, .rejected)
    XCTAssertTrue(utilEvaluation.reasons.contains(.utilityOnly))
    XCTAssertEqual(configEvaluation.decision, .rejected)
    XCTAssertTrue(configEvaluation.reasons.contains(.configOnly))
  }

  func testAcceptsRealMultiFileCapability() {
    let module = googleOAuthModule(confidence: 0.91)
    let evaluation = ModuleQualityGate().evaluate(
      module: module,
      fingerprints: [
        CapabilityFingerprint(
          filePath: "src/routes/auth.ts",
          importedDependencies: [],
          routes: [
            RouteSurface(
              framework: .express,
              method: "GET",
              path: "/auth/google",
              handler: "googleLogin",
              line: 1
            )
          ],
          publicExports: [ExportRef(name: "authRouter", kind: .variable, line: 1)],
          envVars: [],
          configKeys: [],
          namingTokens: ["auth"],
          capabilityHints: []
        )
      ],
      graph: googleOAuthGraph(),
      contentsByPath: googleOAuthContents()
    )

    XCTAssertEqual(evaluation.decision, .accepted)
    XCTAssertEqual(evaluation.reasons, [])
    XCTAssertEqual(evaluation.cohesionScore, 1)
  }

  func testBelowConfidenceGoesToApprovalQueue() {
    let evaluation = ModuleQualityGate(
      options: ModuleQualityGateOptions(confidenceThreshold: 0.7)
    ).evaluate(
      module: googleOAuthModule(confidence: 0.52),
      graph: googleOAuthGraph(),
      contentsByPath: googleOAuthContents()
    )

    XCTAssertEqual(evaluation.decision, .needsApproval)
    XCTAssertTrue(evaluation.isPendingApproval)
    XCTAssertEqual(evaluation.reasons, [.belowConfidenceThreshold])
  }

  private func googleOAuthModule(confidence: Double) -> Module {
    Module(
      name: "Google OAuth login",
      purpose: "Authenticates users with Google OAuth and creates a session.",
      tags: ["auth", "api"],
      files: [
        "src/routes/auth.ts",
        "src/services/googleOAuth.ts",
        "src/config/auth.ts",
        "src/types/auth.ts"
      ],
      language: "TypeScript",
      confidence: confidence,
      ownedFiles: [
        "src/routes/auth.ts",
        "src/services/googleOAuth.ts"
      ],
      sharedDeps: [
        "src/config/auth.ts",
        "src/types/auth.ts"
      ],
      surface: [
        ModuleSurface(path: "src/routes/auth.ts", symbol: "googleLogin")
      ],
      anchors: ["route:GET /auth/google", "passport-google-oauth20"]
    )
  }

  private func googleOAuthGraph() -> CodeGraph {
    graph(
      paths: [
        "src/routes/auth.ts",
        "src/services/googleOAuth.ts",
        "src/config/auth.ts",
        "src/types/auth.ts"
      ],
      edges: [
        edge("src/routes/auth.ts", "src/services/googleOAuth.ts", .import),
        edge("src/services/googleOAuth.ts", "src/config/auth.ts", .import),
        edge("src/services/googleOAuth.ts", "src/types/auth.ts", .reference)
      ]
    )
  }

  private func googleOAuthContents() -> [String: String] {
    [
      "src/routes/auth.ts": """
      router.get("/auth/google", googleLogin);
      export const authRouter = router;
      """,
      "src/services/googleOAuth.ts": """
      import { authConfig } from "../config/auth";
      export async function googleLogin() {}
      """,
      "src/config/auth.ts": "export const authConfig = { clientId: process.env.GOOGLE_CLIENT_ID };",
      "src/types/auth.ts": "export interface AuthUser { id: string; }"
    ]
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
}
