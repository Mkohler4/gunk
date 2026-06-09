import { describe, expect, it } from "vitest";

import { MAX_TAGS_PER_MODULE, normalizeTag, normalizeTags } from "../src/analyze/tagNormalizer.js";

describe("normalizeTag", () => {
  it("lowercases and kebab-cases mixed-case spaced tags", () => {
    expect(normalizeTag("Mixed_Case Tag")).toBe("mixed-case-tag");
  });

  it("strips invalid characters and collapses hyphens", () => {
    expect(normalizeTag("  Order Intake! ")).toBe("order-intake");
    expect(normalizeTag("db__layer")).toBe("db-layer");
    expect(normalizeTag("--api--")).toBe("api");
  });

  it("returns null when nothing meaningful remains", () => {
    expect(normalizeTag("   ")).toBeNull();
    expect(normalizeTag("!!!")).toBeNull();
  });
});

describe("normalizeTags", () => {
  it("normalizes, drops empties, and dedupes while keeping order stable", () => {
    expect(normalizeTags(["Auth", "auth", "Order Intake", "  ", "payments"])).toEqual([
      "auth",
      "order-intake",
      "payments",
    ]);
  });

  it("caps the number of tags per module", () => {
    const many = Array.from({ length: MAX_TAGS_PER_MODULE + 4 }, (_, i) => `tag-${i}`);
    expect(normalizeTags(many)).toHaveLength(MAX_TAGS_PER_MODULE);
  });
});
