import { describe, expect, it } from "vitest";

import { languageKindForPath, uniqued, clamp } from "../src/models.js";

describe("models", () => {
  it("maps file extensions to language kinds", () => {
    expect(languageKindForPath("a/b.ts")).toBe("typeScript");
    expect(languageKindForPath("a/b.tsx")).toBe("typeScript");
    expect(languageKindForPath("a/b.js")).toBe("javaScript");
    expect(languageKindForPath("a/b.py")).toBe("python");
    expect(languageKindForPath("a/b.go")).toBe("go");
    expect(languageKindForPath("a/b.swift")).toBe("swift");
    expect(languageKindForPath("a/b.md")).toBe("unknown");
  });

  it("uniques while preserving order", () => {
    expect(uniqued([3, 1, 3, 2, 1])).toEqual([3, 1, 2]);
  });

  it("clamps to range", () => {
    expect(clamp(1.5, 0, 1)).toBe(1);
    expect(clamp(-0.2, 0, 1)).toBe(0);
    expect(clamp(0.4, 0, 1)).toBe(0.4);
  });
});
