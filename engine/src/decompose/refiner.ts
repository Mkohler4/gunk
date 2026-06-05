// Pass 2: capability refinement. Ported from
// app/Sources/GunkApp/Decompose/CapabilityRefiner.swift.
//
// Unlike the Swift original, reject reasons are surfaced to the caller via the
// onRefinement callback so they land in the run trace (the Swift code dropped
// them).

import type { CapabilityExpansion, Module, ModuleSurface } from "../models.js";
import { clamp, uniqued } from "../models.js";
import type { JsonSchema, LLMClient, LLMRequest } from "../llm/client.js";

export interface RefinerOptions {
  maxContextCharacters?: number;
  maxFileCharacters?: number;
  maxOutputTokens?: number;
  now?: () => number;
  recordRun?: (record: { inputTokens: number | null; outputTokens: number | null; startedAt: number; finishedAt: number }) => void;
  onRefinement?: (record: { capability: string; accepted: boolean; rejectReason: string | null; module: Module | null }) => void;
}

function asObject(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function trimmedNonEmpty(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function nonEmptyStrings(value: unknown): string[] | null {
  if (!Array.isArray(value)) return null;
  return value.filter((v): v is string => typeof v === "string").map((v) => v.trim()).filter((v) => v.length > 0);
}

export class CapabilityRefiner {
  private readonly maxContextCharacters: number;
  private readonly maxFileCharacters: number;
  private readonly maxOutputTokens: number;
  private readonly now: () => number;

  constructor(private readonly options: RefinerOptions = {}) {
    this.maxContextCharacters = options.maxContextCharacters ?? 32_000;
    this.maxFileCharacters = options.maxFileCharacters ?? 8_000;
    this.maxOutputTokens = options.maxOutputTokens ?? 4_096;
    this.now = options.now ?? Date.now;
  }

  async refine(
    client: LLMClient,
    args: { model: string; sourceName: string; expansions: CapabilityExpansion[]; contentsByPath: Record<string, string>; allowedTags: string[] },
  ): Promise<Module[]> {
    const allowedTagsSorted = [...args.allowedTags].sort((a, b) => a.localeCompare(b));
    const allowedTagSet = new Set(args.allowedTags);
    const modules: Module[] = [];

    for (const expansion of args.expansions) {
      const startedAt = this.now();
      const response = await client.complete(
        this.request(args.model, args.sourceName, expansion, args.contentsByPath, allowedTagsSorted),
      );
      const finishedAt = this.now();
      this.options.recordRun?.({
        inputTokens: response.usage.inputTokens,
        outputTokens: response.usage.outputTokens,
        startedAt,
        finishedAt,
      });

      const parsed = this.parseModule(response.json, expansion, allowedTagSet);
      this.options.onRefinement?.({
        capability: expansion.hypothesis.name,
        accepted: parsed.module !== null,
        rejectReason: parsed.rejectReason,
        module: parsed.module,
      });
      if (parsed.module) modules.push(parsed.module);
    }

    return modules;
  }

  private request(
    model: string,
    sourceName: string,
    expansion: CapabilityExpansion,
    contentsByPath: Record<string, string>,
    allowedTags: string[],
  ): LLMRequest {
    return {
      model,
      messages: [
        {
          role: "system",
          content: `You are Pass 2 of gunk's capability-centric decomposition pipeline.
Deep-read one expanded capability closure and return structured JSON only.

Real-module rubric:
- Keep only files needed for the reusable capability.
- Separate owned files from shared dependencies.
- Use only allowed tags and only files present in the closure.
- Return module null with a reject reason if this is not a real module.`,
        },
        {
          role: "user",
          content: `Source: ${sourceName}
Allowed tags: ${allowedTags.join(", ")}

Candidate:
name: ${expansion.hypothesis.name}
rationale: ${expansion.hypothesis.rationale}
anchors: ${expansion.hypothesis.anchors.join(", ")}
expected collaborators: ${expansion.hypothesis.expectedCollaborators.join(", ")}

Closure:
owned candidates: ${expansion.ownedFiles.join(", ")}
shared dependency candidates: ${expansion.sharedDependencyFiles.join(", ")}
excluded files: ${expansion.excludedFiles.map((f) => `${f.path} (${f.reason})`).join(", ")}

Edge evidence:
${this.edgeEvidenceContext(expansion)}

Closure file contents:
${this.fileContentsContext(expansion, contentsByPath)}`,
        },
      ],
      jsonSchemaName: "CapabilityRefinement",
      jsonSchema: refinerOutputSchema(allowedTags),
      maxTokens: this.maxOutputTokens,
      temperature: 0,
    };
  }

  private edgeEvidenceContext(expansion: CapabilityExpansion): string {
    if (expansion.edgeEvidence.length === 0) return "- none";
    return expansion.edgeEvidence
      .map((edge) => `- ${edge.fromPath} --${edge.kind}--> ${edge.toPath} depth=${edge.depth}`)
      .join("\n");
  }

  private fileContentsContext(expansion: CapabilityExpansion, contentsByPath: Record<string, string>): string {
    let remainingBudget = this.maxContextCharacters;
    const blocks: string[] = [];
    for (const path of [...expansion.closureFiles].sort((a, b) => a.localeCompare(b))) {
      if (remainingBudget <= 0) {
        blocks.push(`### ${path}\n[omitted: context budget exhausted]`);
        continue;
      }
      const contents = contentsByPath[path] ?? "[contents unavailable]";
      const fileBudget = Math.min(this.maxFileCharacters, remainingBudget);
      const clipped = contents.slice(0, fileBudget);
      const suffix = contents.length > clipped.length ? "\n[truncated]" : "";
      const block = `### ${path}\n${clipped}${suffix}`;
      blocks.push(block);
      remainingBudget -= block.length;
    }
    return blocks.join("\n\n");
  }

  private parseModule(
    value: unknown,
    expansion: CapabilityExpansion,
    allowedTags: Set<string>,
  ): { module: Module | null; rejectReason: string | null } {
    const root = asObject(value);
    if (!root || !("module" in root) || asObject(root.qualityGateHints) === null || !("reject" in root)) {
      throw new Error("CapabilityRefiner: invalid response");
    }

    const rejectObject = asObject(root.reject);
    const rejectReason = rejectObject ? trimmedNonEmpty(rejectObject.reason) : null;

    if (root.module === null) {
      return { module: null, rejectReason };
    }

    const object = asObject(root.module);
    const name = trimmedNonEmpty(object?.name);
    const purpose = trimmedNonEmpty(object?.purpose);
    const ownedFiles = nonEmptyStrings(object?.ownedFiles);
    const sharedDeps = nonEmptyStrings(object?.sharedDependencies);
    const language = trimmedNonEmpty(object?.language);
    const confidence = typeof object?.confidence === "number" ? object.confidence : null;
    if (!object || !name || !purpose || !ownedFiles || !sharedDeps || !language || confidence === null) {
      throw new Error("CapabilityRefiner: invalid response");
    }

    const closureFiles = new Set(expansion.closureFiles);
    const uniqueSharedDeps = uniqued(sharedDeps).filter((f) => closureFiles.has(f));
    const sharedSet = new Set(uniqueSharedDeps);
    const uniqueOwnedFiles = uniqued(ownedFiles).filter((f) => closureFiles.has(f) && !sharedSet.has(f));
    const finalFiles = uniqued([...uniqueOwnedFiles, ...uniqueSharedDeps]);
    if (finalFiles.length === 0) {
      return { module: null, rejectReason };
    }

    const tags = uniqued(
      (nonEmptyStrings(object.tags) ?? []).filter((t) => allowedTags.has(t)),
    );
    const parsedAnchors = nonEmptyStrings(object.anchors);
    const anchors = parsedAnchors && parsedAnchors.length > 0 ? uniqued(parsedAnchors) : expansion.hypothesis.anchors;
    const surface = this.parseSurface(object.entrypoints, new Set(finalFiles));

    const module: Module = {
      name,
      purpose,
      tags,
      files: finalFiles,
      language,
      confidence: clamp(confidence, 0, 1),
      ownedFiles: uniqueOwnedFiles,
      sharedDeps: uniqueSharedDeps,
      surface,
      anchors,
    };
    return { module, rejectReason: null };
  }

  private parseSurface(value: unknown, allowedFiles: Set<string>): ModuleSurface[] {
    if (!Array.isArray(value)) return [];
    const result: ModuleSurface[] = [];
    const seen = new Set<string>();
    for (const entry of value) {
      const object = asObject(entry);
      const path = trimmedNonEmpty(object?.path);
      if (!path || !allowedFiles.has(path)) continue;
      const symbol = trimmedNonEmpty(object?.symbol);
      const key = `${path}\u0000${symbol ?? ""}`;
      if (seen.has(key)) continue;
      seen.add(key);
      result.push({ path, symbol });
    }
    return result;
  }
}

export function refinerOutputSchema(allowedTags: string[]): JsonSchema {
  const moduleSchema: JsonSchema = {
    type: "object",
    properties: {
      name: { type: "string" },
      purpose: { type: "string" },
      tags: { type: "array", items: { type: "string", enum: allowedTags } },
      language: { type: "string" },
      ownedFiles: { type: "array", items: { type: "string" } },
      sharedDependencies: { type: "array", items: { type: "string" } },
      entrypoints: {
        type: "array",
        items: {
          type: "object",
          properties: { path: { type: "string" }, symbol: { type: "string" } },
          required: ["path", "symbol"],
          additionalProperties: false,
        },
      },
      anchors: { type: "array", items: { type: "string" } },
      confidence: { type: "number", minimum: 0, maximum: 1 },
    },
    required: ["name", "purpose", "tags", "language", "ownedFiles", "sharedDependencies", "entrypoints", "anchors", "confidence"],
    additionalProperties: false,
  };

  return {
    type: "object",
    properties: {
      module: { anyOf: [moduleSchema, { type: "null" }] },
      qualityGateHints: {
        type: "object",
        properties: {
          externalFacingCapability: { type: "boolean" },
          multiFileCohesion: { type: "boolean" },
          anchorPresent: { type: "boolean" },
          rightGranularity: { type: "boolean" },
        },
        required: ["externalFacingCapability", "multiFileCohesion", "anchorPresent", "rightGranularity"],
        additionalProperties: false,
      },
      reject: {
        anyOf: [
          {
            type: "object",
            properties: { reason: { type: "string" } },
            required: ["reason"],
            additionalProperties: false,
          },
          { type: "null" },
        ],
      },
    },
    required: ["module", "qualityGateHints", "reject"],
    additionalProperties: false,
  };
}
