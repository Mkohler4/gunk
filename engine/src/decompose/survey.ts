// Pass 1: capability survey. Ported from
// app/Sources/GunkApp/Decompose/CapabilitySurvey.swift.

import type { CapabilityHypothesis } from "../models.js";
import { uniqued } from "../models.js";
import type { JsonSchema, LLMClient, LLMRequest } from "../llm/client.js";

export interface SurveyRunRecord {
  inputTokens: number | null;
  outputTokens: number | null;
  startedAt: number;
  finishedAt: number;
}

export interface SurveyOptions {
  maxOutputTokens?: number;
  now?: () => number;
  recordRun?: (record: SurveyRunRecord) => void;
}

function trimmedNonEmpty(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function stringArray(value: unknown): string[] | null {
  if (!Array.isArray(value)) return null;
  return value.filter((v): v is string => typeof v === "string").map((v) => v.trim()).filter((v) => v.length > 0);
}

function asObject(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

export function surveyOutputSchema(): JsonSchema {
  return {
    type: "object",
    properties: {
      hypotheses: {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
            rationale: { type: "string" },
            anchors: { type: "array", items: { type: "string" } },
            seedFiles: { type: "array", items: { type: "string" } },
            expectedCollaborators: { type: "array", items: { type: "string" } },
            granularity: { type: "string" },
          },
          required: ["name", "rationale", "anchors", "seedFiles", "expectedCollaborators", "granularity"],
          additionalProperties: false,
        },
      },
    },
    required: ["hypotheses"],
    additionalProperties: false,
  };
}

function surveyRequest(
  model: string,
  sourceName: string,
  repoMap: string,
  knownFiles: string[],
  maxOutputTokens: number,
): LLMRequest {
  return {
    model,
    messages: [
      {
        role: "system",
        content: `You are Pass 1 of gunk's capability-centric decomposition pipeline.
Propose capability hypotheses from the structural repo map only.

Real-module rubric:
- A real module is a reusable capability or feature slice that spans the files needed to stand alone.
- Prefer user-visible or integration-visible capabilities such as OAuth login, Stripe checkout, upload pipeline, API endpoint group, CLI command, SDK client, or workflow.
- Reject file-level chunks, type-only files, generic utilities, config-only groups, generated files, docs-only groups, and arbitrary folders.
- Each hypothesis needs at least one structural anchor: route, entrypoint, public export, dependency capability hint, env/config key, or strongly connected graph cluster.
- Name the capability by what it does, not by a filename.`,
      },
      {
        role: "user",
        content: `Source: ${sourceName}

Known source files:
${[...knownFiles].sort().map((f) => `- ${f}`).join("\n")}

Return capability hypotheses with anchors, seed files, expected collaborators, and granularity.

Structural repo map:
${repoMap}`,
      },
    ],
    jsonSchemaName: "CapabilitySurvey",
    jsonSchema: surveyOutputSchema(),
    maxTokens: maxOutputTokens,
    temperature: 0,
  };
}

export function parseHypotheses(value: unknown, knownFiles: Set<string>): CapabilityHypothesis[] {
  const root = asObject(value);
  const hypotheses = root?.hypotheses;
  if (!Array.isArray(hypotheses)) {
    throw new Error("CapabilitySurvey: invalid response");
  }

  const result: CapabilityHypothesis[] = [];
  for (const raw of hypotheses) {
    const object = asObject(raw);
    if (!object) throw new Error("CapabilitySurvey: invalid response");
    const name = trimmedNonEmpty(object.name);
    const rationale = trimmedNonEmpty(object.rationale);
    const anchors = stringArray(object.anchors);
    const seedFiles = stringArray(object.seedFiles);
    const expectedCollaborators = stringArray(object.expectedCollaborators);
    const granularity = trimmedNonEmpty(object.granularity);
    if (!name || !rationale || !anchors || !seedFiles || !expectedCollaborators || !granularity) {
      throw new Error("CapabilitySurvey: invalid response");
    }

    const uniqueSeedFiles = uniqued(seedFiles);
    const uniqueCollaborators = uniqued(expectedCollaborators);
    const citedFiles = new Set([
      ...uniqueSeedFiles,
      ...uniqueCollaborators.filter((f) => knownFiles.has(f)),
    ]);

    if (uniqueSeedFiles.length === 0 || !uniqueSeedFiles.every((f) => knownFiles.has(f))) {
      continue;
    }
    if (uniqueCollaborators.some((f) => !knownFiles.has(f))) {
      continue;
    }

    const priority: CapabilityHypothesis["priority"] =
      anchors.length === 0 && citedFiles.size < 2 ? "low" : "normal";

    result.push({
      name,
      rationale,
      anchors: uniqued(anchors),
      seedFiles: uniqueSeedFiles,
      expectedCollaborators: uniqueCollaborators,
      granularity,
      priority,
    });
  }

  return result;
}

function hypothesisKey(hypothesis: CapabilityHypothesis): string {
  return hypothesis.name.toLowerCase().replace(/\s+/g, " ").trim();
}

function mergedHypotheses(hypotheses: CapabilityHypothesis[]): CapabilityHypothesis[] {
  const byName = new Map<string, CapabilityHypothesis>();
  for (const hypothesis of hypotheses) {
    const key = hypothesisKey(hypothesis);
    const existing = byName.get(key);
    if (!existing) {
      byName.set(key, hypothesis);
      continue;
    }

    byName.set(key, {
      ...existing,
      anchors: uniqued([...existing.anchors, ...hypothesis.anchors]).sort((a, b) => a.localeCompare(b)),
      seedFiles: uniqued([...existing.seedFiles, ...hypothesis.seedFiles]).sort((a, b) => a.localeCompare(b)),
      expectedCollaborators: uniqued([...existing.expectedCollaborators, ...hypothesis.expectedCollaborators]).sort(
        (a, b) => a.localeCompare(b),
      ),
      priority: existing.priority === "normal" || hypothesis.priority === "normal" ? "normal" : "low",
    });
  }
  return [...byName.values()];
}

export async function survey(
  client: LLMClient,
  args: { model: string; sourceName: string; repoMap: string; repoMapChunks?: string[]; knownFiles: string[] },
  options: SurveyOptions = {},
): Promise<CapabilityHypothesis[]> {
  const now = options.now ?? Date.now;
  const maxOutputTokens = options.maxOutputTokens ?? 4096;
  const knownFiles = new Set(args.knownFiles);
  const repoMaps = args.repoMapChunks && args.repoMapChunks.length > 1 ? args.repoMapChunks : [args.repoMap];
  const parsed: CapabilityHypothesis[] = [];

  for (const repoMap of repoMaps) {
    const startedAt = now();
    const response = await client.complete(
      surveyRequest(args.model, args.sourceName, repoMap, args.knownFiles, maxOutputTokens),
    );
    const finishedAt = now();

    options.recordRun?.({
      inputTokens: response.usage.inputTokens,
      outputTokens: response.usage.outputTokens,
      startedAt,
      finishedAt,
    });

    parsed.push(...parseHypotheses(response.json, knownFiles));
  }

  return mergedHypotheses(parsed);
}
