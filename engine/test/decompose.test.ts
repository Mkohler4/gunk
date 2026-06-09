import { describe, expect, it } from "vitest";

import type { CodeGraph, Module } from "../src/models.js";
import { fileNode } from "../src/models.js";
import type { CapabilityFingerprint } from "../src/analyze/capabilityFingerprint.js";
import { ModuleQualityGate } from "../src/decompose/qualityGate.js";
import type { SelfContainmentResult } from "../src/decompose/selfContainment.js";
import { CapabilityExpander } from "../src/decompose/expander.js";
import { survey } from "../src/decompose/survey.js";
import { CapabilityRefiner } from "../src/decompose/refiner.js";
import type { LLMClient, LLMResponse } from "../src/llm/client.js";

function module(partial: Partial<Module> & Pick<Module, "name" | "files">): Module {
  return {
    name: partial.name,
    purpose: partial.purpose ?? "purpose",
    tags: partial.tags ?? [],
    files: partial.files,
    language: partial.language ?? "typeScript",
    confidence: partial.confidence ?? 0.9,
    ownedFiles: partial.ownedFiles ?? partial.files,
    sharedDeps: partial.sharedDeps ?? [],
    surface: partial.surface ?? [{ path: partial.files[0], symbol: "main" }],
    anchors: partial.anchors ?? ["route:/x"],
  };
}

class FakeClient implements LLMClient {
  readonly provider = "OpenAI" as const;
  constructor(private readonly json: unknown) {}
  async complete(): Promise<LLMResponse> {
    return { json: this.json, usage: { inputTokens: 1, outputTokens: 2 } };
  }
}

function selfContainment(partial: Partial<SelfContainmentResult> = {}): SelfContainmentResult {
  return {
    moduleName: "module",
    imports: "pass",
    entrypoint: "pass",
    danglingImports: [],
    missingEntrypoints: [],
    ...partial,
  };
}

describe("ModuleQualityGate", () => {
  const gate = new ModuleQualityGate();

  it("accepts a cohesive multi-file capability", () => {
    const graph: CodeGraph = {
      nodes: [fileNode("a.ts"), fileNode("b.ts")],
      edges: [{ from: fileNode("a.ts"), to: fileNode("b.ts"), kind: "import" }],
    };
    const evaluation = gate.evaluateModule(
      module({ name: "auth", files: ["a.ts", "b.ts"] }),
      [],
      graph,
      { "a.ts": "export function login() {}", "b.ts": "export const x = 1" },
    );
    expect(evaluation.decision).toBe("accepted");
  });

  it("rejects a type-only module", () => {
    const evaluation = gate.evaluateModule(
      module({ name: "types", files: ["types.ts"] }),
      [],
      null,
      { "types.ts": "export interface A { x: number }" },
    );
    expect(evaluation.decision).toBe("rejected");
    expect(evaluation.reasons).toContain("typeOnly");
  });

  it("accepts a Dart capability with a public entrypoint and dep hint", () => {
    const fingerprints: CapabilityFingerprint[] = [
      {
        filePath: "lib/features/auth/auth_repository.dart",
        importedDependencies: ["firebase_auth"],
        routes: [],
        publicExports: [{ name: "AuthRepository", kind: "class", line: 5 }],
        envVars: [],
        configKeys: [],
        namingTokens: ["auth", "repository"],
        capabilityHints: [{ library: "firebase_auth", labels: ["auth", "firebase"] }],
      },
    ];
    const evaluation = gate.evaluateModule(
      module({
        name: "Flutter auth",
        files: ["lib/features/auth/auth_repository.dart"],
        language: "Dart",
        surface: [],
        anchors: [],
      }),
      fingerprints,
      null,
      {
        "lib/features/auth/auth_repository.dart":
          "class AuthRepository { Future<AuthState> signInWithEmail(String email, String password) async => AuthState('', email); }",
      },
    );

    expect(evaluation.decision).toBe("accepted");
    expect(evaluation.reasons).toEqual([]);
  });

  it("downgrades a non-self-contained module", () => {
    const evaluation = gate.evaluateModule(
      module({ name: "auth", files: ["src/auth.ts"], surface: [{ path: "src/auth.ts", symbol: "login" }] }),
      [],
      null,
      { "src/auth.ts": "export function login() { return 1 }" },
      selfContainment({
        imports: "fail",
        danglingImports: [
          {
            fromPath: "src/auth.ts",
            moduleSpecifier: "./session",
            resolvedTarget: "src/session.ts",
            reason: "internalImportOutsideModule",
          },
        ],
      }),
    );

    expect(evaluation.decision).toBe("needsApproval");
    expect(evaluation.reasons).toEqual(["failsSelfContainment"]);
  });

  it("rejects a claimed surface when verification proves the entrypoint is not real", () => {
    const evaluation = gate.evaluateModule(
      module({ name: "auth", files: ["src/auth.ts"], surface: [{ path: "src/auth.ts", symbol: "login" }] }),
      [],
      null,
      { "src/auth.ts": "function login() { return 1 }" },
      selfContainment({
        entrypoint: "fail",
        missingEntrypoints: [
          {
            path: "src/auth.ts",
            symbol: "login",
            reason: "notExported",
          },
        ],
      }),
    );

    expect(evaluation.decision).toBe("rejected");
    expect(evaluation.reasons).toEqual(["failsSelfContainment", "missingSurface"]);
  });

  it("allows a self-contained low-cohesion mobile module to survive", () => {
    const graph: CodeGraph = {
      nodes: [
        fileNode("lib/features/payments/payment_sheet.dart"),
        fileNode("lib/features/payments/payment_controller.dart"),
        fileNode("lib/platform/native_payments.dart"),
      ],
      edges: [
        {
          from: fileNode("lib/features/payments/payment_sheet.dart"),
          to: fileNode("lib/platform/native_payments.dart"),
          kind: "reference",
        },
        {
          from: fileNode("lib/features/payments/payment_controller.dart"),
          to: fileNode("lib/platform/native_payments.dart"),
          kind: "reference",
        },
      ],
    };
    const evaluation = gate.evaluateModule(
      module({
        name: "Mobile payments",
        files: ["lib/features/payments/payment_sheet.dart", "lib/features/payments/payment_controller.dart"],
        language: "Dart",
        surface: [{ path: "lib/features/payments/payment_sheet.dart", symbol: "PaymentSheet" }],
        anchors: [],
      }),
      [],
      graph,
      {
        "lib/features/payments/payment_sheet.dart": "export class PaymentSheet {}",
        "lib/features/payments/payment_controller.dart": "class PaymentController {}",
      },
      selfContainment({ moduleName: "Mobile payments" }),
    );

    expect(evaluation.cohesionScore).toBe(0);
    expect(evaluation.decision).toBe("accepted");
    expect(evaluation.reasons).toEqual([]);
  });

  it("still rejects self-contained types and utility traps with public-looking surface", () => {
    const evaluations = gate.evaluate(
      [
        module({
          name: "types",
          files: ["src/types.ts"],
          surface: [{ path: "src/types.ts", symbol: "SharedEnvelope" }],
          anchors: ["public-api:SharedEnvelope"],
        }),
        module({
          name: "date util",
          files: ["src/utils/date.ts"],
          surface: [{ path: "src/utils/date.ts", symbol: "compactDate" }],
          anchors: ["public-api:compactDate"],
        }),
      ],
      [
        {
          filePath: "src/types.ts",
          importedDependencies: [],
          routes: [],
          publicExports: [{ name: "SharedEnvelope", kind: "interface", line: 1 }],
          envVars: [],
          configKeys: [],
          namingTokens: ["types", "shared", "envelope"],
          capabilityHints: [],
        },
      ],
      null,
      {
        "src/types.ts": "export interface SharedEnvelope { id: string }",
        "src/utils/date.ts": "export function compactDate(value: Date) { return value.toISOString(); }",
      },
      [selfContainment({ moduleName: "types" }), selfContainment({ moduleName: "date util" })],
    );

    const types = evaluations.find((evaluation) => evaluation.module.name === "types")!;
    const utility = evaluations.find((evaluation) => evaluation.module.name === "date util")!;

    expect(types.decision).toBe("rejected");
    expect(types.reasons).toContain("typeOnly");
    expect(utility.decision).toBe("rejected");
    expect(utility.reasons).toContain("utilityOnly");
  });

  it("flags low confidence as needsApproval", () => {
    const evaluation = gate.evaluateModule(
      module({ name: "auth", files: ["a.ts"], confidence: 0.5, surface: [{ path: "a.ts", symbol: "login" }] }),
      [],
      null,
      { "a.ts": "export function login() { return 1 }" },
    );
    expect(evaluation.decision).toBe("needsApproval");
    expect(evaluation.reasons).toEqual(["belowConfidenceThreshold"]);
  });

  it("rejects the weaker of two duplicate-overlapping modules", () => {
    const evaluations = gate.evaluate(
      [
        module({ name: "strong", files: ["a.ts", "b.ts"], confidence: 0.95 }),
        module({ name: "weak", files: ["a.ts", "b.ts"], confidence: 0.8 }),
      ],
      [],
      null,
      { "a.ts": "export function f(){return 1}", "b.ts": "export function g(){return 2}" },
    );
    const weak = evaluations.find((e) => e.module.name === "weak")!;
    expect(weak.decision).toBe("rejected");
    expect(weak.reasons).toContain("duplicateOverlap");
  });
});

describe("CapabilityExpander", () => {
  it("expands a seed file through outbound import edges", () => {
    const graph: CodeGraph = {
      nodes: [fileNode("login.ts"), fileNode("session.ts"), fileNode("util.ts")],
      edges: [
        { from: fileNode("login.ts"), to: fileNode("session.ts"), kind: "import" },
        { from: fileNode("session.ts"), to: fileNode("util.ts"), kind: "import" },
      ],
    };
    const [expansion] = new CapabilityExpander().expand(
      [
        {
          name: "auth",
          rationale: "login",
          anchors: ["route:/login"],
          seedFiles: ["login.ts"],
          expectedCollaborators: [],
          granularity: "feature",
          priority: "normal",
        },
      ],
      graph,
    );
    expect(expansion.closureFiles).toEqual(["login.ts", "session.ts", "util.ts"]);
    expect(expansion.edgeEvidence.length).toBeGreaterThan(0);
  });
});

describe("survey", () => {
  it("parses and filters hypotheses against known files", async () => {
    const client = new FakeClient({
      hypotheses: [
        {
          name: "Auth",
          rationale: "Login flow",
          anchors: ["route:/login"],
          seedFiles: ["login.ts"],
          expectedCollaborators: ["session.ts"],
          granularity: "feature",
        },
        {
          name: "Ghost",
          rationale: "missing files",
          anchors: [],
          seedFiles: ["does-not-exist.ts"],
          expectedCollaborators: [],
          granularity: "feature",
        },
      ],
    });
    const result = await survey(client, {
      model: "gpt",
      sourceName: "demo",
      repoMap: "map",
      knownFiles: ["login.ts", "session.ts"],
    });
    expect(result.map((h) => h.name)).toEqual(["Auth"]);
    expect(result[0].priority).toBe("normal");
  });

  it("merges chunked survey hypotheses deterministically", async () => {
    const client = new FakeClient({
      hypotheses: [
        {
          name: "Auth",
          rationale: "Login flow",
          anchors: ["session"],
          seedFiles: ["session.ts"],
          expectedCollaborators: [],
          granularity: "feature",
        },
      ],
    });
    let calls = 0;
    client.complete = async () => {
      calls += 1;
      return {
        json:
          calls === 1
            ? {
                hypotheses: [
                  {
                    name: "Auth",
                    rationale: "Login flow",
                    anchors: ["route:/login"],
                    seedFiles: ["login.ts"],
                    expectedCollaborators: [],
                    granularity: "feature",
                  },
                ],
              }
            : {
                hypotheses: [
                  {
                    name: "Auth",
                    rationale: "Login flow",
                    anchors: ["session"],
                    seedFiles: ["session.ts"],
                    expectedCollaborators: [],
                    granularity: "feature",
                  },
                ],
              },
        usage: { inputTokens: 1, outputTokens: 1 },
      };
    };

    const result = await survey(client, {
      model: "gpt",
      sourceName: "demo",
      repoMap: "truncated",
      repoMapChunks: ["chunk-a", "chunk-b"],
      knownFiles: ["login.ts", "session.ts"],
    });

    expect(calls).toBe(2);
    expect(result).toHaveLength(1);
    expect(result[0].anchors).toEqual(["route:/login", "session"]);
    expect(result[0].seedFiles).toEqual(["login.ts", "session.ts"]);
  });
});

describe("CapabilityRefiner", () => {
  it("builds a module and clamps confidence; reports rejection reasons", async () => {
    const expansion = {
      hypothesis: {
        name: "Auth",
        rationale: "login",
        anchors: ["route:/login"],
        seedFiles: ["login.ts"],
        expectedCollaborators: [],
        granularity: "feature",
        priority: "normal" as const,
      },
      closureFiles: ["login.ts", "session.ts"],
      ownedFiles: ["login.ts"],
      sharedDependencyFiles: ["session.ts"],
      excludedFiles: [],
      edgeEvidence: [],
    };
    const client = new FakeClient({
      module: {
        name: "Login",
        purpose: "Handles login",
        tags: ["auth"],
        language: "typeScript",
        ownedFiles: ["login.ts"],
        sharedDependencies: ["session.ts"],
        entrypoints: [{ path: "login.ts", symbol: "login" }],
        anchors: ["route:/login"],
        confidence: 1.5,
      },
      qualityGateHints: { externalFacingCapability: true, multiFileCohesion: true, anchorPresent: true, rightGranularity: true },
      reject: null,
    });
    const refinements: { capability: string; accepted: boolean; rejectReason: string | null }[] = [];
    const refiner = new CapabilityRefiner({
      onRefinement: (r) => refinements.push({ capability: r.capability, accepted: r.accepted, rejectReason: r.rejectReason }),
    });
    const modules = await refiner.refine(client, {
      model: "gpt",
      sourceName: "demo",
      expansions: [expansion],
      contentsByPath: { "login.ts": "x", "session.ts": "y" },
      allowedTags: ["auth", "payments"],
    });
    expect(modules).toHaveLength(1);
    expect(modules[0].confidence).toBe(1);
    expect(modules[0].files).toEqual(["login.ts", "session.ts"]);
    expect(modules[0].tags).toEqual(["auth"]);
    expect(refinements[0].accepted).toBe(true);
  });

  it("returns no module and surfaces a reject reason", async () => {
    const expansion = {
      hypothesis: {
        name: "Types",
        rationale: "type only",
        anchors: [],
        seedFiles: ["types.ts"],
        expectedCollaborators: [],
        granularity: "file",
        priority: "low" as const,
      },
      closureFiles: ["types.ts"],
      ownedFiles: ["types.ts"],
      sharedDependencyFiles: [],
      excludedFiles: [],
      edgeEvidence: [],
    };
    const client = new FakeClient({
      module: null,
      qualityGateHints: { externalFacingCapability: false, multiFileCohesion: false, anchorPresent: false, rightGranularity: false },
      reject: { reason: "type-only file, not a capability" },
    });
    const refinements: string[] = [];
    const refiner = new CapabilityRefiner({
      onRefinement: (r) => {
        if (r.rejectReason) refinements.push(r.rejectReason);
      },
    });
    const modules = await refiner.refine(client, {
      model: "gpt",
      sourceName: "demo",
      expansions: [expansion],
      contentsByPath: { "types.ts": "export interface A {}" },
      allowedTags: ["auth"],
    });
    expect(modules).toHaveLength(0);
    expect(refinements).toEqual(["type-only file, not a capability"]);
  });
});
