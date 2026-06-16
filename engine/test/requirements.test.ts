import { describe, expect, it } from "vitest";

import { deriveRuntime } from "../src/extract/requirements.js";

describe("deriveRuntime", () => {
  it("reads requires-python from pyproject", () => {
    expect(
      deriveRuntime("python", {
        "pyproject.toml": 'requires-python = ">=3.11"\n',
      }),
    ).toBe("Python ≥ 3.11");
  });

  it("reads engines.node from package.json and maps JS/TS to Node", () => {
    expect(
      deriveRuntime("typeScript", {
        "package.json": JSON.stringify({ engines: { node: ">=18" } }),
      }),
    ).toBe("Node ≥ 18");
  });

  it("reads the go directive from go.mod", () => {
    expect(deriveRuntime("go", { "go.mod": "module x\n\ngo 1.21\n" })).toBe(
      "Go ≥ 1.21",
    );
  });

  it("falls back to the bare language name when no constraint is parseable", () => {
    expect(deriveRuntime("python", { "requirements.txt": "ebooklib\n" })).toBe(
      "Python",
    );
  });

  it("prefers the manifest matching the module language", () => {
    expect(
      deriveRuntime("python", {
        "package.json": JSON.stringify({ engines: { node: ">=20" } }),
        "pyproject.toml": 'requires-python = ">=3.12"\n',
      }),
    ).toBe("Python ≥ 3.12");
  });

  it("returns null when the language is unknown and no manifests carry a constraint", () => {
    expect(deriveRuntime(null, {})).toBeNull();
  });
});
