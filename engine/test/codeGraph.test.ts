import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

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
import { dartPackageNameFromPubspec, ImportResolver } from "../src/analyze/importResolver.js";
import { scanFolder } from "../src/ingest/scanner.js";
import { createTreeSitterSymbolExtractor } from "../src/analyze/symbolExtractor.js";

const fixturesDir = join(dirname(fileURLToPath(import.meta.url)), "fixtures");

function fileSymbols(
  filePath: string,
  options: { symbols?: Symbol[]; imports?: ImportRef[]; exports?: ExportRef[] } = {},
): FileSymbols {
  return {
    path: filePath,
    language: languageKindForPath(filePath),
    viaFallback: false,
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

  it("resolves Dart relative and package-self imports", () => {
    const resolver = new ImportResolver({
      sourceFiles: new Set([
        "lib/main.dart",
        "lib/types.dart",
        "lib/features/auth/auth_controller.dart",
        "lib/features/auth/auth_repository.dart",
      ]),
      dartPackageName: "gunk_flutter_fixture",
    });

    expect(resolver.resolve("features/auth/auth_controller.dart", "lib/main.dart")).toBe(
      "lib/features/auth/auth_controller.dart",
    );
    expect(resolver.resolve("auth_repository.dart", "lib/features/auth/auth_controller.dart")).toBe(
      "lib/features/auth/auth_repository.dart",
    );
    expect(
      resolver.resolve(
        "package:gunk_flutter_fixture/types.dart",
        "lib/features/auth/auth_controller.dart",
      ),
    ).toBe("lib/types.dart");
    expect(resolver.resolve("lib/types.dart", "lib/main.dart")).toBe("lib/types.dart");
  });

  it("keeps third-party Dart package imports external", () => {
    const resolver = new ImportResolver({
      sourceFiles: new Set(["lib/features/auth/auth_repository.dart"]),
      dartPackageName: "gunk_flutter_fixture",
    });

    expect(
      resolver.resolve(
        "package:firebase_auth/firebase_auth.dart",
        "lib/features/auth/auth_repository.dart",
      ),
    ).toBeNull();
    expect(resolver.resolve("dart:async", "lib/features/auth/auth_repository.dart")).toBeNull();
  });

  it("resolves Kotlin/Java package imports", () => {
    const resolver = new ImportResolver({
      sourceFiles: new Set([
        "app/src/main/java/com/gunk/fixture/features/payments/PaymentsRepository.kt",
        "app/src/main/java/com/gunk/fixture/features/payments/CheckoutSession.kt",
        "src/main/java/com/gunk/orders/OrderService.java",
        "src/main/java/com/gunk/orders/OrderRepository.java",
      ]),
    });

    expect(
      resolver.resolve(
        "com.gunk.fixture.features.payments.PaymentsRepository",
        "app/src/main/java/com/gunk/fixture/features/payments/CheckoutViewModel.kt",
      ),
    ).toBe("app/src/main/java/com/gunk/fixture/features/payments/PaymentsRepository.kt");
    expect(
      resolver.resolve("com.gunk.orders.OrderRepository", "src/main/java/com/gunk/orders/OrderService.java"),
    ).toBe("src/main/java/com/gunk/orders/OrderRepository.java");
    expect(
      resolver.resolve(
        "org.springframework.web.bind.annotation.RestController",
        "src/main/java/com/gunk/orders/OrderController.java",
      ),
    ).toBeNull();
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

  it("flutter-app main.dart links to its controllers/services", async () => {
    const fixturePath = join(fixturesDir, "flutter-app");
    const scannedFiles = scanFolder(fixturePath);
    const contentsByPath: Record<string, string> = {};
    for (const file of scannedFiles) {
      contentsByPath[file.relpath] = readFileSync(file.absPath, "utf8");
    }

    const extractor = await createTreeSitterSymbolExtractor();
    const files = scannedFiles.map((file) =>
      extractor.extract({ path: file.relpath, contents: contentsByPath[file.relpath] ?? "" }),
    );
    const resolver = new ImportResolver({
      sourceFiles: new Set(scannedFiles.map((file) => file.relpath)),
      dartPackageName: dartPackageNameFromPubspec(contentsByPath["pubspec.yaml"] ?? ""),
    });
    const graph = new CodeGraphBuilder(resolver).build(files, contentsByPath);
    const main = fileNode("lib/main.dart");

    expect(
      hasEdge(
        graph,
        main.id,
        fileNode("lib/features/auth/auth_controller.dart").id,
        "import",
      ),
    ).toBe(true);
    expect(
      hasEdge(
        graph,
        main.id,
        fileNode("lib/features/profile/profile_controller.dart").id,
        "import",
      ),
    ).toBe(true);
    expect(graph.externalDependencies["lib/main.dart"]).toBeUndefined();

    expect(
      transitiveClosure(graph, main, 2, new Set(["import"]))
        .map((node) => node.filePath)
        .sort(),
    ).toEqual([
      "lib/features/auth/auth_controller.dart",
      "lib/features/auth/auth_repository.dart",
      "lib/features/auth/auth_state.dart",
      "lib/features/profile/profile_controller.dart",
      "lib/features/profile/profile_model.dart",
      "lib/features/profile/user_api.dart",
    ]);
  });
});
