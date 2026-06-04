import Darwin
import Foundation

struct Redaction: Equatable, Sendable {
  let path: String
  let reason: String
}

enum SecretRedactionResult: Equatable {
  case write(Data, [Redaction])
  case skip([Redaction])

  var redactions: [Redaction] {
    switch self {
    case .write(_, let redactions), .skip(let redactions):
      return redactions
    }
  }
}

final class SecretRedactor {
  private let secretNamePatterns = [
    ".env*",
    "*.pem",
    "*.key",
    "id_rsa*",
    "credentials*",
    "*.p12",
    "*.pfx"
  ]

  func redact(url: URL, relpath: String) throws -> SecretRedactionResult {
    if isSecretNamed(relpath: relpath) {
      return .skip([Redaction(path: relpath, reason: "secret_filename")])
    }

    let data = try Data(contentsOf: url)
    guard let contents = String(data: data, encoding: .utf8) else {
      return .skip([Redaction(path: relpath, reason: "non_utf8_unscannable")])
    }

    if privateKeyBlockPattern.firstMatch(
      in: contents,
      range: NSRange(contents.startIndex..., in: contents)
    ) != nil {
      return .skip([Redaction(path: relpath, reason: "private_key_block")])
    }

    var didRedact = false
    let redactedLines = contents.components(separatedBy: .newlines).map { line in
      if lineMatchesKnownSecret(line) || lineMatchesHighEntropySecret(line) {
        didRedact = true
        return "[gunk redacted: secret-like content]"
      }

      return line
    }

    guard didRedact else {
      return .write(data, [])
    }

    let redacted = redactedLines.joined(separator: "\n")
    return .write(
      Data(redacted.utf8),
      [Redaction(path: relpath, reason: "secret_like_content")]
    )
  }

  private func isSecretNamed(relpath: String) -> Bool {
    let normalized = relpath
      .replacingOccurrences(of: "\\", with: "/")
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let basename = URL(fileURLWithPath: normalized).lastPathComponent
    let candidates = [basename, normalized]

    return secretNamePatterns.contains { pattern in
      candidates.contains { candidate in
        fnmatch(pattern, candidate, FNM_CASEFOLD) == 0
      }
    }
  }

  private func lineMatchesKnownSecret(_ line: String) -> Bool {
    secretContentPatterns.contains { pattern in
      pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }
  }

  private func lineMatchesHighEntropySecret(_ line: String) -> Bool {
    highEntropyPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
      && line.range(of: #"(?i)(secret|token|api[_-]?key|password|credential)"#, options: .regularExpression) != nil
  }
}

private let secretContentPatterns = [
  try! NSRegularExpression(pattern: #"AKIA[0-9A-Z]{12,}"#),
  try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{12,}"#)
]

private let privateKeyBlockPattern = try! NSRegularExpression(
  pattern: #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#
)

private let highEntropyPattern = try! NSRegularExpression(
  pattern: #"[A-Za-z0-9+/=_-]{40,}"#
)
