import XCTest
@testable import GunkApp

final class ContextBuilderTests: XCTestCase {
  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: temporaryDirectory)
  }

  func testRepoMapIncludesClustersAndFingerprints() throws {
    let files = [
      try scannedFile("package.json", #"{"dependencies":{"passport-google-oauth20":"latest"}}"#),
      try scannedFile(
        "src/auth/routes.ts",
        """
        import passport from "passport-google-oauth20";
        import { createSession } from "./service";

        export function googleCallback() {
          return createSession(process.env.GOOGLE_CLIENT_ID);
        }

        router.get("/auth/google", googleCallback);
        """
      ),
      try scannedFile(
        "src/auth/service.ts",
        """
        export function createSession(clientId: string) {
          return clientId;
        }
        """
      )
    ]

    let context = try ContextBuilder().build(files: files, budgetTokens: 1_200)

    XCTAssertTrue(context.contains("repo_map_v1"))
    XCTAssertTrue(context.contains("tree:"))
    XCTAssertTrue(context.contains("clusters:"))
    XCTAssertTrue(context.contains("files:"))
    XCTAssertTrue(context.contains("cluster: c"))
    XCTAssertTrue(context.contains("passport-google-oauth20[auth/google/oauth]"))
    XCTAssertTrue(context.contains("express:GET /auth/google"))
    XCTAssertTrue(context.contains("env: GOOGLE_CLIENT_ID"))
    XCTAssertTrue(context.contains("imports: ./service->src/auth/service.ts"))
    XCTAssertFalse(context.contains("--- README.md ---"))
  }

  func testRepoMapRespectsTokenBudget() throws {
    let files = [
      try scannedFile(
        "src/auth/routes.ts",
        """
        import { createSession } from "./service";
        router.get("/auth/google", googleCallback);
        export function googleCallback() { return createSession(); }
        """
      ),
      try scannedFile("src/auth/service.ts", "export function createSession() { return true; }"),
      try scannedFile(
        "src/billing/routes.ts",
        """
        import { createCheckout } from "./service";
        router.post("/billing/checkout", checkout);
        export function checkout() { return createCheckout(); }
        """
      ),
      try scannedFile("src/billing/service.ts", "export function createCheckout() { return true; }")
    ]

    let context = try ContextBuilder().build(files: files, budgetTokens: 105)

    XCTAssertLessThanOrEqual(ContextBuilder.estimatedTokens(for: context), 105)
    XCTAssertTrue(context.contains(ContextBuilder.truncationMarker))
    XCTAssertFalse(context.contains("src/billing/routes.ts") && !context.contains("src/billing/service.ts"))
  }

  func testRepoMapIsDeterministic() throws {
    let package = try scannedFile("package.json", #"{"dependencies":{"stripe":"latest"}}"#)
    let billing = try scannedFile(
      "src/billing/routes.ts",
      """
      import Stripe from "stripe";
      router.post("/checkout", checkout);
      export function checkout() { return new Stripe(process.env.STRIPE_KEY); }
      """
    )
    let auth = try scannedFile(
      "src/auth/routes.ts",
      """
      router.get("/auth/google", googleCallback);
      export function googleCallback() { return true; }
      """
    )

    let first = try ContextBuilder().build(files: [billing, auth, package], budgetTokens: 1_200)
    let second = try ContextBuilder().build(files: [package, auth, billing], budgetTokens: 1_200)

    XCTAssertEqual(first, second)
  }

  private func scannedFile(_ relpath: String, _ contents: String) throws -> ScannedFile {
    let url = temporaryDirectory.appendingPathComponent(relpath)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(contents.utf8).write(to: url)

    return ScannedFile(
      url: url,
      relpath: relpath,
      size: Int64(Data(contents.utf8).count)
    )
  }
}
