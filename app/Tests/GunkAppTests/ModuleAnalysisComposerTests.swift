import XCTest
@testable import GunkApp

final class ModuleAnalysisComposerTests: XCTestCase {
  // MARK: Prompt

  func testUserPromptIncludesModuleSignals() {
    let input = ModuleAnalysisInput(
      name: "epub-to-markdown",
      purpose: "Convert an EPUB into Markdown",
      language: "Python",
      entrypoints: [BrowseEntrypoint(path: "src/convert.py", symbol: "convert")],
      requirements: ModuleRequirements(runtime: "Python ≥ 3.11", packages: ["ebooklib"], env: ["OUT_DIR"]),
      ownedFiles: ["src/convert.py", "src/spine.py"],
      callItSnippets: []
    )

    let prompt = ModuleAnalysisComposer.userPrompt(for: input)

    XCTAssertTrue(prompt.contains("Module: epub-to-markdown"))
    XCTAssertTrue(prompt.contains("Language: Python"))
    XCTAssertTrue(prompt.contains("Convert an EPUB into Markdown"))
    XCTAssertTrue(prompt.contains("src/convert.py · convert"))
    XCTAssertTrue(prompt.contains("Python ≥ 3.11"))
    XCTAssertTrue(prompt.contains("ebooklib"))
    XCTAssertTrue(prompt.contains("OUT_DIR"))
    XCTAssertTrue(prompt.contains("src/spine.py"))
  }

  func testUserPromptOmitsAbsentSignals() {
    let input = ModuleAnalysisInput(
      name: "bare",
      purpose: nil,
      language: nil,
      entrypoints: [],
      requirements: nil,
      ownedFiles: [],
      callItSnippets: []
    )

    let prompt = ModuleAnalysisComposer.userPrompt(for: input)

    XCTAssertEqual(prompt, "Module: bare")
    XCTAssertFalse(prompt.contains("Language:"))
    XCTAssertFalse(prompt.contains("Purpose:"))
  }

  func testRequestUsesSchemaAndModel() {
    let input = ModuleAnalysisInput(
      name: "m", purpose: nil, language: nil,
      entrypoints: [], requirements: nil, ownedFiles: [], callItSnippets: []
    )

    let request = ModuleAnalysisComposer.request(for: input, model: "gpt-4.1-mini")

    XCTAssertEqual(request.model, "gpt-4.1-mini")
    XCTAssertEqual(request.jsonSchemaName, "module_analysis")
    XCTAssertEqual(request.messages.first?.role, .system)
    XCTAssertEqual(request.messages.last?.role, .user)
    XCTAssertNotNil(request.jsonSchema.objectValue?["properties"])
  }

  // MARK: Parsing

  func testParseValidPayload() {
    let json = JSONValue.object([
      "summary": .string("Does a thing."),
      "dataFlow": .array([.string("In."), .string("Out.")]),
      "keyFunctions": .array([
        .object(["name": .string("run()"), "role": .string("Entry.")]),
      ]),
      "touches": .array([.string("No network.")]),
      "limits": .array([.string("ASCII only.")]),
    ])

    let content = ModuleAnalysisComposer.parse(json)

    XCTAssertEqual(content?.summary, "Does a thing.")
    XCTAssertEqual(content?.dataFlow, ["In.", "Out."])
    XCTAssertEqual(content?.keyFunctions, [AnalysisFunction(name: "run()", role: "Entry.")])
    XCTAssertEqual(content?.touches, ["No network."])
    XCTAssertEqual(content?.limits, ["ASCII only."])
  }

  func testParseTrimsAndDropsEmptyStringsAndNamelessFunctions() {
    let json = JSONValue.object([
      "summary": .string("  trimmed  "),
      "dataFlow": .array([.string("  keep  "), .string("   "), .string("")]),
      "keyFunctions": .array([
        .object(["name": .string("  "), "role": .string("nameless")]),
        .object(["name": .string("ok()"), "role": .string("  has role  ")]),
      ]),
      "touches": .array([]),
      "limits": .array([]),
    ])

    let content = ModuleAnalysisComposer.parse(json)

    XCTAssertEqual(content?.summary, "trimmed")
    XCTAssertEqual(content?.dataFlow, ["keep"])
    XCTAssertEqual(content?.keyFunctions, [AnalysisFunction(name: "ok()", role: "has role")])
  }

  func testParseReturnsNilForNonObject() {
    XCTAssertNil(ModuleAnalysisComposer.parse(.string("nope")))
    XCTAssertNil(ModuleAnalysisComposer.parse(.null))
  }

  func testParseReturnsNilForEmptyAnalysis() {
    let json = JSONValue.object([
      "summary": .string("   "),
      "dataFlow": .array([]),
      "keyFunctions": .array([]),
      "touches": .array([]),
      "limits": .array([]),
    ])

    XCTAssertNil(ModuleAnalysisComposer.parse(json))
  }
}
