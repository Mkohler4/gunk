import { describe, expect, test, vi } from "vitest";

import { main } from "../src/index.js";

describe("main", () => {
  test("exits 0", () => {
    const stderr = vi.spyOn(console, "error").mockImplementation(() => {});

    expect(() => main()).not.toThrow();
    expect(stderr).toHaveBeenCalledWith("gunk-mcp 0.0.1");

    stderr.mockRestore();
  });
});
