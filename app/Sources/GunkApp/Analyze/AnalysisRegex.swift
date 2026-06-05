import Foundation

func analysisFirstMatch(in text: String, pattern: String) -> String? {
  analysisMatches(in: text, pattern: pattern).first?.first
}

func analysisMatches(in text: String, pattern: String) -> [[String]] {
  guard let regex = try? NSRegularExpression(pattern: pattern) else {
    return []
  }

  let nsString = text as NSString
  let range = NSRange(location: 0, length: nsString.length)

  return regex.matches(in: text, range: range).map { match in
    (1..<match.numberOfRanges).compactMap { index in
      let range = match.range(at: index)
      guard range.location != NSNotFound else {
        return nil
      }

      return nsString.substring(with: range)
    }
  }
}
