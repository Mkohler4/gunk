import XCTest
@testable import GunkApp

final class CapabilityFingerprintTests: XCTestCase {
  func testParsesSupportedDependencyManifests() throws {
    let parser = DependencyManifestParser()
    let manifests = parser.parse(manifests: [
      "package.json": #"{"dependencies":{"stripe":"latest"}}"#,
      "Package.swift": #".package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0")"#,
      "pyproject.toml": #"[project]\ndependencies = ["fastapi>=0.100", "uvicorn"]"#,
      "requirements.txt": "Flask==3.0\n# ignored\nrequests>=2",
      "go.mod": "require github.com/gin-gonic/gin v1.10.0",
      "Cargo.toml": """
      [dependencies]
      serde = "1"
      """
    ])

    XCTAssertEqual(Set(manifests.flatMap(\.dependencies)), [
      "stripe",
      "swift-argument-parser",
      "fastapi",
      "uvicorn",
      "Flask",
      "requests",
      "github.com/gin-gonic/gin",
      "serde"
    ])
  }

  func testMapsThirdPartyDepToImportingFiles() throws {
    let manifests = DependencyManifestParser().parse(manifests: [
      "package.json": """
      {
        "dependencies": {
          "passport-google-oauth20": "latest",
          "stripe": "latest"
        }
      }
      """
    ])
    let files = [
      fileSymbols(
        path: "src/auth/google.ts",
        imports: [
          ImportRef(moduleSpecifier: "passport-google-oauth20", resolvedTarget: nil, line: 1),
          ImportRef(moduleSpecifier: "./types", resolvedTarget: "src/auth/types.ts", line: 2)
        ]
      ),
      fileSymbols(
        path: "src/billing/checkout.ts",
        imports: [ImportRef(moduleSpecifier: "stripe", resolvedTarget: nil, line: 1)]
      ),
      fileSymbols(path: "src/auth/types.ts")
    ]

    let fingerprints = CapabilityFingerprintBuilder().fingerprints(files: files, manifests: manifests, contentsByPath: [:])

    XCTAssertEqual(fingerprint("src/auth/google.ts", in: fingerprints)?.importedDependencies, ["passport-google-oauth20"])
    XCTAssertEqual(fingerprint("src/billing/checkout.ts", in: fingerprints)?.importedDependencies, ["stripe"])
    XCTAssertEqual(fingerprint("src/auth/types.ts", in: fingerprints)?.importedDependencies, [])
  }

  func testDetectsExpressRoutesAsSurface() throws {
    let file = fileSymbols(
      path: "src/auth/routes.ts",
      exports: [ExportRef(name: "authRouter", kind: .variable, line: 1)]
    )
    let fingerprints = CapabilityFingerprintBuilder().fingerprints(
      files: [file],
      manifests: [],
      contentsByPath: [
        "src/auth/routes.ts": """
        router.get("/auth/google", googleLogin);
        app.post("/auth/google/callback", googleCallback);
        """
      ]
    )

    let fingerprint = try XCTUnwrap(fingerprint("src/auth/routes.ts", in: fingerprints))
    XCTAssertEqual(fingerprint.routes, [
      RouteSurface(framework: .express, method: "GET", path: "/auth/google", handler: "googleLogin", line: 1),
      RouteSurface(framework: .express, method: "POST", path: "/auth/google/callback", handler: "googleCallback", line: 2)
    ])
    XCTAssertEqual(fingerprint.publicExports, [ExportRef(name: "authRouter", kind: .variable, line: 1)])
  }

  func testLexiconHintsForKnownLibraries() throws {
    let manifests = DependencyManifestParser().parse(manifests: [
      "package.json": """
      {
        "dependencies": {
          "passport-google-oauth20": "latest"
        }
      }
      """
    ])
    let files = [
      fileSymbols(
        path: "src/auth/google.ts",
        symbols: [Symbol(name: "googleOAuthCallback", kind: .function, line: 4)],
        imports: [ImportRef(moduleSpecifier: "passport-google-oauth20", resolvedTarget: nil, line: 1)],
        exports: [ExportRef(name: "googleOAuthCallback", kind: .function, line: 4)]
      )
    ]

    let fingerprints = CapabilityFingerprintBuilder().fingerprints(
      files: files,
      manifests: manifests,
      contentsByPath: [
        "src/auth/google.ts": """
        const clientId = process.env.GOOGLE_CLIENT_ID;
        const callbackUrl = config.get("auth.google.callbackUrl");
        export function googleOAuthCallback() {}
        """
      ]
    )
    let fingerprint = try XCTUnwrap(fingerprint("src/auth/google.ts", in: fingerprints))
    let aggregate = CapabilityFingerprintBuilder().aggregate(fingerprints, filePaths: ["src/auth/google.ts"])

    XCTAssertEqual(fingerprint.capabilityHints, [
      CapabilityHint(library: "passport-google-oauth20", labels: ["auth", "google", "oauth"])
    ])
    XCTAssertEqual(fingerprint.envVars, ["GOOGLE_CLIENT_ID"])
    XCTAssertEqual(fingerprint.configKeys, ["auth.google.callbackUrl"])
    XCTAssertTrue(fingerprint.namingTokens.contains("google"))
    XCTAssertTrue(aggregate.hasPublicSurface)
    XCTAssertEqual(aggregate.capabilityHints, fingerprint.capabilityHints)
  }

  private func fingerprint(_ path: String, in fingerprints: [CapabilityFingerprint]) -> CapabilityFingerprint? {
    fingerprints.first { $0.filePath == path }
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
