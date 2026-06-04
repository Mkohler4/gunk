import { startServer } from "./server/index.js";

export async function main(): Promise<void> {
  await startServer();
}

const isDirectRun = import.meta.path === Bun.main;

if (isDirectRun) {
  main().catch((error: unknown) => {
    console.error("gunk-mcp server error:", error);
    process.exitCode = 1;
  });
}
