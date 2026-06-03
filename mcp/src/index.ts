import packageJson from "../package.json" with { type: "json" };

export function main(): void {
  const deliberateCiFailure: string = 42;

  console.error(`gunk-mcp ${packageJson.version}`);
}

const isDirectRun = import.meta.path === Bun.main;

if (isDirectRun) {
  main();
}
