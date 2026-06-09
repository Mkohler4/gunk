// The decomposition pipeline orchestrator. Ported from
// app/Sources/GunkApp/Decompose/DecompositionPipeline.swift, with the trace
// observer and NDJSON event emission woven through every stage.

import type { Database } from "bun:sqlite";
import { homedir } from "node:os";
import { join } from "node:path";

import {
  addGunkFile,
  addGunkTag,
  addSourceFile,
  filesForSource,
  gunkById,
  insertGunk,
  listTags,
  recordLLMRun,
  type Gunk,
  type Source,
} from "../store/index.js";
import { clamp, type FileSymbols, type Module } from "../models.js";
import {
  NullEventSink,
  type EventSink,
  type PipelineStage,
} from "../contract/events.js";
import {
  NoopObserver,
  type DecompositionObserver,
  type StageRecord,
} from "../trace/trace.js";
import { TracingLLMClient, type LLMClient } from "../llm/client.js";
import type { EmbeddingProvider } from "../llm/embeddings.js";
import { EmbeddingIndex } from "../search/embeddingIndex.js";
import { Extractor } from "../extract/extractor.js";
import { BuildVerifier } from "../extract/buildVerify.js";

import { scanFolder } from "../ingest/scanner.js";
import { ContextBuilder } from "../ingest/contextBuilder.js";
import { dartPackageNameFromManifests, ImportResolver } from "../analyze/importResolver.js";
import { CodeGraphBuilder } from "../analyze/codeGraph.js";
import { DependencyManifestParser } from "../analyze/dependencyManifest.js";
import { CapabilityFingerprintBuilder } from "../analyze/capabilityFingerprint.js";
import { createTreeSitterSymbolExtractor, type SymbolExtractor } from "../analyze/symbolExtractor.js";

import { survey } from "./survey.js";
import { CapabilityExpander } from "./expander.js";
import { CapabilityRefiner } from "./refiner.js";
import { ModuleQualityGate } from "./qualityGate.js";
import { verifySelfContainment } from "./selfContainment.js";
import { dedupe } from "./dedupe.js";
import { readFileSync } from "node:fs";
import { basename } from "node:path";

export interface PipelineOptions {
  contextBudgetTokens?: number;
  confidenceThreshold?: number;
  gunkHome?: string;
  symbolExtractor?: SymbolExtractor;
  embeddingProvider?: EmbeddingProvider | null;
  observer?: DecompositionObserver;
  eventSink?: EventSink;
  verifyBuild?: boolean;
  now?: () => number;
}

export interface PipelineResult {
  gunkIds: number[];
  accepted: number;
  needsApproval: number;
  rejected: number;
}

const MANIFEST_BASENAMES = [
  "package.json",
  "package.swift",
  "pyproject.toml",
  "requirements.txt",
  "go.mod",
  "cargo.toml",
  "pubspec.yaml",
  "build.gradle",
  "build.gradle.kts",
];

export class DecompositionPipeline {
  private readonly contextBudgetTokens: number;
  private readonly confidenceThreshold: number;
  private readonly gunkHome: string;
  private readonly observer: DecompositionObserver;
  private readonly events: EventSink;
  private readonly verifyBuild: boolean;
  private readonly now: () => number;
  private readonly embeddingProvider: EmbeddingProvider | null;
  private readonly symbolExtractorOverride: SymbolExtractor | null;

  constructor(
    private readonly db: Database,
    private readonly provider: string,
    private readonly model: string,
    options: PipelineOptions = {},
  ) {
    this.contextBudgetTokens = options.contextBudgetTokens ?? 20_000;
    this.confidenceThreshold = options.confidenceThreshold ?? 0.7;
    this.gunkHome = options.gunkHome ?? join(homedir(), ".gunk");
    this.observer = options.observer ?? new NoopObserver();
    this.events = options.eventSink ?? new NullEventSink();
    this.verifyBuild = options.verifyBuild ?? false;
    this.now = options.now ?? Date.now;
    this.embeddingProvider = options.embeddingProvider ?? null;
    this.symbolExtractorOverride = options.symbolExtractor ?? null;
  }

  async run(source: Source, client: LLMClient): Promise<PipelineResult> {
    const symbolExtractor =
      this.symbolExtractorOverride ?? (await createTreeSitterSymbolExtractor());
    const sourceRoot = source.path;
    const tracing = new TracingLLMClient(client, this.observer, this.now);

    // 1. scan
    const scannedFiles = await this.stage("scan", 0.1, () => {
      const files = scanFolder(sourceRoot);
      for (const file of files) addSourceFile(this.db, source.id, file.relpath, file.size);
      return { value: files, counts: { files: files.length } };
    });

    // 2. symbols
    const contentsByPath: Record<string, string> = {};
    for (const file of scannedFiles) {
      try {
        contentsByPath[file.relpath] = readFileSync(file.absPath, "utf8");
      } catch {
        contentsByPath[file.relpath] = "";
      }
    }
    const fileSymbols = await this.stage("symbols", 0.2, () => {
      const symbols: FileSymbols[] = scannedFiles.map((file) =>
        symbolExtractor.extract({ path: file.relpath, contents: contentsByPath[file.relpath] ?? "" }),
      );
      return {
        value: symbols,
        counts: {
          files: symbols.length,
          parsedFiles: symbols.filter((file) => !file.viaFallback).length,
          fallbackFiles: symbols.filter((file) => file.viaFallback).length,
          realSymbolFiles: symbols.filter((file) => !file.viaFallback && file.symbols.length > 0).length,
        },
      };
    });

    // 3. graph
    const manifestContents = this.manifestContents(contentsByPath);
    const resolver = new ImportResolver({
      sourceFiles: new Set(scannedFiles.map((f) => f.relpath)),
      dartPackageName: dartPackageNameFromManifests(manifestContents),
    });
    const graph = await this.stage("graph", 0.3, () => {
      const built = new CodeGraphBuilder(resolver).build(fileSymbols, contentsByPath);
      return { value: built, counts: { nodes: built.nodes.length, edges: built.edges.length } };
    });

    // 4. fingerprints
    const manifestParser = new DependencyManifestParser();
    const fingerprintBuilder = new CapabilityFingerprintBuilder();
    const fingerprints = await this.stage("fingerprints", 0.38, () => {
      const manifests = manifestParser.parse(manifestContents);
      const fps = fingerprintBuilder.fingerprints(fileSymbols, manifests, contentsByPath);
      return { value: fps, counts: { fingerprints: fps.length } };
    });

    // 5. repoMap
    const repoMapContext = await this.stage("repoMap", 0.48, () => {
      const builder = new ContextBuilder(symbolExtractor, manifestParser, fingerprintBuilder);
      const map = builder.buildRepoMap(scannedFiles);
      const serialized = builder.serialize(map, this.contextBudgetTokens);
      const chunks = builder.serializeChunks(map, this.contextBudgetTokens);
      return {
        value: { serialized, chunks },
        counts: {
          chars: serialized.length,
          chunks: chunks.length,
          chunkChars: chunks.reduce((sum, chunk) => sum + chunk.length, 0),
        },
      };
    });

    // 6. survey
    const knownFiles = scannedFiles.map((f) => f.relpath);
    tracing.stage = "survey";
    const hypotheses = await this.stage("survey", 0.58, async () => {
      const result = await survey(
        tracing,
        {
          model: this.model,
          sourceName: source.name,
          repoMap: repoMapContext.serialized,
          repoMapChunks: repoMapContext.chunks,
          knownFiles,
        },
        { recordRun: (r) => this.recordRun(source.id, r) },
      );
      this.observer.recordedHypotheses(result);
      return { value: result, counts: { hypotheses: result.length } };
    });

    // 7. expansion
    const expansions = await this.stage("expansion", 0.66, () => {
      const result = new CapabilityExpander().expand(hypotheses, graph);
      this.observer.recordedExpansions(result);
      return { value: result, counts: { expansions: result.length } };
    });

    // 8. refine
    const allowedTags = listTags(this.db).map((t) => t.name);
    tracing.stage = "refine";
    const modules = await this.stage("refine", 0.78, async () => {
      const refiner = new CapabilityRefiner({
        recordRun: (r) => this.recordRun(source.id, r),
        onRefinement: (record) => this.observer.recordedRefinement(record),
      });
      const result = await refiner.refine(tracing, {
        model: this.model,
        sourceName: source.name,
        expansions,
        contentsByPath,
        allowedTags,
      });
      return { value: result, counts: { modules: result.length } };
    });

    // 9. quality gates
    const persistable = await this.stage("qualityGates", 0.84, () => {
      const selfContainmentResults = modules.map((module) => {
        const filePaths = new Set(module.files);
        const aggregate = fingerprintBuilder.aggregate(fingerprints, filePaths);
        return verifySelfContainment({
          module,
          graph,
          files: fileSymbols,
          declaredExternalDependencies: aggregate.importedDependencies,
        });
      });
      this.observer.recordedSelfContainment(selfContainmentResults);
      const evaluations = new ModuleQualityGate({
        confidenceThreshold: this.confidenceThreshold,
        cohesionThreshold: 0.35,
        duplicateOverlapThreshold: 0.85,
      }).evaluate(modules, fingerprints, graph, contentsByPath, selfContainmentResults);
      this.observer.recordedGateEvaluations(evaluations);
      const keep = evaluations.filter((e) => e.decision === "accepted" || e.decision === "needsApproval");
      return {
        value: { evaluations, keep },
        counts: {
          accepted: evaluations.filter((e) => e.decision === "accepted").length,
          needsApproval: evaluations.filter((e) => e.decision === "needsApproval").length,
          rejected: evaluations.filter((e) => e.decision === "rejected").length,
        },
      };
    });

    // 10. persist
    const persisted = await this.stage("persist", 0.92, () => {
      const rows = this.persist(persistable.keep, source);
      return { value: rows, counts: { persisted: rows.length } };
    });

    // 11. extract
    const gunks = await this.stage("extract", 1, async () => {
      const result = await this.extractAccepted(persisted);
      return { value: result, counts: { extracted: result.length } };
    });
    if (this.verifyBuild) {
      this.observer.recordedBuildVerification(
        new BuildVerifier().verifyGunks(gunks),
      );
    }

    const accepted = persistable.evaluations.filter((e) => e.decision === "accepted").length;
    const needsApproval = persistable.evaluations.filter((e) => e.decision === "needsApproval").length;
    const rejected = persistable.evaluations.filter((e) => e.decision === "rejected").length;

    return { gunkIds: gunks.map((g) => g.id), accepted, needsApproval, rejected };
  }

  private async stage<T>(
    stage: PipelineStage,
    fraction: number,
    fn: () => { value: T; counts: Record<string, number> } | Promise<{ value: T; counts: Record<string, number> }>,
  ): Promise<T> {
    this.observer.stageStarted(stage);
    this.events.emit({ type: "stage", stage, phase: "started" });
    const startedAtMs = this.now();
    try {
      const { value, counts } = await fn();
      const finishedAtMs = this.now();
      const record: StageRecord = {
        stage,
        startedAtMs,
        finishedAtMs,
        durationMs: finishedAtMs - startedAtMs,
        counts,
        status: "ok",
      };
      this.observer.stageFinished(record);
      this.events.emit({ type: "stage", stage, phase: "finished", durationMs: record.durationMs, counts });
      this.events.emit({
        type: "progress",
        stage,
        fraction: clamp(fraction, 0, 1),
        modulesFound: counts.modules ?? counts.persisted ?? counts.extracted ?? null,
      });
      return value;
    } catch (error) {
      const finishedAtMs = this.now();
      const message = error instanceof Error ? error.message : String(error);
      this.observer.stageFinished({
        stage,
        startedAtMs,
        finishedAtMs,
        durationMs: finishedAtMs - startedAtMs,
        counts: {},
        status: "error",
        error: message,
      });
      throw error;
    }
  }

  private manifestContents(contentsByPath: Record<string, string>): Record<string, string> {
    const manifests: Record<string, string> = {};
    for (const [path, contents] of Object.entries(contentsByPath)) {
      if (MANIFEST_BASENAMES.includes(basename(path).toLowerCase())) {
        manifests[path] = contents;
      }
    }
    return manifests;
  }

  private recordRun(
    sourceId: number,
    run: { inputTokens: number | null; outputTokens: number | null; startedAt: number; finishedAt: number },
  ): void {
    recordLLMRun(this.db, {
      sourceId,
      provider: this.provider,
      model: this.model,
      inputTokens: run.inputTokens,
      outputTokens: run.outputTokens,
      startedAt: run.startedAt,
      finishedAt: run.finishedAt,
    });
  }

  private persist(
    evaluations: { module: Module; decision: string }[],
    source: Source,
  ): { gunk: Gunk; decision: string }[] {
    const sourceFileByPath = new Map(filesForSource(this.db, source.id).map((f) => [f.relpath, f]));
    const tagByName = new Map(listTags(this.db).map((t) => [t.name, t]));
    const persisted: { gunk: Gunk; decision: string }[] = [];

    for (const evaluation of evaluations) {
      const module = evaluation.module;
      const gunk = insertGunk(this.db, {
        sourceId: source.id,
        name: module.name,
        purpose: module.purpose,
        language: module.language,
        confidence: module.confidence,
      });
      for (const tagName of module.tags) {
        const tag = tagByName.get(tagName);
        if (tag) addGunkTag(this.db, gunk.id, tag.id, module.confidence);
      }
      const seen = new Set<string>();
      for (const relpath of module.files) {
        if (seen.has(relpath)) continue;
        seen.add(relpath);
        addGunkFile(this.db, gunk.id, relpath, sourceFileByPath.get(relpath)?.size ?? null);
      }
      persisted.push({ gunk, decision: evaluation.decision });
    }
    return persisted;
  }

  private async extractAccepted(persisted: { gunk: Gunk; decision: string }[]): Promise<Gunk[]> {
    const extractor = new Extractor(this.db, {
      gunkHome: this.gunkHome,
      confidenceThreshold: this.confidenceThreshold,
      now: this.now,
    });
    const index = this.embeddingProvider ? new EmbeddingIndex(this.db, this.embeddingProvider) : null;
    const gunks: Gunk[] = [];

    for (const { gunk, decision } of persisted) {
      if (decision === "accepted") {
        extractor.extract(gunk);
        const extracted = gunkById(this.db, gunk.id) ?? gunk;
        if (index) {
          try {
            await index.index(extracted);
            dedupe(this.db, extracted);
          } catch {
            // embeddings are best-effort; never fail the run on them
          }
        }
        gunks.push(extracted);
      } else {
        gunks.push(gunk);
      }
    }
    return gunks;
  }
}
