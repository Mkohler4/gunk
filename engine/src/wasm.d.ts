// Bun embeds files imported with `{ type: "file" }` into the compiled binary
// and resolves the default export to a runtime path. This keeps the tree-sitter
// grammars working both under `bun run` (dev) and in the single-file binary.
declare module "*.wasm" {
  const path: string;

  export default path;
}
