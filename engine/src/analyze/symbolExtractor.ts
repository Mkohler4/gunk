import { Language, Parser, type Node } from "web-tree-sitter";

// Embed the tree-sitter runtime + grammars into the build with `type: "file"`.
// Under `bun run` these resolve to node_modules paths; in the compiled
// `gunk-engine` binary Bun embeds them and hands back a runtime-extractable
// path, so the single binary needs no node_modules on the target machine.
import treeSitterRuntimeWasm from "web-tree-sitter/tree-sitter.wasm" with { type: "file" };
import javascriptWasm from "tree-sitter-wasms/out/tree-sitter-javascript.wasm" with { type: "file" };
import typescriptWasm from "tree-sitter-wasms/out/tree-sitter-typescript.wasm" with { type: "file" };
import tsxWasm from "tree-sitter-wasms/out/tree-sitter-tsx.wasm" with { type: "file" };
import pythonWasm from "tree-sitter-wasms/out/tree-sitter-python.wasm" with { type: "file" };
import swiftWasm from "tree-sitter-wasms/out/tree-sitter-swift.wasm" with { type: "file" };
import goWasm from "tree-sitter-wasms/out/tree-sitter-go.wasm" with { type: "file" };

import {
  type ExportRef,
  type FileSymbols,
  type ImportRef,
  type LanguageKind,
  languageKindForPath,
  type Symbol,
  type SymbolKind,
} from "../models.js";
import { analysisFirstMatch, analysisMatches, analysisRawMatches } from "./analysisRegex.js";

export interface SymbolFile {
  path: string;
  contents: string;
}

export interface SymbolExtractor {
  extract(file: SymbolFile): FileSymbols;
}

type GrammarName = "javascript" | "typescript" | "tsx" | "python" | "swift" | "go";

const GRAMMAR_WASM: Record<GrammarName, string> = {
  javascript: javascriptWasm,
  typescript: typescriptWasm,
  tsx: tsxWasm,
  python: pythonWasm,
  swift: swiftWasm,
  go: goWasm,
};

const GRAMMARS: GrammarName[] = ["javascript", "typescript", "tsx", "python", "swift", "go"];

// --- structural dedupe (parity with Swift `Array.uniqued()` over Hashable) ---

function uniquedBy<T>(items: T[], key: (item: T) => string): T[] {
  const seen = new Set<string>();
  const out: T[] = [];
  for (const item of items) {
    const k = key(item);
    if (!seen.has(k)) {
      seen.add(k);
      out.push(item);
    }
  }
  return out;
}

function symbolKey(symbol: Symbol): string {
  return `${symbol.name}\u0000${symbol.kind}\u0000${symbol.line}`;
}

function importKey(ref: ImportRef): string {
  return `${ref.moduleSpecifier}\u0000${ref.resolvedTarget ?? "\u0001"}\u0000${ref.line}`;
}

function exportKey(ref: ExportRef): string {
  return `${ref.name}\u0000${ref.kind ?? "\u0001"}\u0000${ref.line}`;
}

function firstCharIsUppercase(name: string): boolean {
  if (name.length === 0) {
    return false;
  }
  const first = name[0];
  return first !== first.toLowerCase() && first === first.toUpperCase();
}

// --- regex helpers (faithful ports of the private Swift functions) ---

function moduleSpecifiers(text: string): string[] {
  return analysisMatches(text, String.raw`"([^"]+)"|'([^']+)'`)
    .map((groups) => groups.find((value) => value.length > 0))
    .filter((value): value is string => value !== undefined);
}

function requireSpecifier(text: string): string | undefined {
  return analysisFirstMatch(text, String.raw`require\s*\(\s*["']([^"']+)["']\s*\)`);
}

function pythonImportSpecifiers(text: string): string[] {
  const fromModule = analysisFirstMatch(
    text,
    String.raw`^from\s+([A-Za-z_][A-Za-z0-9_\.]*)\s+import\s+`,
  );
  if (fromModule !== undefined) {
    return [fromModule];
  }

  const imported = analysisFirstMatch(text, String.raw`^import\s+(.+)$`);
  if (imported === undefined) {
    return [];
  }

  return imported
    .split(",")
    .map((part) => {
      const trimmed = part.trim();
      const tokens = trimmed.split(" ").filter((token) => token.length > 0);
      return tokens.length > 0 ? tokens[0] : "";
    })
    .filter((value) => value.length > 0);
}

function variableNames(text: string): string[] {
  return analysisMatches(text, String.raw`(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)`)
    .map((groups) => groups[0])
    .filter((value): value is string => value !== undefined);
}

function javaScriptExports(text: string, line: number): ExportRef[] {
  const exports: ExportRef[] = [];

  const patterns: [string, SymbolKind][] = [
    [String.raw`export\s+(?:default\s+)?function\s+([A-Za-z_$][A-Za-z0-9_$]*)`, "function"],
    [String.raw`export\s+(?:default\s+)?class\s+([A-Za-z_$][A-Za-z0-9_$]*)`, "class"],
    [String.raw`export\s+interface\s+([A-Za-z_$][A-Za-z0-9_$]*)`, "interface"],
    [String.raw`export\s+type\s+([A-Za-z_$][A-Za-z0-9_$]*)`, "type"],
    [String.raw`export\s+(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)`, "variable"],
  ];

  for (const [pattern, kind] of patterns) {
    for (const groups of analysisMatches(text, pattern)) {
      const name = groups[0];
      if (name !== undefined) {
        exports.push({ name, kind, line });
      }
    }
  }

  const namedExports = analysisFirstMatch(text, String.raw`export\s*\{([^}]+)\}`);
  if (namedExports !== undefined) {
    for (const part of namedExports.split(",")) {
      const segments = part.trim().split(" as ");
      const name = (segments[segments.length - 1] ?? "").trim();
      if (name.length > 0) {
        exports.push({ name, kind: null, line });
      }
    }
  }

  return exports;
}

function swiftPrimaryDeclaration(text: string, line: number): Symbol | null {
  const matches = analysisMatches(
    text,
    String.raw`\b(func|class|struct|enum|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)`,
  );
  const first = matches[0];
  if (!first || first.length < 2) {
    return null;
  }

  const keyword = first[0];
  const name = first[1];

  let kind: SymbolKind;
  switch (keyword) {
    case "func":
      kind = "function";
      break;
    case "class":
      kind = "class";
      break;
    case "struct":
      kind = "struct";
      break;
    case "enum":
      kind = "enum";
      break;
    case "protocol":
      kind = "protocolDecl";
      break;
    default:
      return null;
  }

  return { name, kind, line };
}

function swiftPrimaryDeclarationIsExported(text: string): boolean {
  return (
    analysisRawMatches(
      text,
      String.raw`^\s*(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s*)*(?:public|open)\s+\b(?:func|class|struct|enum|protocol)\b`,
    ).length > 0
  );
}

function goTypeNames(text: string): string[] {
  return analysisMatches(text, String.raw`type\s+([A-Za-z_][A-Za-z0-9_]*)`)
    .map((groups) => groups[0])
    .filter((value): value is string => value !== undefined);
}

function relativeTarget(specifier: string): string | null {
  return specifier.startsWith(".") ? specifier : null;
}

function splitLines(text: string): string[] {
  return text.split(/\r\n|\r|\n/);
}

function fallbackImports(text: string): ImportRef[] {
  const imports: ImportRef[] = [];
  const lines = splitLines(text);

  lines.forEach((line, index) => {
    const lineNumber = index + 1;
    if (line.includes("import") || line.includes("require")) {
      for (const specifier of moduleSpecifiers(line)) {
        imports.push({
          moduleSpecifier: specifier,
          resolvedTarget: relativeTarget(specifier),
          line: lineNumber,
        });
      }
    }

    const pythonModule = analysisFirstMatch(
      line,
      String.raw`^(?:from|import)\s+([A-Za-z_][A-Za-z0-9_\.]*)`,
    );
    if (pythonModule !== undefined) {
      imports.push({ moduleSpecifier: pythonModule, resolvedTarget: null, line: lineNumber });
    }

    const swiftModule = analysisFirstMatch(line, String.raw`^import\s+([A-Za-z_][A-Za-z0-9_]*)`);
    if (swiftModule !== undefined) {
      imports.push({ moduleSpecifier: swiftModule, resolvedTarget: null, line: lineNumber });
    }
  });

  return uniquedBy(imports, importKey);
}

function fallbackSymbols(text: string): Symbol[] {
  const symbols: Symbol[] = [];
  const lines = splitLines(text);

  lines.forEach((line, index) => {
    const lineNumber = index + 1;

    const fnName = analysisFirstMatch(line, String.raw`\bfunction\s+([A-Za-z_$][A-Za-z0-9_$]*)`);
    if (fnName !== undefined) {
      symbols.push({ name: fnName, kind: "function", line: lineNumber });
    }

    const className = analysisFirstMatch(line, String.raw`\bclass\s+([A-Za-z_$][A-Za-z0-9_$]*)`);
    if (className !== undefined) {
      symbols.push({ name: className, kind: "class", line: lineNumber });
    }
  });

  return uniquedBy(symbols, symbolKey);
}

// --- tree walking ---

function walk(node: Node, visit: (node: Node) => void): void {
  visit(node);
  for (let index = 0; index < node.childCount; index += 1) {
    const child = node.child(index);
    if (child) {
      walk(child, visit);
    }
  }
}

function appendSymbol(
  node: Node,
  kind: SymbolKind,
  line: number,
  symbols: Symbol[],
): void {
  const nameNode = node.childForFieldName("name");
  if (!nameNode) {
    return;
  }

  const name = nameNode.text;
  if (name.length === 0) {
    return;
  }

  symbols.push({ name, kind, line });
}

function appendSwiftDeclaration(
  text: string,
  line: number,
  symbols: Symbol[],
  exports: ExportRef[],
): void {
  const symbol = swiftPrimaryDeclaration(text, line);
  if (!symbol) {
    return;
  }

  symbols.push(symbol);

  if (swiftPrimaryDeclarationIsExported(text)) {
    exports.push({ name: symbol.name, kind: symbol.kind, line });
  }
}

function collectJavaScriptLike(
  node: Node,
  type: string,
  text: string,
  line: number,
  symbols: Symbol[],
  imports: ImportRef[],
  exports: ExportRef[],
): void {
  switch (type) {
    case "import_statement":
      for (const specifier of moduleSpecifiers(text)) {
        imports.push({
          moduleSpecifier: specifier,
          resolvedTarget: relativeTarget(specifier),
          line,
        });
      }
      break;
    case "call_expression": {
      const specifier = requireSpecifier(text);
      if (specifier !== undefined) {
        imports.push({
          moduleSpecifier: specifier,
          resolvedTarget: relativeTarget(specifier),
          line,
        });
      }
      break;
    }
    case "function_declaration":
      appendSymbol(node, "function", line, symbols);
      break;
    case "class_declaration":
      appendSymbol(node, "class", line, symbols);
      break;
    case "method_definition":
      appendSymbol(node, "method", line, symbols);
      break;
    case "interface_declaration":
      appendSymbol(node, "interface", line, symbols);
      break;
    case "type_alias_declaration":
      appendSymbol(node, "type", line, symbols);
      break;
    case "lexical_declaration":
    case "variable_declaration":
      for (const name of variableNames(text)) {
        symbols.push({ name, kind: "variable", line });
      }
      break;
    case "export_statement":
      exports.push(...javaScriptExports(text, line));
      for (const specifier of moduleSpecifiers(text)) {
        imports.push({
          moduleSpecifier: specifier,
          resolvedTarget: relativeTarget(specifier),
          line,
        });
      }
      break;
    default:
      break;
  }
}

function collectPython(
  node: Node,
  type: string,
  text: string,
  line: number,
  symbols: Symbol[],
  imports: ImportRef[],
): void {
  switch (type) {
    case "import_statement":
    case "import_from_statement":
      for (const specifier of pythonImportSpecifiers(text)) {
        imports.push({ moduleSpecifier: specifier, resolvedTarget: null, line });
      }
      break;
    case "function_definition":
      appendSymbol(node, "function", line, symbols);
      break;
    case "class_definition":
      appendSymbol(node, "class", line, symbols);
      break;
    default:
      break;
  }
}

function collectSwift(
  type: string,
  text: string,
  line: number,
  symbols: Symbol[],
  imports: ImportRef[],
  exports: ExportRef[],
): void {
  switch (type) {
    case "import_declaration": {
      const specifier = analysisFirstMatch(
        text,
        String.raw`import\s+(?:\w+\s+)?([A-Za-z_][A-Za-z0-9_]*)`,
      );
      if (specifier !== undefined) {
        imports.push({ moduleSpecifier: specifier, resolvedTarget: null, line });
      }
      break;
    }
    case "function_declaration":
    case "class_declaration":
    case "struct_declaration":
    case "enum_declaration":
    case "protocol_declaration":
      appendSwiftDeclaration(text, line, symbols, exports);
      break;
    default:
      break;
  }
}

function collectGo(
  node: Node,
  type: string,
  text: string,
  line: number,
  symbols: Symbol[],
  imports: ImportRef[],
  exports: ExportRef[],
): void {
  switch (type) {
    case "import_spec":
      for (const specifier of moduleSpecifiers(text)) {
        imports.push({ moduleSpecifier: specifier, resolvedTarget: null, line });
      }
      break;
    case "function_declaration":
      appendSymbol(node, "function", line, symbols);
      break;
    case "method_declaration":
      appendSymbol(node, "method", line, symbols);
      break;
    case "type_declaration":
      for (const name of goTypeNames(text)) {
        symbols.push({ name, kind: "type", line });
        if (firstCharIsUppercase(name)) {
          exports.push({ name, kind: "type", line });
        }
      }
      break;
    default:
      break;
  }

  const last = symbols[symbols.length - 1];
  if (last && last.line === line && firstCharIsUppercase(last.name)) {
    exports.push({ name: last.name, kind: last.kind, line });
  }
}

function fallbackExtract(file: SymbolFile, language: LanguageKind): FileSymbols {
  return {
    path: file.path,
    language,
    symbols: fallbackSymbols(file.contents),
    imports: fallbackImports(file.contents),
    exports: [],
  };
}

function grammarFor(language: LanguageKind, path: string): GrammarName | null {
  switch (language) {
    case "go":
      return "go";
    case "javaScript":
      return "javascript";
    case "python":
      return "python";
    case "swift":
      return "swift";
    case "typeScript":
      return path.toLowerCase().endsWith(".tsx") ? "tsx" : "typescript";
    case "unknown":
      return null;
  }
}

class TreeSitterSymbolExtractor implements SymbolExtractor {
  private readonly languages: Map<GrammarName, Language>;

  constructor(languages: Map<GrammarName, Language>) {
    this.languages = languages;
  }

  extract(file: SymbolFile): FileSymbols {
    const language = languageKindForPath(file.path);

    if (language === "unknown") {
      return fallbackExtract(file, language);
    }

    const grammarName = grammarFor(language, file.path);
    const grammar = grammarName ? this.languages.get(grammarName) : undefined;
    if (!grammar) {
      return fallbackExtract(file, language);
    }

    const parser = new Parser();
    parser.setLanguage(grammar);
    const tree = parser.parse(file.contents);
    const root = tree?.rootNode;
    if (!root) {
      return fallbackExtract(file, language);
    }

    const symbols: Symbol[] = [];
    const imports: ImportRef[] = [];
    const exports: ExportRef[] = [];

    walk(root, (node) => {
      const type = node.type;
      const text = node.text;
      const line = node.startPosition.row + 1;

      switch (language) {
        case "javaScript":
        case "typeScript":
          collectJavaScriptLike(node, type, text, line, symbols, imports, exports);
          break;
        case "python":
          collectPython(node, type, text, line, symbols, imports);
          break;
        case "swift":
          collectSwift(type, text, line, symbols, imports, exports);
          break;
        case "go":
          collectGo(node, type, text, line, symbols, imports, exports);
          break;
      }
    });

    return {
      path: file.path,
      language,
      symbols: uniquedBy(symbols, symbolKey),
      imports: uniquedBy(imports, importKey),
      exports: uniquedBy(exports, exportKey),
    };
  }
}

/** Synchronous regex-only extractor for unknown languages or grammar-load failures. */
export class FallbackSymbolExtractor implements SymbolExtractor {
  extract(file: SymbolFile): FileSymbols {
    return fallbackExtract(file, languageKindForPath(file.path));
  }
}

let parserInitialized: Promise<void> | null = null;

function ensureParserInitialized(): Promise<void> {
  if (!parserInitialized) {
    parserInitialized = Parser.init({ locateFile: () => treeSitterRuntimeWasm });
  }
  return parserInitialized;
}

export async function createTreeSitterSymbolExtractor(): Promise<SymbolExtractor> {
  await ensureParserInitialized();

  const languages = new Map<GrammarName, Language>();
  for (const name of GRAMMARS) {
    languages.set(name, await Language.load(GRAMMAR_WASM[name]));
  }

  return new TreeSitterSymbolExtractor(languages);
}
