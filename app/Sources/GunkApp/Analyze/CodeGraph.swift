import Foundation

struct CodeGraphNode: Equatable, Hashable, Sendable {
  enum Kind: Equatable, Hashable, Sendable {
    case file
    case symbol(Symbol.Kind)
  }

  let id: String
  let kind: Kind
  let filePath: String
  let symbolName: String?

  static func file(_ path: String) -> CodeGraphNode {
    CodeGraphNode(id: "file:\(path)", kind: .file, filePath: path, symbolName: nil)
  }

  static func symbol(_ symbol: Symbol, in path: String) -> CodeGraphNode {
    CodeGraphNode(
      id: "symbol:\(path)#\(symbol.name)",
      kind: .symbol(symbol.kind),
      filePath: path,
      symbolName: symbol.name
    )
  }
}

enum CodeGraphEdgeKind: String, Equatable, Hashable, Sendable {
  case call
  case `import`
  case implements
  case inherit
  case reference
}

struct CodeGraphEdge: Equatable, Hashable, Sendable {
  let from: CodeGraphNode
  let to: CodeGraphNode
  let kind: CodeGraphEdgeKind
}

struct CodeGraph: Equatable, Sendable {
  let nodes: Set<CodeGraphNode>
  let edges: Set<CodeGraphEdge>
  let externalDependencies: [String: Set<String>]

  func neighbors(of node: CodeGraphNode, kinds: Set<CodeGraphEdgeKind>? = nil) -> Set<CodeGraphNode> {
    Set(outboundEdges(from: node, kinds: kinds).map(\.to))
  }

  func outboundEdges(from node: CodeGraphNode, kinds: Set<CodeGraphEdgeKind>? = nil) -> Set<CodeGraphEdge> {
    Set(edges.filter { edge in
      edge.from == node && (kinds == nil || kinds?.contains(edge.kind) == true)
    })
  }

  func inboundEdges(to node: CodeGraphNode, kinds: Set<CodeGraphEdgeKind>? = nil) -> Set<CodeGraphEdge> {
    Set(edges.filter { edge in
      edge.to == node && (kinds == nil || kinds?.contains(edge.kind) == true)
    })
  }

  func transitiveClosure(from node: CodeGraphNode, maxDepth: Int, kinds: Set<CodeGraphEdgeKind>? = nil) -> Set<CodeGraphNode> {
    guard maxDepth > 0 else {
      return []
    }

    var visited: Set<CodeGraphNode> = []
    var frontier: Set<CodeGraphNode> = [node]

    for _ in 0..<maxDepth {
      let next = Set(frontier.flatMap { neighbors(of: $0, kinds: kinds) }).subtracting(visited).subtracting([node])
      guard !next.isEmpty else {
        break
      }

      visited.formUnion(next)
      frontier = next
    }

    return visited
  }
}

struct CodeGraphBuilder: Sendable {
  private let resolver: ImportResolver

  init(resolver: ImportResolver) {
    self.resolver = resolver
  }

  func build(files: [FileSymbols], contentsByPath: [String: String] = [:]) -> CodeGraph {
    var nodes: Set<CodeGraphNode> = []
    var edges: Set<CodeGraphEdge> = []
    var externalDependencies: [String: Set<String>] = [:]

    let symbolNodesByPath = Dictionary(
      uniqueKeysWithValues: files.map { file in
        (file.path, file.symbols.map { CodeGraphNode.symbol($0, in: file.path) })
      }
    )
    let exportedSymbols = exportedSymbolIndex(files: files)

    for file in files {
      let fileNode = CodeGraphNode.file(file.path)
      nodes.insert(fileNode)
      nodes.formUnion(symbolNodesByPath[file.path] ?? [])

      for importRef in file.imports {
        guard let targetPath = resolver.resolve(importRef.moduleSpecifier, from: file.path) ?? importRef.resolvedTarget else {
          externalDependencies[file.path, default: []].insert(importRef.moduleSpecifier)
          continue
        }

        let targetNode = CodeGraphNode.file(targetPath)
        nodes.insert(targetNode)
        edges.insert(CodeGraphEdge(from: fileNode, to: targetNode, kind: .import))
      }

      guard let contents = contentsByPath[file.path] else {
        continue
      }

      for exported in exportedSymbols where exported.filePath != file.path {
        let symbolNode = CodeGraphNode.symbol(exported.symbol, in: exported.filePath)
        nodes.insert(symbolNode)

        if containsCall(to: exported.symbol.name, in: contents) {
          edges.insert(CodeGraphEdge(from: fileNode, to: symbolNode, kind: .call))
        } else if containsReference(to: exported.symbol.name, in: contents) {
          edges.insert(CodeGraphEdge(from: fileNode, to: symbolNode, kind: .reference))
        }

        if containsInheritance(of: exported.symbol.name, in: contents) {
          edges.insert(CodeGraphEdge(from: fileNode, to: symbolNode, kind: .inherit))
        }

        if containsImplementation(of: exported.symbol.name, in: contents) {
          edges.insert(CodeGraphEdge(from: fileNode, to: symbolNode, kind: .implements))
        }
      }
    }

    return CodeGraph(nodes: nodes, edges: edges, externalDependencies: externalDependencies)
  }

  private func exportedSymbolIndex(files: [FileSymbols]) -> [(filePath: String, symbol: Symbol)] {
    files.flatMap { file in
      let exportedNames = Set(file.exports.map(\.name))
      return file.symbols
        .filter { exportedNames.contains($0.name) || file.exports.isEmpty }
        .map { (file.path, $0) }
    }
  }

  private func containsCall(to symbolName: String, in contents: String) -> Bool {
    regexMatch(#"\b\#(NSRegularExpression.escapedPattern(for: symbolName))\s*\("#, in: contents)
  }

  private func containsReference(to symbolName: String, in contents: String) -> Bool {
    regexMatch(#"\b\#(NSRegularExpression.escapedPattern(for: symbolName))\b"#, in: contents)
  }

  private func containsInheritance(of symbolName: String, in contents: String) -> Bool {
    let escaped = NSRegularExpression.escapedPattern(for: symbolName)
    return regexMatch(#"\bextends\s+\#(escaped)\b"#, in: contents)
      || regexMatch(#":\s*\#(escaped)\b"#, in: contents)
  }

  private func containsImplementation(of symbolName: String, in contents: String) -> Bool {
    regexMatch(#"\bimplements\s+\#(NSRegularExpression.escapedPattern(for: symbolName))\b"#, in: contents)
  }

  private func regexMatch(_ pattern: String, in contents: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return false
    }

    let range = NSRange(location: 0, length: (contents as NSString).length)
    return regex.firstMatch(in: contents, range: range) != nil
  }
}
