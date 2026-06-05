import { describe, expect, it } from "vitest";

import {
  type ExportRef,
  fileNode,
  type FileSymbols,
  type ImportRef,
  languageKindForPath,
  type Symbol,
} from "../src/models.js";
import {
  type CodeGraph,
  CodeGraphBuilder,
  inboundEdges,
  symbolNode,
  transitiveClosure,
} from "../src/analyze/codeGraph.js";
import { GraphClustering } from "../src/analyze/graphClustering.js";
import { ImportResolver } from "../src/analyze/importResolver.js";

function fileSymbols(
  filePath: string,
  options: { symbols?: Symbol[]; imports?: ImportRef[]; exports?: ExportRef[] } = {},
): FileSymbols {
  return {
    path: filePath,
    language: languageKindForPath(filePath),
    symbols: options.symbols ?? [],
    imports: options.imports ?? [],
    exports: options.exports ?? [],
  };
}

function buildGraph(
  files: FileSymbols[],
  contentsByPath: Record<string, string> = {},
): CodeGraph {
  const resolver = new ImportResolver({ sourceFiles: new Set(files.map((file) => file.path)) });
  return new CodeGraphBuilder(resolver).build(files, contentsByPath);
}

function hasEdge(graph: CodeGraph, fromId: string, toId: string, kind: string): boolean {
  return graph.edges.some(
    (edge) => edge.from.id === fromId && edge.to.id === toId && edge.kind === kind,
  );
}

describe("ImportResolver", () => {
  it("resolves relative and alias imports", () => {
    const resolver = new ImportResolver({
      sourceFiles: new Set([
        "src/auth/login.ts",
        "src/auth/types.ts",
        "src/config/env.ts",
        "src/shared/oauth.ts",
      ]),
      tsconfigPaths: { "@/*": ["src/*"] },
    });

    expect(resolver.resolve("./types", "src/auth/login.ts")).toBe("src/auth/types.ts");
    expect(resolver.resolve("@/shared/oauth", "src/auth/login.ts")).toBe("src/shared/oauth.ts");
    expect(resolver.resolve("src/config/env", "src/auth/login.ts")).toBe("src/config/env.ts");
    expect(resolver.resolve("react", "src/auth/login.ts")).toBeNull();
  });
});

describe("GraphClustering", () => {
  it("separates connected components by feature", () => {
    const files = [
      fileSymbols("src/auth/route.ts", {
        imports: [{ moduleSpecifier: "./service", resolvedTarget: null, line: 1 }],
      }),
      fileSymbols("src/auth/service.ts"),
      fileSymbols("src/billing/route.ts", {
        imports: [{ moduleSpecifier: "./service", resolvedTarget: null, line: 1 }],
      }),
      fileSymbols("src/billing/service.ts"),
    ];
    const graph = buildGraph(files);
    const clusters = new GraphClustering(graph).connectedComponents();

    const clusterSets = clusters.map((cluster) => [...cluster.filePaths].sort());
    expect(clusterSets).toContainEqual(["src/auth/route.ts", "src/auth/service.ts"]);
    expect(clusterSets).toContainEqual(["src/billing/route.ts", "src/billing/service.ts"]);
    expect(clusters.map((cluster) => cluster.cohesionScore)).toEqual([1, 1]);
  });

  it("identifies shared utility as a high fan-in bridge", () => {
    const files = [
      fileSymbols("src/auth/service.ts", {
        imports: [{ moduleSpecifier: "../shared/oauth", resolvedTarget: null, line: 1 }],
      }),
      fileSymbols("src/billing/service.ts", {
        imports: [{ moduleSpecifier: "../shared/oauth", resolvedTarget: null, line: 1 }],
      }),
      fileSymbols("src/shared/oauth.ts"),
    ];
    const graph = buildGraph(files);
    const bridgeFiles = new GraphClustering(graph).highFanInBridgeFiles(2);

    expect(bridgeFiles.map((node) => node.id)).toEqual([fileNode("src/shared/oauth.ts").id]);
    expect(
      inboundEdges(graph, fileNode("src/shared/oauth.ts"), new Set(["import"])).length,
    ).toBe(2);
  });
});

describe("CodeGraphBuilder", () => {
  it("builds closure and symbol edges", () => {
    const files = [
      fileSymbols("src/auth/controller.ts", {
        imports: [{ moduleSpecifier: "./service", resolvedTarget: null, line: 1 }],
      }),
      fileSymbols("src/auth/service.ts", {
        symbols: [{ name: "createSession", kind: "function", line: 1 }],
        exports: [{ name: "createSession", kind: "function", line: 1 }],
      }),
      fileSymbols("src/auth/base.ts", {
        symbols: [{ name: "BaseHandler", kind: "class", line: 1 }],
        exports: [{ name: "BaseHandler", kind: "class", line: 1 }],
      }),
    ];
    const graph = buildGraph(files, {
      "src/auth/controller.ts": `import { createSession } from "./service";
class LoginHandler extends BaseHandler {
  run() { createSession(); }
}`,
    });

    const controller = fileNode("src/auth/controller.ts");
    expect(hasEdge(graph, controller.id, fileNode("src/auth/service.ts").id, "import")).toBe(true);
    expect(
      hasEdge(
        graph,
        controller.id,
        symbolNode({ name: "createSession", kind: "function", line: 1 }, "src/auth/service.ts").id,
        "call",
      ),
    ).toBe(true);
    expect(
      hasEdge(
        graph,
        controller.id,
        symbolNode({ name: "BaseHandler", kind: "class", line: 1 }, "src/auth/base.ts").id,
        "inherit",
      ),
    ).toBe(true);

    const closure = transitiveClosure(graph, controller, 1, new Set(["import"]));
    expect(closure.map((node) => node.id)).toEqual([fileNode("src/auth/service.ts").id]);
  });
});
