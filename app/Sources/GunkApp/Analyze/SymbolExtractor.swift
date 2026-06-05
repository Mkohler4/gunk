import Foundation
import SwiftTreeSitter
import TreeSitterGo
import TreeSitterJavaScript
import TreeSitterPython
import TreeSitterSwift
import TreeSitterTypeScript

protocol SymbolExtractor {
  func extract(file: SymbolFile) throws -> FileSymbols
}

enum SymbolExtractorError: Error, Equatable {
  case parseFailed(String)
}

final class TreeSitterSymbolExtractor: SymbolExtractor {
  func extract(file: SymbolFile) throws -> FileSymbols {
    let language = LanguageKind(path: file.path)

    guard language != .unknown else {
      return fallbackExtract(file: file, language: language)
    }

    let root = try parseRoot(file: file, language: language)
    var symbols: [Symbol] = []
    var imports: [ImportRef] = []
    var exports: [ExportRef] = []

    walk(root) { node in
      let type = node.nodeType ?? ""
      let text = nodeText(node, in: file.contents)
      let line = lineNumber(for: node, in: file.contents)

      switch language {
      case .javaScript, .typeScript:
        collectJavaScriptLike(
          node: node,
          type: type,
          text: text,
          line: line,
          symbols: &symbols,
          imports: &imports,
          exports: &exports
        )
      case .python:
        collectPython(
          node: node,
          type: type,
          text: text,
          line: line,
          symbols: &symbols,
          imports: &imports
        )
      case .swift:
        collectSwift(
          node: node,
          type: type,
          text: text,
          line: line,
          symbols: &symbols,
          imports: &imports,
          exports: &exports
        )
      case .go:
        collectGo(
          node: node,
          type: type,
          text: text,
          line: line,
          symbols: &symbols,
          imports: &imports,
          exports: &exports
        )
      case .unknown:
        break
      }
    }

    return FileSymbols(
      path: file.path,
      language: language,
      symbols: symbols.uniqued(),
      imports: imports.uniqued(),
      exports: exports.uniqued()
    )
  }

  private func parseRoot(file: SymbolFile, language: LanguageKind) throws -> Node {
    let parser = Parser()

    switch language {
    case .go:
      try parser.setLanguage(Language(language: tree_sitter_go()))
    case .javaScript:
      try parser.setLanguage(Language(language: tree_sitter_javascript()))
    case .python:
      try parser.setLanguage(Language(language: tree_sitter_python()))
    case .swift:
      try parser.setLanguage(Language(language: tree_sitter_swift()))
    case .typeScript:
      try parser.setLanguage(Language(language: tree_sitter_typescript()))
    case .unknown:
      throw SymbolExtractorError.parseFailed(file.path)
    }

    guard let tree = parser.parse(file.contents),
          let root = tree.rootNode else {
      throw SymbolExtractorError.parseFailed(file.path)
    }

    return root
  }

  private func collectJavaScriptLike(
    node: Node,
    type: String,
    text: String,
    line: Int,
    symbols: inout [Symbol],
    imports: inout [ImportRef],
    exports: inout [ExportRef]
  ) {
    switch type {
    case "import_statement":
      for specifier in moduleSpecifiers(in: text) {
        imports.append(ImportRef(moduleSpecifier: specifier, resolvedTarget: relativeTarget(for: specifier), line: line))
      }
    case "call_expression":
      if let specifier = requireSpecifier(in: text) {
        imports.append(ImportRef(moduleSpecifier: specifier, resolvedTarget: relativeTarget(for: specifier), line: line))
      }
    case "function_declaration":
      appendSymbol(from: node, in: text, kind: .function, line: line, symbols: &symbols)
    case "class_declaration":
      appendSymbol(from: node, in: text, kind: .class, line: line, symbols: &symbols)
    case "method_definition":
      appendSymbol(from: node, in: text, kind: .method, line: line, symbols: &symbols)
    case "interface_declaration":
      appendSymbol(from: node, in: text, kind: .interface, line: line, symbols: &symbols)
    case "type_alias_declaration":
      appendSymbol(from: node, in: text, kind: .type, line: line, symbols: &symbols)
    case "lexical_declaration", "variable_declaration":
      for name in variableNames(in: text) {
        symbols.append(Symbol(name: name, kind: .variable, line: line))
      }
    case "export_statement":
      exports.append(contentsOf: javaScriptExports(in: text, line: line))
      for specifier in moduleSpecifiers(in: text) {
        imports.append(ImportRef(moduleSpecifier: specifier, resolvedTarget: relativeTarget(for: specifier), line: line))
      }
    default:
      break
    }
  }

  private func collectPython(
    node: Node,
    type: String,
    text: String,
    line: Int,
    symbols: inout [Symbol],
    imports: inout [ImportRef]
  ) {
    switch type {
    case "import_statement", "import_from_statement":
      for specifier in pythonImportSpecifiers(in: text) {
        imports.append(ImportRef(moduleSpecifier: specifier, resolvedTarget: nil, line: line))
      }
    case "function_definition":
      appendSymbol(from: node, in: text, kind: .function, line: line, symbols: &symbols)
    case "class_definition":
      appendSymbol(from: node, in: text, kind: .class, line: line, symbols: &symbols)
    default:
      break
    }
  }

  private func collectSwift(
    node: Node,
    type: String,
    text: String,
    line: Int,
    symbols: inout [Symbol],
    imports: inout [ImportRef],
    exports: inout [ExportRef]
  ) {
    switch type {
    case "import_declaration":
      if let specifier = firstMatch(in: text, pattern: #"import\s+(?:\w+\s+)?([A-Za-z_][A-Za-z0-9_]*)"#) {
        imports.append(ImportRef(moduleSpecifier: specifier, resolvedTarget: nil, line: line))
      }
    case "function_declaration":
      appendSwiftDeclaration(in: text, line: line, symbols: &symbols, exports: &exports)
    case "class_declaration":
      appendSwiftDeclaration(in: text, line: line, symbols: &symbols, exports: &exports)
    case "struct_declaration":
      appendSwiftDeclaration(in: text, line: line, symbols: &symbols, exports: &exports)
    case "enum_declaration":
      appendSwiftDeclaration(in: text, line: line, symbols: &symbols, exports: &exports)
    case "protocol_declaration":
      appendSwiftDeclaration(in: text, line: line, symbols: &symbols, exports: &exports)
    default:
      break
    }
  }

  private func collectGo(
    node: Node,
    type: String,
    text: String,
    line: Int,
    symbols: inout [Symbol],
    imports: inout [ImportRef],
    exports: inout [ExportRef]
  ) {
    switch type {
    case "import_spec":
      for specifier in moduleSpecifiers(in: text) {
        imports.append(ImportRef(moduleSpecifier: specifier, resolvedTarget: nil, line: line))
      }
    case "function_declaration":
      appendSymbol(from: node, in: text, kind: .function, line: line, symbols: &symbols)
    case "method_declaration":
      appendSymbol(from: node, in: text, kind: .method, line: line, symbols: &symbols)
    case "type_declaration":
      for name in goTypeNames(in: text) {
        let symbol = Symbol(name: name, kind: .type, line: line)
        symbols.append(symbol)
        if name.first?.isUppercase == true {
          exports.append(ExportRef(name: name, kind: .type, line: line))
        }
      }
    default:
      break
    }

    if let symbol = symbols.last,
       symbol.line == line,
       symbol.name.first?.isUppercase == true {
      exports.append(ExportRef(name: symbol.name, kind: symbol.kind, line: line))
    }
  }

  private func appendSymbol(from node: Node, in text: String, kind: Symbol.Kind, line: Int, symbols: inout [Symbol]) {
    guard let nameNode = node.child(byFieldName: "name") else {
      return
    }

    let nodeLocation = node.range.location
    let relativeRange = NSRange(location: nameNode.range.location - nodeLocation, length: nameNode.range.length)
    let nsString = text as NSString
    guard relativeRange.location >= 0,
          relativeRange.location + relativeRange.length <= nsString.length else {
      return
    }

    let name = nsString.substring(with: relativeRange)
    guard !name.isEmpty else {
      return
    }

    symbols.append(Symbol(name: name, kind: kind, line: line))
  }

  private func appendSwiftDeclaration(in text: String, line: Int, symbols: inout [Symbol], exports: inout [ExportRef]) {
    guard let symbol = swiftPrimaryDeclaration(in: text, line: line) else {
      return
    }

    symbols.append(symbol)

    if swiftPrimaryDeclarationIsExported(in: text) {
      exports.append(ExportRef(name: symbol.name, kind: symbol.kind, line: line))
    }
  }

  private func fallbackExtract(file: SymbolFile, language: LanguageKind) -> FileSymbols {
    let imports = fallbackImports(in: file.contents)
    let symbols = fallbackSymbols(in: file.contents)

    return FileSymbols(
      path: file.path,
      language: language,
      symbols: symbols,
      imports: imports,
      exports: []
    )
  }
}

private func walk(_ node: Node, visit: (Node) -> Void) {
  visit(node)

  for index in 0..<node.childCount {
    guard let child = node.child(at: index) else {
      continue
    }

    walk(child, visit: visit)
  }
}

private func nodeText(_ node: Node, in contents: String) -> String {
  guard !contents.isEmpty else {
    return node.sExpressionString ?? ""
  }

  let nsString = contents as NSString
  let range = node.range
  guard range.location >= 0,
        range.location + range.length <= nsString.length else {
    return ""
  }

  return nsString.substring(with: range)
}

private func lineNumber(for node: Node, in contents: String) -> Int {
  let nsString = contents as NSString
  let location = max(0, min(node.range.location, nsString.length))
  let prefix = nsString.substring(with: NSRange(location: 0, length: location))
  return prefix.reduce(1) { count, character in
    character == "\n" ? count + 1 : count
  }
}

private func moduleSpecifiers(in text: String) -> [String] {
  matches(in: text, pattern: #""([^"]+)"|'([^']+)'"#)
    .compactMap { $0.first(where: { !$0.isEmpty }) }
}

private func requireSpecifier(in text: String) -> String? {
  firstMatch(in: text, pattern: #"require\s*\(\s*["']([^"']+)["']\s*\)"#)
}

private func pythonImportSpecifiers(in text: String) -> [String] {
  if let fromModule = firstMatch(in: text, pattern: #"^from\s+([A-Za-z_][A-Za-z0-9_\.]*)\s+import\s+"#) {
    return [fromModule]
  }

  guard let imported = firstMatch(in: text, pattern: #"^import\s+(.+)$"#) else {
    return []
  }

  return imported
    .split(separator: ",")
    .map { part in
      part.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: " ")
        .first
        .map(String.init) ?? ""
    }
    .filter { !$0.isEmpty }
}

private func variableNames(in text: String) -> [String] {
  matches(in: text, pattern: #"(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)"#)
    .compactMap(\.first)
}

private func javaScriptExports(in text: String, line: Int) -> [ExportRef] {
  var exports: [ExportRef] = []

  let patterns: [(String, Symbol.Kind)] = [
    (#"export\s+(?:default\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)"#, .function),
    (#"export\s+(?:default\s+)?class\s+([A-Za-z_$][A-Za-z0-9_$]*)"#, .class),
    (#"export\s+interface\s+([A-Za-z_$][A-Za-z0-9_$]*)"#, .interface),
    (#"export\s+type\s+([A-Za-z_$][A-Za-z0-9_$]*)"#, .type),
    (#"export\s+(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)"#, .variable)
  ]

  for (pattern, kind) in patterns {
    exports.append(contentsOf: matches(in: text, pattern: pattern).compactMap(\.first).map {
      ExportRef(name: $0, kind: kind, line: line)
    })
  }

  if let namedExports = firstMatch(in: text, pattern: #"export\s*\{([^}]+)\}"#) {
    exports.append(
      contentsOf: namedExports
        .split(separator: ",")
        .map { part in
          part.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: " as ")
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        .filter { !$0.isEmpty }
        .map { ExportRef(name: $0, kind: nil, line: line) }
    )
  }

  return exports
}

private func swiftPrimaryDeclaration(in text: String, line: Int) -> Symbol? {
  guard let regex = try? NSRegularExpression(
    pattern: #"\b(func|class|struct|enum|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
    options: []
  ) else {
    return nil
  }

  let nsString = text as NSString
  let range = NSRange(location: 0, length: nsString.length)
  guard let match = regex.firstMatch(in: text, range: range),
        match.numberOfRanges == 3,
        match.range(at: 1).location != NSNotFound,
        match.range(at: 2).location != NSNotFound else {
    return nil
  }

  let keyword = nsString.substring(with: match.range(at: 1))
  let name = nsString.substring(with: match.range(at: 2))

  let kind: Symbol.Kind
  switch keyword {
  case "func":
    kind = .function
  case "class":
    kind = .class
  case "struct":
    kind = .struct
  case "enum":
    kind = .enum
  case "protocol":
    kind = .protocolDecl
  default:
    return nil
  }

  return Symbol(name: name, kind: kind, line: line)
}

private func swiftPrimaryDeclarationIsExported(in text: String) -> Bool {
  guard let regex = try? NSRegularExpression(
    pattern: #"^\s*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s*)*(?:public|open)\s+\b(?:func|class|struct|enum|protocol)\b"#,
    options: []
  ) else {
    return false
  }

  let nsString = text as NSString
  return regex.firstMatch(in: text, range: NSRange(location: 0, length: nsString.length)) != nil
}

private func goTypeNames(in text: String) -> [String] {
  matches(in: text, pattern: #"type\s+([A-Za-z_][A-Za-z0-9_]*)"#)
    .compactMap(\.first)
}

private func fallbackImports(in text: String) -> [ImportRef] {
  var imports: [ImportRef] = []
  let lines = text.components(separatedBy: .newlines)

  for (index, line) in lines.enumerated() {
    let lineNumber = index + 1
    for specifier in moduleSpecifiers(in: line) where line.contains("import") || line.contains("require") {
      imports.append(ImportRef(moduleSpecifier: specifier, resolvedTarget: relativeTarget(for: specifier), line: lineNumber))
    }

    if let pythonModule = firstMatch(in: line, pattern: #"^(?:from|import)\s+([A-Za-z_][A-Za-z0-9_\.]*)"#) {
      imports.append(ImportRef(moduleSpecifier: pythonModule, resolvedTarget: nil, line: lineNumber))
    }

    if let swiftModule = firstMatch(in: line, pattern: #"^import\s+([A-Za-z_][A-Za-z0-9_]*)"#) {
      imports.append(ImportRef(moduleSpecifier: swiftModule, resolvedTarget: nil, line: lineNumber))
    }
  }

  return imports.uniqued()
}

private func fallbackSymbols(in text: String) -> [Symbol] {
  var symbols: [Symbol] = []
  let lines = text.components(separatedBy: .newlines)

  for (index, line) in lines.enumerated() {
    let lineNumber = index + 1

    if let name = firstMatch(in: line, pattern: #"\bfunction\s+([A-Za-z_$][A-Za-z0-9_$]*)"#) {
      symbols.append(Symbol(name: name, kind: .function, line: lineNumber))
    }

    if let name = firstMatch(in: line, pattern: #"\bclass\s+([A-Za-z_$][A-Za-z0-9_$]*)"#) {
      symbols.append(Symbol(name: name, kind: .class, line: lineNumber))
    }
  }

  return symbols.uniqued()
}

private func relativeTarget(for specifier: String) -> String? {
  specifier.hasPrefix(".") ? specifier : nil
}

private func firstMatch(in text: String, pattern: String) -> String? {
  matches(in: text, pattern: pattern).first?.first
}

private func matches(in text: String, pattern: String) -> [[String]] {
  guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
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

private extension Array where Element: Hashable {
  func uniqued() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
