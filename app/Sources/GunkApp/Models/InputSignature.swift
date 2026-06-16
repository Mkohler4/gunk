import Foundation

/// The typed-input surface's data model (T-10.8): a small set of compact,
/// native controls derived from a module's entrypoint so a developer can feed
/// the module **their** data instead of only the staged demo.
///
/// Pure and derivation-only — no I/O, no store. The view binds field *values*
/// over it; `BrowseModel` composes those values into the runner's `arguments`
/// (the sandbox contract is unchanged — ADR-0016). Anything that can't be
/// inferred confidently is left out: an unreliable signature falls back to the
/// zero-touch terminal path (T-10.7) rather than fabricating wrong controls.

/// One inferred input control. Its `kind` picks the native control; `demoValue`
/// is the prefilled staged-demo value (empty until T-10.9 stages a real demo —
/// the prefill is a forward seam, so a zero-touch run with an empty file field
/// stays identical to the T-10.7 bare command).
struct InputField: Equatable, Identifiable, Sendable {
  let id: String
  /// A short human label ("EPUB file", "Text", "Format").
  let label: String
  let kind: InputFieldKind
  /// Quiet guidance shown under the control — "this entrypoint takes a `.epub`"
  /// — never a system warning (CP-F). Optional.
  let hint: String?
  /// Whether the command is incomplete without this field (a *missing
  /// requirement* when cleared). The demo prefill keeps the zero-touch run
  /// working; clearing a required field surfaces quiet guidance.
  let required: Bool
  /// The prefilled staged-demo value. Empty until a real demo is staged
  /// (T-10.9). A file field carries an absolute path here once it exists.
  let demoValue: String

  init(
    id: String,
    label: String,
    kind: InputFieldKind,
    hint: String? = nil,
    required: Bool = false,
    demoValue: String = ""
  ) {
    self.id = id
    self.label = label
    self.kind = kind
    self.hint = hint
    self.required = required
    self.demoValue = demoValue
  }
}

/// The control a field renders as. File compose as a positional path argument
/// (the most common one-shot convention); text/number/choice compose their
/// value as a positional token. Env vars are deliberately **absent**: the
/// sandbox passes no environment (ADR-0016 — secrets are never injected), so an
/// env "input" could not honestly affect the run; module env *requirements*
/// surface in the T-10.6 readout instead.
enum InputFieldKind: Equatable, Sendable {
  /// A file drop well, restricted to the inferred extensions (lowercased, no
  /// dot — e.g. `["epub"]`). Empty means "any file".
  case file(extensions: [String])
  case text
  case number
  /// A dropdown of fixed options.
  case choice(options: [String])
}

/// The inferred input surface for a module: an ordered list of fields plus
/// whether the inference was confident enough to show controls at all.
struct InputSignature: Equatable, Sendable {
  let fields: [InputField]
  /// `false` → the page shows nothing typed and quietly falls back to the bare
  /// "Try it" run (T-10.7). We never invent controls we can't stand behind.
  let reliable: Bool

  static let unreliable = InputSignature(fields: [], reliable: false)

  var isEmpty: Bool { fields.isEmpty }

  /// Composes the developer's current values into the runner's positional
  /// arguments, in field order. A value is contributed only when present (so an
  /// empty file field — the demo-less default — yields the bare command, the
  /// zero-touch floor). Whitespace-only values are treated as empty.
  func arguments(from values: [String: String]) -> [String] {
    fields.compactMap { field in
      let value = (values[field.id] ?? field.demoValue)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? nil : value
    }
  }
}

/// The validation state of a single field's current value — drives the quiet
/// guidance (CP-F: guidance, not warnings).
enum InputFieldValidation: Equatable, Sendable {
  /// Present and acceptable (or empty + optional).
  case ok
  /// A required field is empty (the *missing requirement* state).
  case missing
  /// A file whose extension doesn't match the entrypoint's expectation.
  case wrongFileType(expected: [String])
  /// A file larger than the sandbox input cap.
  case tooLarge(limitBytes: Int)
  /// A number field whose value isn't numeric.
  case notANumber
}

/// Sandbox-boundary limits for developer-provided inputs (T-10.2 contract).
/// A file the developer drops is read inside the sandbox (reads are allowed;
/// writes/network are not — ADR-0016), but it must be bounded so a huge file
/// can't blow the run dir or the timeout.
enum InputLimits {
  /// 25 MB — generous for documents/data, far short of "stage a whole corpus".
  static let maxFileBytes = 25 * 1024 * 1024
}

/// Validates a single field's value against its kind. Pure; the view renders
/// the returned state as quiet guidance and gates Run on it.
enum InputValidator {
  static func validate(
    field: InputField,
    value: String,
    fileSizeBytes: Int? = nil
  ) -> InputFieldValidation {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.isEmpty {
      return field.required ? .missing : .ok
    }

    switch field.kind {
    case .file(let extensions):
      if !extensions.isEmpty {
        let ext = (trimmed as NSString).pathExtension.lowercased()
        if !extensions.contains(ext) {
          return .wrongFileType(expected: extensions)
        }
      }
      if let bytes = fileSizeBytes, bytes > InputLimits.maxFileBytes {
        return .tooLarge(limitBytes: InputLimits.maxFileBytes)
      }
      return .ok
    case .number:
      return Double(trimmed) == nil ? .notANumber : .ok
    case .text, .choice:
      return .ok
    }
  }
}

/// Derives an input signature from what a module already exposes (entrypoint,
/// language, purpose, parsed requirements). There is no persisted per-parameter
/// signature today (Hard data fact 4 carries only `{path, symbol}`), so this is
/// a **conservative heuristic**: it infers a file input when the purpose /
/// symbol / filenames clearly name a file format, an optional text input for
/// obviously string-in utilities, and otherwise reports `unreliable` so the
/// page falls back to the zero-touch terminal path. It never guesses an env var
/// or a flag shape it can't stand behind.
enum InputSignatureInference {
  /// File-format keywords → the extension(s) a drop well should accept. Ordered
  /// so the first match wins (most specific document/data formats first).
  private static let fileKeywords: [(keyword: String, extensions: [String])] = [
    ("epub", ["epub"]),
    ("pdf", ["pdf"]),
    ("markdown", ["md", "markdown"]),
    ("csv", ["csv"]),
    ("tsv", ["tsv"]),
    ("json", ["json"]),
    ("yaml", ["yaml", "yml"]),
    ("xml", ["xml"]),
    ("html", ["html", "htm"]),
    ("svg", ["svg"]),
    ("png", ["png"]),
    ("jpeg", ["jpg", "jpeg"]),
    ("jpg", ["jpg", "jpeg"]),
    ("image", ["png", "jpg", "jpeg", "gif", "webp"]),
    ("audio", ["mp3", "wav", "m4a", "flac"]),
    ("mp3", ["mp3"]),
    ("wav", ["wav"]),
    ("subtitle", ["srt", "vtt"]),
    ("zip", ["zip"]),
    ("archive", ["zip", "tar", "gz"]),
    ("spreadsheet", ["xlsx", "csv"]),
  ]

  /// Purpose/symbol fragments that mark a plain string-in utility (the
  /// low-level "slugify a string" family the future-vision section calls out).
  private static let textKeywords: Set<String> = [
    "slug", "slugify", "string", "text", "sentence", "phrase", "word",
  ]

  static func infer(
    entrypoints: [BrowseEntrypoint],
    language: String?,
    purpose: String?,
    requirements: ModuleRequirements?
  ) -> InputSignature {
    // Only modules with a runnable interpreter get a typed surface; everything
    // else renders the not-runnable-here state, not inputs.
    switch ModuleLanguage(rawLanguage: language ?? "") {
    case .python, .node:
      break
    case .other:
      return .unreliable
    }

    let haystack = corpus(entrypoints: entrypoints, purpose: purpose)

    if let match = fileKeywords.first(where: { haystack.contains($0.keyword) }) {
      let pretty = match.extensions.map { ".\($0)" }.joined(separator: " / ")
      let field = InputField(
        id: "input-file",
        label: "Input file",
        kind: .file(extensions: match.extensions),
        hint: "This entrypoint takes a \(pretty) file. Drop your own to run it on your data.",
        required: false
      )
      return InputSignature(fields: [field], reliable: true)
    }

    if textKeywords.contains(where: { haystack.contains($0) }) {
      let field = InputField(
        id: "input-text",
        label: "Input text",
        kind: .text,
        hint: "This entrypoint takes a string. Type your own to run it on your data.",
        required: false
      )
      return InputSignature(fields: [field], reliable: true)
    }

    // Nothing confident to infer → quiet fallback to the bare terminal path.
    return .unreliable
  }

  /// The lowercased text the heuristics scan: the purpose, the entrypoint
  /// symbols, and the entrypoint filenames.
  private static func corpus(entrypoints: [BrowseEntrypoint], purpose: String?) -> String {
    var parts: [String] = []
    if let purpose { parts.append(purpose) }
    for entry in entrypoints {
      if let symbol = entry.symbol { parts.append(symbol) }
      parts.append((entry.path as NSString).lastPathComponent)
    }
    return parts.joined(separator: " ").lowercased()
  }
}
