// Domain models for the decomposition engine, ported from the Swift app.
// These mirror the Swift structs in app/Sources/GunkApp/{Analyze,Decompose,Ingest}.

export type LanguageKind =
  | "dart"
  | "go"
  | "java"
  | "javaScript"
  | "kotlin"
  | "python"
  | "swift"
  | "typeScript"
  | "unknown";

export function languageKindForPath(path: string): LanguageKind {
  const p = path.toLowerCase();
  if (p.endsWith(".dart")) return "dart";
  if (p.endsWith(".go")) return "go";
  if (p.endsWith(".java")) return "java";
  if (p.endsWith(".js") || p.endsWith(".jsx") || p.endsWith(".mjs")) return "javaScript";
  if (p.endsWith(".kt") || p.endsWith(".kts")) return "kotlin";
  if (p.endsWith(".py")) return "python";
  if (p.endsWith(".swift")) return "swift";
  if (p.endsWith(".ts") || p.endsWith(".tsx") || p.endsWith(".mts")) return "typeScript";
  return "unknown";
}

export type SymbolKind =
  | "class"
  | "enum"
  | "function"
  | "interface"
  | "method"
  | "protocolDecl"
  | "struct"
  | "type"
  | "variable";

export interface Symbol {
  name: string;
  kind: SymbolKind;
  line: number;
}

export interface ImportRef {
  moduleSpecifier: string;
  resolvedTarget: string | null;
  line: number;
}

export interface ExportRef {
  name: string;
  kind: SymbolKind | null;
  line: number;
}

export interface FileSymbols {
  path: string;
  language: LanguageKind;
  viaFallback: boolean;
  symbols: Symbol[];
  imports: ImportRef[];
  exports: ExportRef[];
}

export interface ScannedFile {
  /** Absolute path on disk. */
  absPath: string;
  /** Path relative to the source root, forward-slash separated. */
  relpath: string;
  size: number;
}

// --- Code graph ---

export type CodeGraphNodeKind = "file" | "symbol";

export interface CodeGraphNode {
  id: string;
  kind: CodeGraphNodeKind;
  filePath: string;
  symbolName?: string;
}

export type CodeGraphEdgeKind =
  | "call"
  | "import"
  | "implements"
  | "inherit"
  | "reference"
  | "contains";

export interface CodeGraphEdge {
  from: CodeGraphNode;
  to: CodeGraphNode;
  kind: CodeGraphEdgeKind;
}

export interface CodeGraph {
  nodes: CodeGraphNode[];
  edges: CodeGraphEdge[];
}

export function fileNode(filePath: string): CodeGraphNode {
  return { id: `file:${filePath}`, kind: "file", filePath };
}

// --- Capability hypotheses / expansion ---

export type HypothesisPriority = "normal" | "low";

export interface CapabilityHypothesis {
  name: string;
  rationale: string;
  anchors: string[];
  seedFiles: string[];
  expectedCollaborators: string[];
  granularity: string;
  priority: HypothesisPriority;
}

export interface CapabilityExpansionExcludedFile {
  path: string;
  reason: string;
}

export interface CapabilityExpansionEdgeEvidence {
  fromPath: string;
  toPath: string;
  kind: CodeGraphEdgeKind;
  depth: number;
}

export interface CapabilityExpansion {
  hypothesis: CapabilityHypothesis;
  closureFiles: string[];
  ownedFiles: string[];
  sharedDependencyFiles: string[];
  excludedFiles: CapabilityExpansionExcludedFile[];
  edgeEvidence: CapabilityExpansionEdgeEvidence[];
}

// --- Modules ---

export interface ModuleSurface {
  path: string;
  symbol: string | null;
}

export interface Module {
  name: string;
  purpose: string | null;
  tags: string[];
  files: string[];
  language: string | null;
  confidence: number;
  ownedFiles: string[];
  sharedDeps: string[];
  surface: ModuleSurface[];
  anchors: string[];
}

// --- Quality gate ---

export type QualityGateDecision = "accepted" | "needsApproval" | "rejected";

export type QualityGateReason =
  | "belowConfidenceThreshold"
  | "duplicateOverlap"
  | "failsSelfContainment"
  | "generatedOnly"
  | "lowCohesion"
  | "missingFiles"
  | "missingSurface"
  | "singleFileWithoutOwnedSurface"
  | "typeOnly"
  | "utilityOnly"
  | "configOnly";

export type ModuleFileKind = "config" | "generated" | "source" | "typeOnly" | "utility";

export interface QualityGateEvaluation {
  module: Module;
  decision: QualityGateDecision;
  reasons: QualityGateReason[];
  cohesionScore: number | null;
  fileKinds: Record<string, ModuleFileKind>;
}

// --- Shared helpers ---

export function uniqued<T>(items: T[]): T[] {
  const seen = new Set<T>();
  const out: T[] = [];
  for (const item of items) {
    if (!seen.has(item)) {
      seen.add(item);
      out.push(item);
    }
  }
  return out;
}

export function clamp(value: number, lower: number, upper: number): number {
  return Math.min(Math.max(value, lower), upper);
}
