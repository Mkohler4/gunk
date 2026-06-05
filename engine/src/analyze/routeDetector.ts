import { lineNumberAtOffset } from "./analysisRegex.js";

export type RouteFramework = "express" | "fastAPI" | "flask" | "gin" | "next";

export interface RouteSurface {
  framework: RouteFramework;
  method: string;
  path: string;
  handler: string | null;
  line: number;
}

export function routeSurfaceKey(route: RouteSurface): string {
  return [route.framework, route.method, route.path, route.handler ?? "\u0000", route.line].join(
    "\u0001",
  );
}

export class RouteDetector {
  detect(path: string, contents: string): RouteSurface[] {
    const routes: RouteSurface[] = [];

    routes.push(...this.detectExpressRoutes(contents));
    if (
      contents.includes("FastAPI") ||
      contents.includes("APIRouter") ||
      contents.includes("from fastapi")
    ) {
      routes.push(...this.detectPythonDecoratorRoutes(contents, "fastAPI"));
    }
    if (
      contents.includes("Flask") ||
      contents.includes("Blueprint") ||
      contents.includes("from flask")
    ) {
      routes.push(...this.detectPythonDecoratorRoutes(contents, "flask"));
    }
    routes.push(...this.detectGinRoutes(contents));
    routes.push(...this.detectNextRoutes(path, contents));

    const seen = new Set<string>();
    const uniqueRoutes = routes.filter((route) => {
      const key = routeSurfaceKey(route);
      if (seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    });

    return uniqueRoutes.sort((lhs, rhs) =>
      lhs.line === rhs.line
        ? lhs.path < rhs.path
          ? -1
          : lhs.path > rhs.path
            ? 1
            : 0
        : lhs.line - rhs.line,
    );
  }

  private detectExpressRoutes(contents: string): RouteSurface[] {
    return this.routeMatches(
      contents,
      String.raw`\b(?:app|router)\.(get|post|put|patch|delete|head|options|all)\s*\(\s*["']([^"']+)["']\s*,\s*([A-Za-z_$][A-Za-z0-9_$]*)?`,
      "express",
    );
  }

  private detectPythonDecoratorRoutes(
    contents: string,
    framework: RouteFramework,
  ): RouteSurface[] {
    const receiver = framework === "fastAPI" ? String.raw`(?:app|router)` : String.raw`(?:app|bp|blueprint)`;
    return this.routeMatches(
      contents,
      String.raw`@${receiver}\.(get|post|put|patch|delete|route)\s*\(\s*["']([^"']+)["']`,
      framework,
    );
  }

  private detectGinRoutes(contents: string): RouteSurface[] {
    return this.routeMatches(
      contents,
      String.raw`\b[A-Za-z_][A-Za-z0-9_]*\.(GET|POST|PUT|PATCH|DELETE|Any)\s*\(\s*["']([^"']+)["']\s*,\s*([A-Za-z_][A-Za-z0-9_]*)?`,
      "gin",
    );
  }

  private detectNextRoutes(path: string, contents: string): RouteSurface[] {
    if (
      !path.endsWith("route.ts") &&
      !path.endsWith("route.js") &&
      !path.endsWith("route.tsx") &&
      !path.endsWith("route.jsx")
    ) {
      return [];
    }

    const pattern = String.raw`export\s+(?:async\s+)?function\s+(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\b`;
    let regex: RegExp;
    try {
      regex = new RegExp(pattern, "g");
    } catch {
      return [];
    }

    const routePath = this.nextRoutePath(path);
    const routes: RouteSurface[] = [];
    for (const match of contents.matchAll(regex)) {
      const method = match[1];
      if (method === undefined) {
        continue;
      }
      routes.push({
        framework: "next",
        method: method.toUpperCase(),
        path: routePath,
        handler: method,
        line: lineNumberAtOffset(match.index ?? 0, contents),
      });
    }

    return routes;
  }

  private routeMatches(
    contents: string,
    pattern: string,
    framework: RouteFramework,
  ): RouteSurface[] {
    let regex: RegExp;
    try {
      regex = new RegExp(pattern, "g");
    } catch {
      return [];
    }

    const routes: RouteSurface[] = [];
    for (const match of contents.matchAll(regex)) {
      const groups: string[] = [];
      for (let index = 1; index < match.length; index += 1) {
        const group = match[index];
        if (group !== undefined) {
          groups.push(group);
        }
      }

      if (groups.length < 2) {
        continue;
      }

      routes.push({
        framework,
        method: groups[0].toUpperCase(),
        path: groups[1],
        handler: groups.length > 2 ? groups[2] : null,
        line: lineNumberAtOffset(match.index ?? 0, contents),
      });
    }

    return routes;
  }

  private nextRoutePath(path: string): string {
    let components = path.split("/").filter((component) => component.length > 0);
    const appIndex = components.indexOf("app");
    if (appIndex !== -1) {
      components = components.slice(appIndex + 1);
    }

    if (components.length > 0 && components[components.length - 1].startsWith("route.")) {
      components = components.slice(0, components.length - 1);
    }

    const visibleComponents = components
      .filter((component) => !component.startsWith("(") && !component.startsWith("@"))
      .map((component) =>
        component.startsWith("[") && component.endsWith("]")
          ? `:${component.slice(1, component.length - 1)}`
          : component,
      );

    return `/${visibleComponents.join("/")}`;
  }
}
