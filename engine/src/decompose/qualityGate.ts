// Real-module quality gates. Ported from
// app/Sources/GunkApp/Decompose/ModuleQualityGate.swift.

import type {
  CodeGraph,
  Module,
  ModuleFileKind,
  QualityGateEvaluation,
  QualityGateReason,
} from "../models.js";
import { uniqued } from "../models.js";
import type { CapabilityFingerprint } from "../analyze/capabilityFingerprint.js";
import type { SelfContainmentResult } from "./selfContainment.js";

export interface QualityGateOptions {
  confidenceThreshold: number;
  cohesionThreshold: number;
  duplicateOverlapThreshold: number;
}

export const defaultQualityGateOptions: QualityGateOptions = {
  confidenceThreshold: 0.7,
  cohesionThreshold: 0.35,
  duplicateOverlapThreshold: 0.85,
};

export class ModuleQualityGate {
  constructor(private readonly options: QualityGateOptions = defaultQualityGateOptions) {}

  evaluateModule(
    module: Module,
    fingerprints: CapabilityFingerprint[] = [],
    graph: CodeGraph | null = null,
    contentsByPath: Record<string, string> = {},
    selfContainment: SelfContainmentResult | null = null,
  ): QualityGateEvaluation {
    const moduleFiles = uniqued(module.files);
    const fileKinds = this.fileKinds(moduleFiles, contentsByPath);
    const cohesionScore = graph ? this.cohesion(moduleFiles, graph) : null;
    const trivialityReasons = this.trivialityReasons(fileKinds);
    const failsSelfContainment = this.failsSelfContainment(selfContainment);
    const failsVerifiedEntrypoint = selfContainment?.entrypoint === "fail";
    const selfContainedEntrypoint = this.hasVerifiedSelfContainedEntrypoint(moduleFiles, module, selfContainment);
    const reasons: QualityGateReason[] = [];

    if (moduleFiles.length === 0) reasons.push("missingFiles");
    if (!this.hasSurface(module, fingerprints) || failsVerifiedEntrypoint) reasons.push("missingSurface");
    if (moduleFiles.length === 1 && !this.singleFileOwnsSurface(module, fingerprints)) {
      reasons.push("singleFileWithoutOwnedSurface");
    }
    if (
      moduleFiles.length > 1 &&
      cohesionScore !== null &&
      cohesionScore < this.options.cohesionThreshold &&
      !selfContainedEntrypoint
    ) {
      reasons.push("lowCohesion");
    }
    reasons.push(...trivialityReasons);

    const rejectionReasons = uniqued(reasons).sort((a, b) => a.localeCompare(b));
    if (rejectionReasons.length > 0) {
      const allReasons = failsSelfContainment
        ? uniqued([...rejectionReasons, "failsSelfContainment" as QualityGateReason]).sort((a, b) =>
            a.localeCompare(b),
          )
        : rejectionReasons;
      return { module, decision: "rejected", reasons: allReasons, cohesionScore, fileKinds };
    }
    const approvalReasons: QualityGateReason[] = [];
    if (failsSelfContainment) approvalReasons.push("failsSelfContainment");
    if (module.confidence < this.options.confidenceThreshold) approvalReasons.push("belowConfidenceThreshold");
    if (approvalReasons.length > 0) {
      return {
        module,
        decision: "needsApproval",
        reasons: uniqued(approvalReasons).sort((a, b) => a.localeCompare(b)),
        cohesionScore,
        fileKinds,
      };
    }
    return { module, decision: "accepted", reasons: [], cohesionScore, fileKinds };
  }

  evaluate(
    modules: Module[],
    fingerprints: CapabilityFingerprint[] = [],
    graph: CodeGraph | null = null,
    contentsByPath: Record<string, string> = {},
    selfContainmentResults: SelfContainmentResult[] = [],
  ): QualityGateEvaluation[] {
    const evaluations = modules.map((m, index) =>
      this.evaluateModule(m, fingerprints, graph, contentsByPath, selfContainmentResults[index] ?? null),
    );
    const duplicateIndexes = this.duplicateEvaluationIndexes(evaluations);
    for (const index of duplicateIndexes) {
      const evaluation = evaluations[index];
      const reasons = uniqued([...evaluation.reasons, "duplicateOverlap" as QualityGateReason]).sort((a, b) =>
        a.localeCompare(b),
      );
      evaluations[index] = { ...evaluation, decision: "rejected", reasons };
    }
    return evaluations;
  }

  private hasSurface(module: Module, fingerprints: CapabilityFingerprint[]): boolean {
    if (module.surface.length > 0 || module.anchors.length > 0) return true;
    return this.fingerprintsForModule(module, fingerprints).some(
      (fp) =>
        fp.routes.length > 0 ||
        fp.publicExports.length > 0 ||
        fp.capabilityHints.length > 0,
    );
  }

  private singleFileOwnsSurface(module: Module, fingerprints: CapabilityFingerprint[]): boolean {
    const file = module.files[0];
    if (file === undefined) return false;
    if (module.anchors.length > 0) return true;
    if (module.surface.some((s) => s.path === file)) return true;
    return fingerprints
      .filter((fp) => fp.filePath === file)
      .some(
        (fp) =>
          fp.routes.length > 0 ||
          fp.publicExports.length > 0 ||
          fp.capabilityHints.length > 0,
      );
  }

  private fingerprintsForModule(module: Module, fingerprints: CapabilityFingerprint[]): CapabilityFingerprint[] {
    const files = new Set(module.files);
    return fingerprints.filter((fp) => files.has(fp.filePath));
  }

  private failsSelfContainment(result: SelfContainmentResult | null): boolean {
    return result !== null && (result.imports === "fail" || result.entrypoint === "fail");
  }

  private hasVerifiedSelfContainedEntrypoint(
    moduleFiles: string[],
    module: Module,
    result: SelfContainmentResult | null,
  ): boolean {
    if (result === null || this.failsSelfContainment(result)) return false;
    const fileSet = new Set(moduleFiles);
    return module.surface.some((entrypoint) => fileSet.has(entrypoint.path) && (entrypoint.symbol?.length ?? 0) > 0);
  }

  private cohesion(files: string[], graph: CodeGraph): number {
    if (files.length <= 1) return 1;
    const fileSet = new Set(files);
    let internal = 0;
    let external = 0;
    for (const edge of graph.edges) {
      const fromIn = fileSet.has(edge.from.filePath);
      const toIn = fileSet.has(edge.to.filePath);
      if (fromIn && toIn) {
        if (edge.from.filePath !== edge.to.filePath) internal += 1;
      } else if (fromIn || toIn) {
        external += 1;
      }
    }
    const total = internal + external;
    if (total === 0) return 0;
    return internal / total;
  }

  private fileKinds(files: string[], contentsByPath: Record<string, string>): Record<string, ModuleFileKind> {
    const result: Record<string, ModuleFileKind> = {};
    for (const path of files) {
      result[path] = classify(path, contentsByPath[path] ?? "");
    }
    return result;
  }

  private trivialityReasons(fileKinds: Record<string, ModuleFileKind>): QualityGateReason[] {
    const kinds = new Set(Object.values(fileKinds));
    if (kinds.size === 0) return [];
    const eq = (set: Set<ModuleFileKind>) => kinds.size === set.size && [...kinds].every((k) => set.has(k));
    const subsetOf = (set: Set<ModuleFileKind>) => [...kinds].every((k) => set.has(k));

    if (eq(new Set(["generated"]))) return ["generatedOnly"];
    if (eq(new Set(["typeOnly"]))) return ["typeOnly"];
    if (eq(new Set(["utility"]))) return ["utilityOnly"];
    if (eq(new Set(["config"]))) return ["configOnly"];
    if (subsetOf(new Set(["typeOnly", "utility"]))) return ["typeOnly", "utilityOnly"];
    if (subsetOf(new Set(["config", "typeOnly"]))) return ["configOnly", "typeOnly"];
    return [];
  }

  private duplicateEvaluationIndexes(evaluations: QualityGateEvaluation[]): Set<number> {
    const duplicates = new Set<number>();
    for (let lhs = 0; lhs < evaluations.length; lhs += 1) {
      if (evaluations[lhs].decision === "rejected") continue;
      for (let rhs = lhs + 1; rhs < evaluations.length; rhs += 1) {
        if (evaluations[rhs].decision === "rejected") continue;
        const lhsFiles = new Set(evaluations[lhs].module.files);
        const rhsFiles = new Set(evaluations[rhs].module.files);
        if (lhsFiles.size === 0 || rhsFiles.size === 0) continue;
        const intersectionCount = [...lhsFiles].filter((f) => rhsFiles.has(f)).length;
        const overlap = intersectionCount / Math.min(lhsFiles.size, rhsFiles.size);
        if (overlap < this.options.duplicateOverlapThreshold) continue;
        duplicates.add(this.duplicateLoserIndex(lhs, rhs, evaluations));
      }
    }
    return duplicates;
  }

  private duplicateLoserIndex(lhsIndex: number, rhsIndex: number, evaluations: QualityGateEvaluation[]): number {
    const lhs = evaluations[lhsIndex].module;
    const rhs = evaluations[rhsIndex].module;
    if (lhs.confidence !== rhs.confidence) return lhs.confidence < rhs.confidence ? lhsIndex : rhsIndex;
    if (lhs.files.length !== rhs.files.length) return lhs.files.length < rhs.files.length ? lhsIndex : rhsIndex;
    return lhs.name.localeCompare(rhs.name, undefined, { numeric: true }) < 0 ? rhsIndex : lhsIndex;
  }
}

function classify(path: string, contents: string): ModuleFileKind {
  const lowercasedPath = path.toLowerCase();
  const components = lowercasedPath.split("/").filter((c) => c.length > 0);
  const filename = components.at(-1) ?? lowercasedPath;
  const normalizedContents = contents.toLowerCase();

  if (
    components.includes("generated") ||
    filename.includes("generated") ||
    normalizedContents.includes("@generated") ||
    normalizedContents.includes("code generated") ||
    normalizedContents.includes("auto-generated") ||
    normalizedContents.includes("do not edit")
  ) {
    return "generated";
  }
  if (
    components.includes("config") ||
    filename === "config.ts" ||
    filename === "config.js" ||
    filename === "settings.py" ||
    filename === "env.ts" ||
    filename === "env.js"
  ) {
    return "config";
  }
  if (
    components.includes("utils") ||
    components.includes("util") ||
    filename.includes("util") ||
    filename.includes("helper") ||
    filename === "format.ts" ||
    filename === "format.js"
  ) {
    return "utility";
  }
  if (isTypeFile(lowercasedPath, contents)) return "typeOnly";
  return "source";
}

function isTypeFile(path: string, contents: string): boolean {
  const components = path.split("/").filter((c) => c.length > 0);
  const filename = components.at(-1) ?? path;
  if (filename.startsWith("types.") || filename.endsWith(".d.ts") || components.includes("types")) {
    return true;
  }
  const meaningfulLines = contents
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0 && !l.startsWith("//") && !l.startsWith("/*") && !l.startsWith("*"));
  if (meaningfulLines.length === 0) return false;
  return meaningfulLines.every(
    (line) =>
      line.startsWith("import ") ||
      line.startsWith("export type ") ||
      line.startsWith("export interface ") ||
      line.startsWith("export enum ") ||
      line.startsWith("type ") ||
      line.startsWith("interface ") ||
      line.startsWith("enum ") ||
      line === "}" ||
      line === "};",
  );
}
