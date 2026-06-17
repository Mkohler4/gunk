import Foundation

/// The "How this works" analysis (T-10.14): the **long form** of the T-10.8
/// input signature. Where the input signature answers "what do I feed it",
/// this answers "how is it built" — data flow in → transform → out, the key
/// functions, what it touches, and its honest limits.
///
/// Pure and derivation-free at the value level: the text is generated once by a
/// model (`ModuleAnalysisComposer` builds the prompt + schema) and then cached
/// in the store (schema v7). Opening the disclosure reads the cache, so it is
/// instant and never blocks on a live model call at view time.

/// The generated content alone — the part a model writes and we serialize into
/// the store's `content` column. Kept separate from the metadata
/// (`model`/`generatedAt`) so the composer's output type carries no clock or
/// provider concerns.
struct ModuleAnalysisContent: Equatable, Sendable, Codable {
  /// A one- or two-sentence plain-language summary of what the module does.
  let summary: String
  /// The data flow as ordered steps: input → transform → output. Each step is
  /// a short prose line (the view numbers them).
  let dataFlow: [String]
  /// The key functions/symbols a reader should know, each a code reference
  /// (mono) paired with a plain-prose role.
  let keyFunctions: [AnalysisFunction]
  /// What the module touches — files, packages, env, network, the filesystem —
  /// stated as facts, not warnings.
  let touches: [String]
  /// Honest limits / caveats: what it does *not* handle, assumptions it makes.
  let limits: [String]

  /// Whether there is anything worth showing. A model that returns nothing
  /// useful should be treated as "not analyzed" rather than rendering an empty
  /// shell.
  var isEmpty: Bool {
    summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && dataFlow.isEmpty
      && keyFunctions.isEmpty
      && touches.isEmpty
      && limits.isEmpty
  }
}

/// One key function in the analysis: a code reference (`name`, rendered mono)
/// and the plain-language `role` it plays.
struct AnalysisFunction: Equatable, Sendable, Codable {
  /// The symbol/function name — a code reference, so the view renders it mono.
  let name: String
  /// What the function does, in plain prose.
  let role: String
}

/// A cached analysis as the store returns it: the generated `content` plus the
/// metadata for the honesty footer ("Analyzed with <model>").
struct ModuleAnalysis: Equatable, Sendable {
  let content: ModuleAnalysisContent
  /// The model that wrote it (`nil` for a debug/canned analysis).
  let model: String?
  /// When it was generated (epoch ms), matching the store's clock.
  let generatedAt: Int64
}

extension ModuleAnalysis {
  /// A canned analysis used only by the `GUNK_DEBUG_HOW_IT_WORKS=open`
  /// screenshot hook, so the open state can be captured without a real model
  /// call or a seeded store row.
  static let sample = ModuleAnalysis(
    content: ModuleAnalysisContent(
      summary: "Converts an EPUB e-book into clean, chapter-split Markdown — "
        + "unzipping the container, walking the spine in reading order, and "
        + "flattening each XHTML document to text.",
      dataFlow: [
        "Reads an .epub path from the first positional argument.",
        "Unzips the container and parses content.opf for the spine order.",
        "Converts each spine document from XHTML to Markdown.",
        "Writes one Markdown file per chapter to the output directory.",
      ],
      keyFunctions: [
        AnalysisFunction(name: "convert(path:)", role: "The entrypoint — orchestrates the whole pipeline."),
        AnalysisFunction(name: "readSpine(_:)", role: "Parses the OPF manifest into an ordered chapter list."),
        AnalysisFunction(name: "xhtmlToMarkdown(_:)", role: "Flattens one XHTML document to Markdown."),
      ],
      touches: [
        "Reads the input .epub file and the output directory.",
        "Depends on `ebooklib` and `beautifulsoup4`.",
        "No network access.",
      ],
      limits: [
        "Assumes a well-formed EPUB 2/3 spine; malformed archives are skipped, not repaired.",
        "Drops embedded fonts and most CSS — text and structure only.",
        "Images are referenced by path, not inlined.",
      ]
    ),
    model: "claude-sonnet-4",
    generatedAt: 0
  )
}
