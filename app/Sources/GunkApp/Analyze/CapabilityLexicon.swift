import Foundation

struct CapabilityHint: Equatable, Hashable, Sendable {
  let library: String
  let labels: Set<String>
}

struct CapabilityLexicon: Sendable {
  static let `default` = CapabilityLexicon(entries: [
    "passport-google-oauth20": ["auth", "google", "oauth"],
    "google-auth-library": ["auth", "google"],
    "next-auth": ["auth"],
    "@auth/core": ["auth"],
    "@clerk/nextjs": ["auth", "clerk"],
    "auth0": ["auth", "auth0"],
    "stripe": ["payments", "billing"],
    "@stripe/stripe-js": ["payments", "billing"],
    "paypal-rest-sdk": ["payments", "paypal"],
    "twilio": ["messaging", "sms"],
    "@sendgrid/mail": ["email", "sendgrid"],
    "nodemailer": ["email"],
    "openai": ["ai", "openai"],
    "langchain": ["ai", "llm"],
    "firebase": ["firebase"],
    "@aws-sdk/client-s3": ["storage", "s3", "aws"],
    "aws-sdk": ["aws"],
    "pg": ["database", "postgres"],
    "prisma": ["database", "orm"]
  ])

  private let entries: [String: Set<String>]

  init(entries: [String: Set<String>]) {
    self.entries = entries.reduce(into: [:]) { result, entry in
      result[Self.normalize(entry.key)] = entry.value
    }
  }

  func hint(for library: String) -> CapabilityHint? {
    let normalized = Self.normalize(library)
    guard let labels = entries[normalized] else {
      return nil
    }

    return CapabilityHint(library: library, labels: labels)
  }

  private static func normalize(_ value: String) -> String {
    value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
