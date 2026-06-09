import { describe, expect, it } from "vitest";

import {
  RepoMap,
  RepoMapCluster,
  RepoMapFile,
  TRUNCATION_MARKER,
} from "../src/ingest/repoMap.js";

function file(path: string, clusterId: string, imports: number): RepoMapFile {
  return new RepoMapFile(
    path,
    100,
    clusterId,
    [{ name: path.split("/").at(-1)?.replace(".ts", "") ?? path, kind: "function", line: 1 }],
    [{ name: "run", kind: "function", line: 2 }],
    Array.from({ length: imports }, (_, index) => ({
      specifier: `huge-dependency-${index.toString().padStart(2, "0")}`,
      target: null,
    })),
    [],
    [],
    [],
    [],
    [],
  );
}

function cluster(id: string, path: string): RepoMapCluster {
  return new RepoMapCluster(id, [path], 1, [], [], []);
}

describe("RepoMap", () => {
  it("chunks a truncated map deterministically under the budget", () => {
    const repoMap = new RepoMap(
      [
        file("src/a.ts", "c1", 40),
        file("src/b.ts", "c2", 40),
        file("src/c.ts", "c3", 40),
      ],
      [cluster("c1", "src/a.ts"), cluster("c2", "src/b.ts"), cluster("c3", "src/c.ts")],
      {},
    );
    const first = repoMap.serializedChunks(120);
    const second = repoMap.serializedChunks(120);

    expect(repoMap.serialized(120)).toContain(TRUNCATION_MARKER);
    expect(first).toEqual(second);
    expect(first.length).toBeGreaterThan(1);
    expect(first.every((chunk) => chunk.length <= 120 * 4)).toBe(true);
    expect(first.join("\n")).toContain("src/c.ts");
  });
});
