import { rmSync } from "node:fs";

rmSync("dist", { force: true, recursive: true });

const result = await Bun.build({
  entrypoints: ["./src/index.ts"],
  compile: {
    outfile: "./dist/gunk-mcp",
  },
});

if (!result.success) {
  for (const log of result.logs) {
    console.error(log);
  }

  process.exitCode = 1;
}
