import Foundation

struct SymbolFile: Equatable, Sendable {
  let path: String
  let contents: String

  init(path: String, contents: String) {
    self.path = path
    self.contents = contents
  }
}

struct FileSymbols: Equatable, Sendable {
  let path: String
  let language: LanguageKind
  let symbols: [Symbol]
  let imports: [ImportRef]
  let exports: [ExportRef]
}

struct Symbol: Equatable, Hashable, Sendable {
  enum Kind: String, Equatable, Hashable, Sendable {
    case `class`
    case `enum`
    case function
    case interface
    case method
    case protocolDecl
    case `struct`
    case type
    case variable
  }

  let name: String
  let kind: Kind
  let line: Int
}

struct ImportRef: Equatable, Hashable, Sendable {
  let moduleSpecifier: String
  let resolvedTarget: String?
  let line: Int
}

struct ExportRef: Equatable, Hashable, Sendable {
  let name: String
  let kind: Symbol.Kind?
  let line: Int
}

enum LanguageKind: String, Equatable, Sendable {
  case go
  case javaScript
  case python
  case swift
  case typeScript
  case unknown

  init(path: String) {
    let lowercasedPath = path.lowercased()

    if lowercasedPath.hasSuffix(".go") {
      self = .go
    } else if lowercasedPath.hasSuffix(".js") || lowercasedPath.hasSuffix(".jsx") || lowercasedPath.hasSuffix(".mjs") {
      self = .javaScript
    } else if lowercasedPath.hasSuffix(".py") {
      self = .python
    } else if lowercasedPath.hasSuffix(".swift") {
      self = .swift
    } else if lowercasedPath.hasSuffix(".ts") || lowercasedPath.hasSuffix(".tsx") || lowercasedPath.hasSuffix(".mts") {
      self = .typeScript
    } else {
      self = .unknown
    }
  }
}
