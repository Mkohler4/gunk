import { Database } from "bun:sqlite";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import {
  filesForGunk,
  gunksForSource,
  insertSource,
  listGunkTags,
  runMigrations,
} from "../src/store/index.js";
import { scanFolder } from "../src/ingest/scanner.js";
import { DecompositionPipeline } from "../src/decompose/pipeline.js";
import { createTreeSitterSymbolExtractor } from "../src/analyze/symbolExtractor.js";
import {
  assertSignalFloor,
  loadExpected,
  score,
  signalMetrics,
} from "../src/eval/scorecard.js";
import { ReplayClient } from "../src/eval/replayClient.js";
import { formatEvalReport, runEval } from "../src/eval/runEval.js";
import type { Module } from "../src/models.js";
import type { LLMClient, LLMRequest, LLMResponse } from "../src/llm/client.js";
import { RunTraceRecorder } from "../src/trace/trace.js";

const fixturesDir = join(dirname(fileURLToPath(import.meta.url)), "fixtures");
const multiLanguageFixtures = [
  "flutter-app",
  "kotlin-android",
  "java-service",
  "mixed-monorepo",
  "large-repo",
];

class QueuedClient implements LLMClient {
  readonly provider = "OpenAI" as const;
  constructor(private readonly responses: unknown[]) {}
  async complete(): Promise<LLMResponse> {
    const json = this.responses.shift();
    return { json, usage: { inputTokens: null, outputTokens: null } };
  }
}

function surveyJSON(hypotheses: unknown[]) {
  return { hypotheses };
}

function hypothesisJSON(
  name: string,
  anchors: string[],
  seedFiles: string[],
  expectedCollaborators: string[],
) {
  return {
    name,
    rationale: `${name} is anchored by route, service, config, and type collaborators.`,
    anchors,
    seedFiles,
    expectedCollaborators,
    granularity: "feature",
  };
}

function refinementJSON(args: {
  name: string;
  purpose: string;
  tags: string[];
  language?: string;
  ownedFiles: string[];
  sharedDependencies: string[];
  entrypoints: { path: string; symbol: string }[];
  anchors: string[];
}) {
  return {
    module: {
      name: args.name,
      purpose: args.purpose,
      tags: args.tags,
      language: args.language ?? "TypeScript",
      ownedFiles: args.ownedFiles,
      sharedDependencies: args.sharedDependencies,
      entrypoints: args.entrypoints,
      anchors: args.anchors,
      confidence: 0.92,
    },
    qualityGateHints: {
      externalFacingCapability: true,
      multiFileCohesion: true,
      anchorPresent: true,
      rightGranularity: true,
    },
    reject: null,
  };
}

class LargeRepoMapReduceClient implements LLMClient {
  readonly provider = "OpenAI" as const;

  async complete(request: LLMRequest): Promise<LLMResponse> {
    const prompt = request.messages.map((message) => message.content).join("\n");
    if (request.jsonSchemaName === "CapabilitySurvey") {
      const repoMap = prompt.split("Structural repo map:\n").at(-1) ?? prompt;
      const hypotheses = [];
      if (
        repoMap.includes("src/main/java/com/gunk/identity/LoginController.java") &&
        repoMap.includes("src/main/java/com/gunk/identity/LoginService.java") &&
        repoMap.includes("src/main/java/com/gunk/identity/SessionTokenStore.java")
      ) {
        hypotheses.push(
          hypothesisJSON(
            "Session token login",
            ["LoginController", "SessionTokenStore"],
            [
              "src/main/java/com/gunk/identity/LoginController.java",
              "src/main/java/com/gunk/identity/LoginService.java",
              "src/main/java/com/gunk/identity/SessionTokenStore.java",
            ],
            [],
          ),
        );
      }
      if (
        repoMap.includes("src/main/java/com/gunk/billing/InvoiceController.java") &&
        repoMap.includes("src/main/java/com/gunk/billing/InvoiceService.java") &&
        repoMap.includes("src/main/java/com/gunk/billing/TaxCalculator.java")
      ) {
        hypotheses.push(
          hypothesisJSON(
            "Invoice generation",
            ["InvoiceController", "TaxCalculator"],
            [
              "src/main/java/com/gunk/billing/InvoiceController.java",
              "src/main/java/com/gunk/billing/InvoiceService.java",
              "src/main/java/com/gunk/billing/TaxCalculator.java",
            ],
            [],
          ),
        );
      }
      return { json: surveyJSON(hypotheses), usage: { inputTokens: null, outputTokens: null } };
    }

    if (prompt.includes("name: Session token login")) {
      return {
        json: refinementJSON({
          name: "Session token login",
          purpose: "Issues session tokens for email login requests.",
          tags: ["auth", "api"],
          language: "Java",
          ownedFiles: [
            "src/main/java/com/gunk/identity/LoginController.java",
            "src/main/java/com/gunk/identity/LoginService.java",
            "src/main/java/com/gunk/identity/SessionTokenStore.java",
          ],
          sharedDependencies: [],
          entrypoints: [{ path: "src/main/java/com/gunk/identity/LoginController.java", symbol: "LoginController" }],
          anchors: ["LoginController", "SessionTokenStore"],
        }),
        usage: { inputTokens: null, outputTokens: null },
      };
    }

    return {
      json: refinementJSON({
        name: "Invoice generation",
        purpose: "Creates invoices and calculates tax totals.",
        tags: ["payments", "api"],
        language: "Java",
        ownedFiles: [
          "src/main/java/com/gunk/billing/InvoiceController.java",
          "src/main/java/com/gunk/billing/InvoiceService.java",
          "src/main/java/com/gunk/billing/TaxCalculator.java",
        ],
        sharedDependencies: [],
        entrypoints: [{ path: "src/main/java/com/gunk/billing/InvoiceController.java", symbol: "InvoiceController" }],
        anchors: ["InvoiceController", "TaxCalculator"],
      }),
      usage: { inputTokens: null, outputTokens: null },
    };
  }
}

function responsesFor(fixture: string): unknown[] {
  if (fixture === "express-saas") {
    return [
      surveyJSON([
        hypothesisJSON(
          "Google OAuth login",
          ["google-auth-library", "GOOGLE_CLIENT_ID"],
          ["src/routes/auth.ts"],
          [
            "src/services/googleOAuth.ts",
            "src/config/auth.ts",
            "src/types/auth.ts",
          ],
        ),
        hypothesisJSON(
          "Stripe subscription billing",
          ["stripe", "STRIPE_SECRET_KEY"],
          ["src/routes/billing.ts"],
          [
            "src/services/stripeBilling.ts",
            "src/config/stripe.ts",
            "src/types/billing.ts",
          ],
        ),
      ]),
      refinementJSON({
        name: "Google OAuth login",
        purpose: "Authenticates users with Google OAuth and creates a session.",
        tags: ["auth", "api"],
        ownedFiles: ["src/routes/auth.ts", "src/services/googleOAuth.ts"],
        sharedDependencies: ["src/config/auth.ts", "src/types/auth.ts"],
        entrypoints: [{ path: "src/routes/auth.ts", symbol: "authCallback" }],
        anchors: ["google-auth-library", "GOOGLE_CLIENT_ID"],
      }),
      refinementJSON({
        name: "Stripe subscription billing",
        purpose: "Creates Stripe subscription checkout sessions.",
        tags: ["payments", "api"],
        ownedFiles: ["src/routes/billing.ts", "src/services/stripeBilling.ts"],
        sharedDependencies: ["src/config/stripe.ts", "src/types/billing.ts"],
        entrypoints: [
          { path: "src/routes/billing.ts", symbol: "billingCheckout" },
        ],
        anchors: ["stripe", "STRIPE_SECRET_KEY"],
      }),
    ];
  }
  return [
    surveyJSON([
      hypothesisJSON(
        "S3 image upload",
        ["@aws-sdk/client-s3", "S3_BUCKET", "AWS_REGION"],
        ["app/api/upload/route.ts"],
        [
          "src/services/s3Upload.ts",
          "src/config/storage.ts",
          "src/types/upload.ts",
        ],
      ),
      hypothesisJSON(
        "Email invite sending",
        ["nodemailer", "SMTP_URL"],
        ["app/api/invites/route.ts"],
        [
          "src/services/emailInvite.ts",
          "src/config/mail.ts",
          "src/types/invite.ts",
        ],
      ),
    ]),
    refinementJSON({
      name: "S3 image upload",
      purpose: "Uploads image blobs to S3 and returns bucket/key metadata.",
      tags: ["api"],
      ownedFiles: ["app/api/upload/route.ts", "src/services/s3Upload.ts"],
      sharedDependencies: ["src/config/storage.ts", "src/types/upload.ts"],
      entrypoints: [{ path: "app/api/upload/route.ts", symbol: "POST" }],
      anchors: ["@aws-sdk/client-s3", "S3_BUCKET", "AWS_REGION"],
    }),
    refinementJSON({
      name: "Email invite sending",
      purpose: "Sends invite emails through an SMTP transport.",
      tags: ["email", "api"],
      ownedFiles: ["app/api/invites/route.ts", "src/services/emailInvite.ts"],
      sharedDependencies: ["src/config/mail.ts", "src/types/invite.ts"],
      entrypoints: [{ path: "app/api/invites/route.ts", symbol: "POST" }],
      anchors: ["nodemailer", "SMTP_URL"],
    }),
  ];
}

describe("eval gate: capability-centric pipeline beats baseline", () => {
  let db: Database;
  let gunkHome: string;
  let extractor: Awaited<ReturnType<typeof createTreeSitterSymbolExtractor>>;

  beforeEach(async () => {
    db = new Database(":memory:");
    db.exec("PRAGMA foreign_keys = ON;");
    runMigrations(db);
    gunkHome = mkdtempSync(join(tmpdir(), "gunk-eval-home-"));
    extractor = await createTreeSitterSymbolExtractor();
  });

  afterEach(() => {
    db.close();
    rmSync(gunkHome, { recursive: true, force: true });
  });

  async function runFixture(fixture: string) {
    const fixturePath = join(fixturesDir, fixture);
    const source = insertSource(db, fixture, fixturePath, 100);
    const pipeline = new DecompositionPipeline(
      db,
      "OpenAI",
      "phase-4-eval-fixture",
      {
        contextBudgetTokens: 4000,
        confidenceThreshold: 0.7,
        gunkHome,
        symbolExtractor: extractor,
        embeddingProvider: null,
        now: () => 100,
      },
    );
    await pipeline.run(source, new QueuedClient(responsesFor(fixture)));

    const modules: Module[] = gunksForSource(db, source.id).map((gunk) => ({
      name: gunk.name,
      purpose: gunk.purpose,
      tags: listGunkTags(db, gunk.id).map((t) => t.tag),
      files: filesForGunk(db, gunk.id).map((f) => f.relpath),
      language: gunk.language,
      confidence: gunk.confidence ?? 0,
      ownedFiles: [],
      sharedDeps: [],
      surface: [],
      anchors: [],
    }));
    const expected = loadExpected(
      JSON.parse(readFileSync(join(fixturePath, "expected.json"), "utf8")),
    );
    return score(modules, expected);
  }

  it("express-saas: perfect precision/recall, zero trap false positives", async () => {
    const card = await runFixture("express-saas");
    expect(card.filePrecision).toBeCloseTo(1, 5);
    expect(card.fileRecall).toBeCloseTo(1, 5);
    expect(card.tagAccuracy).toBeCloseTo(1, 5);
    expect(card.moduleCountDelta).toBe(0);
    expect(card.trivialModuleFalsePositiveCount).toBe(0);
    expect(card.trivialModuleFalsePositiveRate).toBeCloseTo(0, 5);
  });

  it("next-media: perfect precision/recall, zero trap false positives", async () => {
    const card = await runFixture("next-media");
    expect(card.filePrecision).toBeCloseTo(1, 5);
    expect(card.fileRecall).toBeCloseTo(1, 5);
    expect(card.tagAccuracy).toBeCloseTo(1, 5);
    expect(card.moduleCountDelta).toBe(0);
    expect(card.trivialModuleFalsePositiveCount).toBe(0);
    expect(card.trivialModuleFalsePositiveRate).toBeCloseTo(0, 5);
  });
});

describe("eval fixtures: multi-language labels and scanner smoke", () => {
  it("loads each new expected.json without error", () => {
    for (const fixture of multiLanguageFixtures) {
      const fixturePath = join(fixturesDir, fixture);
      const expected = loadExpected(
        JSON.parse(readFileSync(join(fixturePath, "expected.json"), "utf8")),
      );

      expect(expected.modules.length, fixture).toBeGreaterThanOrEqual(2);
      expect(expected.mustNotBeModules.length, fixture).toBeGreaterThanOrEqual(
        1,
      );
    }
  });

  it("scans each new fixture to a non-empty file list", () => {
    for (const fixture of multiLanguageFixtures) {
      const fixturePath = join(fixturesDir, fixture);
      const files = scanFolder(fixturePath);
      const relpaths = new Set(files.map((file) => file.relpath));
      const expected = loadExpected(
        JSON.parse(readFileSync(join(fixturePath, "expected.json"), "utf8")),
      );

      expect(files.length, fixture).toBeGreaterThan(0);
      for (const module of expected.modules) {
        for (const file of module.files) {
          expect(relpaths.has(file), `${fixture}: ${file}`).toBe(true);
        }
      }
    }
  });

  it("keeps the large fixture above the default repo-map budget", () => {
    const files = scanFolder(join(fixturesDir, "large-repo"));
    const totalBytes = files.reduce((sum, file) => sum + file.size, 0);

    expect(totalBytes).toBeGreaterThan(80_000);
  });

  it("honors the Flutter fixture ignore rules", () => {
    const files = scanFolder(join(fixturesDir, "flutter-app"));
    const relpaths = files.map((file) => file.relpath);

    expect(relpaths.some((file) => file.startsWith(".dart_tool/"))).toBe(false);
    expect(relpaths.some((file) => file.startsWith(".gradle/"))).toBe(false);
    expect(relpaths.some((file) => file.startsWith("build/"))).toBe(false);
  });
});

describe("eval signal metrics: Flutter Dart coverage", () => {
  let db: Database;
  let gunkHome: string;
  let runsDir: string;
  let extractor: Awaited<ReturnType<typeof createTreeSitterSymbolExtractor>>;

  beforeEach(async () => {
    db = new Database(":memory:");
    db.exec("PRAGMA foreign_keys = ON;");
    runMigrations(db);
    gunkHome = mkdtempSync(join(tmpdir(), "gunk-eval-home-"));
    runsDir = mkdtempSync(join(tmpdir(), "gunk-runs-"));
    extractor = await createTreeSitterSymbolExtractor();
  });

  afterEach(() => {
    db.close();
    rmSync(gunkHome, { recursive: true, force: true });
    rmSync(runsDir, { recursive: true, force: true });
  });

  it("reports real Dart parse coverage for flutter-app", async () => {
    const fixturePath = join(fixturesDir, "flutter-app");
    const source = insertSource(db, "flutter-app", fixturePath, 100);
    const observer = new RunTraceRecorder(
      {
        runId: "flutter-signal",
        sourceId: source.id,
        sourceName: source.name,
        provider: "OpenAI",
        model: "phase-5-signal",
      },
      { runsDir, now: () => 100 },
    );
    const pipeline = new DecompositionPipeline(db, "OpenAI", "phase-5-signal", {
      contextBudgetTokens: 4000,
      confidenceThreshold: 0.7,
      gunkHome,
      symbolExtractor: extractor,
      embeddingProvider: null,
      observer,
      now: () => 100,
    });

    await pipeline.run(source, new QueuedClient([surveyJSON([])]));
    const metrics = signalMetrics(observer.current);

    expect(metrics.parseCoverage).toBeGreaterThan(0.6);
    expect(metrics.realSymbolFiles).toBeGreaterThanOrEqual(9);
    expect(metrics.fallbackFiles).toBeGreaterThan(0);
    expect(() => assertSignalFloor(metrics, { minParseCoverage: 0.6 })).not.toThrow();
  });
});

describe("large-repo map-reduce survey", () => {
  let db: Database;
  let gunkHome: string;
  let runsDir: string;
  let extractor: Awaited<ReturnType<typeof createTreeSitterSymbolExtractor>>;

  beforeEach(async () => {
    db = new Database(":memory:");
    db.exec("PRAGMA foreign_keys = ON;");
    runMigrations(db);
    gunkHome = mkdtempSync(join(tmpdir(), "gunk-eval-home-"));
    runsDir = mkdtempSync(join(tmpdir(), "gunk-runs-"));
    extractor = await createTreeSitterSymbolExtractor();
  });

  afterEach(() => {
    db.close();
    rmSync(gunkHome, { recursive: true, force: true });
    rmSync(runsDir, { recursive: true, force: true });
  });

  it("large-repo capabilities survive chunked survey without silent truncation", async () => {
    const fixturePath = join(fixturesDir, "large-repo");
    const source = insertSource(db, "large-repo", fixturePath, 100);
    const observer = new RunTraceRecorder(
      {
        runId: "large-map-reduce",
        sourceId: source.id,
        sourceName: source.name,
        provider: "OpenAI",
        model: "phase-5-map-reduce",
      },
      { runsDir, now: () => 100 },
    );
    const pipeline = new DecompositionPipeline(db, "OpenAI", "phase-5-map-reduce", {
      contextBudgetTokens: 4000,
      confidenceThreshold: 0.7,
      gunkHome,
      symbolExtractor: extractor,
      embeddingProvider: null,
      observer,
      now: () => 100,
    });

    await pipeline.run(source, new LargeRepoMapReduceClient());

    const modules: Module[] = gunksForSource(db, source.id).map((gunk) => ({
      name: gunk.name,
      purpose: gunk.purpose,
      tags: listGunkTags(db, gunk.id).map((t) => t.tag),
      files: filesForGunk(db, gunk.id).map((f) => f.relpath),
      language: gunk.language,
      confidence: gunk.confidence ?? 0,
      ownedFiles: [],
      sharedDeps: [],
      surface: [],
      anchors: [],
    }));
    const expected = loadExpected(JSON.parse(readFileSync(join(fixturePath, "expected.json"), "utf8")));
    const card = score(modules, expected);
    const metrics = signalMetrics(observer.current);
    const repoMapStage = observer.current.stages.find((stage) => stage.stage === "repoMap");

    expect(repoMapStage?.counts.chunks).toBeGreaterThan(1);
    expect(metrics.surveyHypothesisCount).toBe(2);
    expect(card.actualModuleCount).toBe(2);
    expect(card.filePrecision).toBeCloseTo(1, 5);
    expect(card.fileRecall).toBeCloseTo(1, 5);
    expect(card.trivialModuleFalsePositiveCount).toBe(0);
  });
});

describe("offline replay eval harness", () => {
  it("replays recorded LLM calls deterministically", async () => {
    const report = await runEval({
      fixturesDir,
      fixtureNames: ["express-saas"],
    });
    const fixture = report.fixtures[0];

    expect(report.passed).toBe(true);
    expect(fixture?.scorecard.filePrecision).toBeCloseTo(1, 5);
    expect(fixture?.scorecard.fileRecall).toBeCloseTo(1, 5);
    expect(fixture?.scorecard.trivialModuleFalsePositiveCount).toBe(0);
  });

  it("stale replay tape fails loudly", async () => {
    const replay = ReplayClient.fromFile(
      join(fixturesDir, "express-saas", "recorded-trace.json"),
    );

    await expect(
      replay.complete({
        model: "phase-5-replay-fixture",
        messages: [{ role: "user", content: "stale prompt" }],
        jsonSchemaName: "survey",
        jsonSchema: {},
      }),
    ).rejects.toThrow(/Replay tape stale/);
  });

  it("eval report holds express-saas and next-media at the Phase 4 baseline", async () => {
    const report = await runEval({
      fixturesDir,
      fixtureNames: ["express-saas", "next-media"],
    });

    expect(report.passed).toBe(true);
    for (const fixture of report.fixtures) {
      expect(fixture.scorecard.filePrecision, fixture.name).toBeCloseTo(1, 5);
      expect(fixture.scorecard.fileRecall, fixture.name).toBeCloseTo(1, 5);
      expect(fixture.scorecard.tagAccuracy, fixture.name).toBeCloseTo(1, 5);
      expect(
        fixture.scorecard.trivialModuleFalsePositiveCount,
        fixture.name,
      ).toBe(0);
      expect(fixture.signalMetrics.selfContainmentVerifiedCount, fixture.name).toBe(
        fixture.scorecard.actualModuleCount,
      );
      expect(fixture.signalMetrics.selfContainmentPassRate, fixture.name).toBeCloseTo(1, 5);
    }
  });

  it("eval report includes proxy agreement per fixture", async () => {
    const report = await runEval({
      fixturesDir,
      fixtureNames: ["express-saas"],
    });
    const fixture = report.fixtures[0];
    const formatted = formatEvalReport(report);

    expect(report.passed).toBe(true);
    expect(fixture?.signalMetrics.proxyAgreement.cohesion.evaluated).toBeGreaterThan(0);
    expect(formatted).toContain("proxy_cohesion_agreement:");
    expect(formatted).toContain("proxy_surface_agreement:");
    expect(formatted).toContain("proxy_classification_agreement:");
  });

  it("flutter-app replay accepts mobile capabilities without trap false positives", async () => {
    const report = await runEval({
      fixturesDir,
      fixtureNames: ["flutter-app"],
    });
    const fixture = report.fixtures[0];

    expect(report.passed).toBe(true);
    expect(fixture?.scorecard.actualModuleCount).toBeGreaterThanOrEqual(2);
    expect(fixture?.scorecard.fileRecall).toBeGreaterThanOrEqual(0.8);
    expect(fixture?.scorecard.trivialModuleFalsePositiveCount).toBe(0);
    expect(fixture?.signalMetrics.surveyHypothesisCount).toBeGreaterThanOrEqual(2);
    expect(fixture?.signalMetrics.selfContainmentVerifiedCount).toBe(
      fixture?.scorecard.actualModuleCount,
    );
    expect(fixture?.signalMetrics.selfContainmentPassRate).toBeCloseTo(1, 5);
  });

  it("kotlin-android replay accepts mobile capabilities without trap false positives", async () => {
    const report = await runEval({
      fixturesDir,
      fixtureNames: ["kotlin-android"],
    });
    const fixture = report.fixtures[0];

    expect(report.passed).toBe(true);
    expect(fixture?.scorecard.actualModuleCount).toBe(2);
    expect(fixture?.scorecard.filePrecision).toBeCloseTo(1, 5);
    expect(fixture?.scorecard.fileRecall).toBeCloseTo(1, 5);
    expect(fixture?.scorecard.trivialModuleFalsePositiveCount).toBe(0);
    expect(fixture?.signalMetrics.selfContainmentVerifiedCount).toBe(2);
    expect(fixture?.signalMetrics.selfContainmentPassRate).toBeCloseTo(1, 5);
  }, 10_000);
});
