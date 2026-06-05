import { describe, expect, it } from "vitest";

import type { CodeGraph, Module } from "../src/models.js";
import { fileNode } from "../src/models.js";
import { ModuleQualityGate } from "../src/decompose/qualityGate.js";
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
