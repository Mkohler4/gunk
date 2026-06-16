import XCTest

@testable import GunkApp

final class RequirementsDeriverTests: XCTestCase {
  private let deriver = RequirementsDeriver()

  func testReadsRequiresPythonFromPyproject() {
    let runtime = deriver.deriveRuntime(
      language: "Python",
      manifests: ["pyproject.toml": "requires-python = \">=3.11\"\n"]
    )
    XCTAssertEqual(runtime, "Python ≥ 3.11")
  }

  func testReadsEnginesNodeAndMapsTypeScriptToNode() {
    let runtime = deriver.deriveRuntime(
      language: "typeScript",
      manifests: ["package.json": "{\"engines\": {\"node\": \">=18\"}}"]
    )
    XCTAssertEqual(runtime, "Node ≥ 18")
  }

  func testReadsGoDirective() {
    let runtime = deriver.deriveRuntime(
      language: "Go",
      manifests: ["go.mod": "module x\n\ngo 1.21\n"]
    )
    XCTAssertEqual(runtime, "Go ≥ 1.21")
  }

  func testFallsBackToBareLanguageWhenNoConstraint() {
    let runtime = deriver.deriveRuntime(
      language: "Python",
      manifests: ["requirements.txt": "ebooklib\n"]
    )
    XCTAssertEqual(runtime, "Python")
  }

  func testPrefersManifestMatchingLanguage() {
    let runtime = deriver.deriveRuntime(
      language: "Python",
      manifests: [
        "package.json": "{\"engines\": {\"node\": \">=20\"}}",
        "pyproject.toml": "requires-python = \">=3.12\"\n"
      ]
    )
    XCTAssertEqual(runtime, "Python ≥ 3.12")
  }

  func testNilWhenLanguageUnknownAndNoManifests() {
    XCTAssertNil(deriver.deriveRuntime(language: nil, manifests: [:]))
  }
}
