import { expect, test } from "vitest";

import { main } from "../src/index.js";

test("exports the MCP entrypoint", () => {
  expect(main).toBeTypeOf("function");
});
