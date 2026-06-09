import { describe, expect, it } from "vitest";

import { parseHypotheses } from "../src/decompose/survey.js";

const knownFiles = new Set([
  "src/immersive_audio_book/cli.py",
  "src/immersive_audio_book/llm/pipelines.py",
  "src/immersive_audio_book/llm/runner.py",
]);

describe("parseHypotheses", () => {
  it("keeps a hypothesis whose collaborators are names, not file paths", () => {
    const response = {
      hypotheses: [
        {
          name: "Command Line Interface for Audiobook Processing",
          rationale: "cli.py orchestrates the audiobook workflow.",
          anchors: ["src/immersive_audio_book/cli.py"],
          seedFiles: ["src/immersive_audio_book/cli.py"],
          // descriptive collaborator names, NOT repo file paths
          expectedCollaborators: ["process_runner", "logging", "utils"],
          granularity: "module-level",
        },
      ],
    };

    const result = parseHypotheses(response, knownFiles);

    expect(result).toHaveLength(1);
    // unresolved collaborator names are dropped, not the whole hypothesis
    expect(result[0]!.expectedCollaborators).toEqual([]);
    expect(result[0]!.seedFiles).toEqual(["src/immersive_audio_book/cli.py"]);
  });

  it("retains collaborators that resolve to known files and drops the rest", () => {
    const response = {
      hypotheses: [
        {
          name: "LLM Pipelines",
          rationale: "Pipelines and runner process content.",
          anchors: ["src/immersive_audio_book/llm/pipelines.py"],
          seedFiles: ["src/immersive_audio_book/llm/pipelines.py"],
          expectedCollaborators: ["src/immersive_audio_book/llm/runner.py", "logging"],
          granularity: "subpackage-level",
        },
      ],
    };

    const result = parseHypotheses(response, knownFiles);

    expect(result).toHaveLength(1);
    expect(result[0]!.expectedCollaborators).toEqual(["src/immersive_audio_book/llm/runner.py"]);
  });

  it("still rejects a hypothesis whose seed files are unknown", () => {
    const response = {
      hypotheses: [
        {
          name: "Phantom module",
          rationale: "Seeds do not exist in the repo.",
          anchors: ["does/not/exist.py"],
          seedFiles: ["does/not/exist.py"],
          expectedCollaborators: [],
          granularity: "module-level",
        },
      ],
    };

    expect(parseHypotheses(response, knownFiles)).toHaveLength(0);
  });
});
