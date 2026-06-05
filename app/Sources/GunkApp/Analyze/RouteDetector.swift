import Foundation

struct RouteSurface: Equatable, Hashable, Sendable {
  enum Framework: String, Equatable, Hashable, Sendable {
    case express
    case fastAPI
    case flask
    case gin
    case next
  }

  let framework: Framework
  let method: String
  let path: String
  let handler: String?
  let line: Int
}

struct RouteDetector: Sendable {
  func detect(path: String, contents: String) -> [RouteSurface] {
    var routes: [RouteSurface] = []

    routes.append(contentsOf: detectExpressRoutes(in: contents))
    if contents.contains("FastAPI") || contents.contains("APIRouter") || contents.contains("from fastapi") {
      routes.append(contentsOf: detectPythonDecoratorRoutes(in: contents, framework: .fastAPI))
    }
    if contents.contains("Flask") || contents.contains("Blueprint") || contents.contains("from flask") {
      routes.append(contentsOf: detectPythonDecoratorRoutes(in: contents, framework: .flask))
    }
    routes.append(contentsOf: detectGinRoutes(in: contents))
    routes.append(contentsOf: detectNextRoutes(path: path, contents: contents))

    var seen = Set<RouteSurface>()
    let uniqueRoutes = routes.filter { route in
      seen.insert(route).inserted
    }

    return uniqueRoutes.sorted { lhs, rhs in
      lhs.line == rhs.line ? lhs.path < rhs.path : lhs.line < rhs.line
    }
  }

  private func detectExpressRoutes(in contents: String) -> [RouteSurface] {
    routeMatches(
      in: contents,
      pattern: #"\b(?:app|router)\.(get|post|put|patch|delete|head|options|all)\s*\(\s*["']([^"']+)["']\s*,\s*([A-Za-z_$][A-Za-z0-9_$]*)?"#,
      framework: .express
    )
  }

  private func detectPythonDecoratorRoutes(in contents: String, framework: RouteSurface.Framework) -> [RouteSurface] {
    let receiver = framework == .fastAPI ? #"(?:app|router)"# : #"(?:app|bp|blueprint)"#
    return routeMatches(
      in: contents,
      pattern: #"@\#(receiver)\.(get|post|put|patch|delete|route)\s*\(\s*["']([^"']+)["']"#,
      framework: framework
    )
  }

  private func detectGinRoutes(in contents: String) -> [RouteSurface] {
    routeMatches(
      in: contents,
      pattern: #"\b[A-Za-z_][A-Za-z0-9_]*\.(GET|POST|PUT|PATCH|DELETE|Any)\s*\(\s*["']([^"']+)["']\s*,\s*([A-Za-z_][A-Za-z0-9_]*)?"#,
      framework: .gin
    )
  }

  private func detectNextRoutes(path: String, contents: String) -> [RouteSurface] {
    guard path.hasSuffix("route.ts") || path.hasSuffix("route.js") || path.hasSuffix("route.tsx") || path.hasSuffix("route.jsx") else {
      return []
    }

    guard let regex = try? NSRegularExpression(pattern: #"export\s+(?:async\s+)?function\s+(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b"#) else {
      return []
    }

    let routePath = nextRoutePath(from: path)
    let nsString = contents as NSString
    let fullRange = NSRange(location: 0, length: nsString.length)

    return regex.matches(in: contents, range: fullRange).compactMap { match in
      let methodRange = match.range(at: 1)
      guard methodRange.location != NSNotFound else {
        return nil
      }

      let method = nsString.substring(with: methodRange)
      return RouteSurface(
        framework: .next,
        method: method.uppercased(),
        path: routePath,
        handler: method,
        line: lineNumber(atUTF16Offset: match.range.location, in: contents)
      )
    }
  }

  private func routeMatches(in contents: String, pattern: String, framework: RouteSurface.Framework) -> [RouteSurface] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return []
    }

    let nsString = contents as NSString
    let fullRange = NSRange(location: 0, length: nsString.length)

    return regex.matches(in: contents, range: fullRange).compactMap { match in
      let groups = (1..<match.numberOfRanges).compactMap { index -> String? in
        let range = match.range(at: index)
        guard range.location != NSNotFound else {
          return nil
        }

        return nsString.substring(with: range)
      }

      guard groups.count >= 2 else {
        return nil
      }

      return RouteSurface(
        framework: framework,
        method: groups[0].uppercased(),
        path: groups[1],
        handler: groups.dropFirst(2).first,
        line: lineNumber(atUTF16Offset: match.range.location, in: contents)
      )
    }
  }

  private func nextRoutePath(from path: String) -> String {
    var components = path.split(separator: "/").map(String.init)
    if let appIndex = components.firstIndex(of: "app") {
      components = Array(components.dropFirst(appIndex + 1))
    }

    if components.last?.hasPrefix("route.") == true {
      components.removeLast()
    }

    let visibleComponents = components.filter { component in
      !component.hasPrefix("(") && !component.hasPrefix("@")
    }
    .map { component in
      component.hasPrefix("[") && component.hasSuffix("]")
        ? ":\(component.dropFirst().dropLast())"
        : component
    }

    return "/" + visibleComponents.joined(separator: "/")
  }

  private func lineNumber(atUTF16Offset offset: Int, in contents: String) -> Int {
    let nsString = contents as NSString
    let prefix = nsString.substring(with: NSRange(location: 0, length: min(offset, nsString.length)))
    return prefix.reduce(1) { count, character in
      character == "\n" ? count + 1 : count
    }
  }
}
