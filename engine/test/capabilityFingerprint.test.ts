import { describe, expect, it } from "vitest";

import {
  type ExportRef,
  type FileSymbols,
  type ImportRef,
  languageKindForPath,
  type Symbol,
} from "../src/models.js";
import {
  type CapabilityFingerprint,
  CapabilityFingerprintBuilder,
} from "../src/analyze/capabilityFingerprint.js";
import { DependencyManifestParser } from "../src/analyze/dependencyManifest.js";

function fileSymbols(
  filePath: string,
  options: { symbols?: Symbol[]; imports?: ImportRef[]; exports?: ExportRef[] } = {},
): FileSymbols {
  return {
    path: filePath,
    language: languageKindForPath(filePath),
    viaFallback: false,
    symbols: options.symbols ?? [],
    imports: options.imports ?? [],
    exports: options.exports ?? [],
  };
}

function fingerprintFor(
  filePath: string,
  fingerprints: CapabilityFingerprint[],
): CapabilityFingerprint | undefined {
  return fingerprints.find((fingerprint) => fingerprint.filePath === filePath);
}

describe("DependencyManifestParser", () => {
  it("parses supported dependency manifests", () => {
    const parser = new DependencyManifestParser();
    const manifests = parser.parse({
      "package.json": '{"dependencies":{"stripe":"latest"}}',
      "Package.swift":
        '.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0")',
      // Mirrors the Swift raw-string fixture: the `\n` is a literal backslash-n.
      "pyproject.toml": '[project]\\ndependencies = ["fastapi>=0.100", "uvicorn"]',
      "requirements.txt": "Flask==3.0\n# ignored\nrequests>=2",
      "go.mod": "require github.com/gin-gonic/gin v1.10.0",
      "Cargo.toml": '[dependencies]\nserde = "1"',
    });

    const allDependencies = new Set(manifests.flatMap((manifest) => manifest.dependencies));
    expect(allDependencies).toEqual(
      new Set([
        "stripe",
        "swift-argument-parser",
        "fastapi",
        "uvicorn",
        "Flask",
        "requests",
        "github.com/gin-gonic/gin",
        "serde",
      ]),
    );
  });

  it("parses pubspec.yaml dependencies", () => {
    const parser = new DependencyManifestParser();
    const manifest = parser.parseOne(
      "pubspec.yaml",
      `name: fixture

environment:
  sdk: ">=3.4.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  firebase_auth: ^5.0.0
  dio: ^5.4.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.0`,
    );

    expect(manifest?.kind).toBe("pubspecYaml");
    expect(manifest?.dependencies).toEqual([
      "flutter",
      "firebase_auth",
      "dio",
      "flutter_test",
      "build_runner",
    ]);
  });

  it("parses Gradle dependencies", () => {
    const parser = new DependencyManifestParser();
    const manifest = parser.parseOne(
      "android/app/build.gradle.kts",
      `dependencies {
  implementation("com.squareup.retrofit2:retrofit:2.11.0")
  implementation("com.android.billingclient:billing-ktx:7.0.0")
  testImplementation("junit:junit:4.13.2")
}`,
    );

    expect(manifest?.kind).toBe("gradle");
    expect(manifest?.dependencies).toEqual([
      "com.squareup.retrofit2:retrofit",
      "retrofit",
      "com.android.billingclient:billing-ktx",
      "billing-ktx",
      "junit:junit",
      "junit",
    ]);
  });
});

describe("CapabilityFingerprintBuilder", () => {
  it("maps third-party dependencies to importing files", () => {
    const manifests = new DependencyManifestParser().parse({
      "package.json": `{
  "dependencies": {
    "passport-google-oauth20": "latest",
    "stripe": "latest"
  }
}`,
    });
    const files = [
      fileSymbols("src/auth/google.ts", {
        imports: [
          { moduleSpecifier: "passport-google-oauth20", resolvedTarget: null, line: 1 },
          { moduleSpecifier: "./types", resolvedTarget: "src/auth/types.ts", line: 2 },
        ],
      }),
      fileSymbols("src/billing/checkout.ts", {
        imports: [{ moduleSpecifier: "stripe", resolvedTarget: null, line: 1 }],
      }),
      fileSymbols("src/auth/types.ts"),
    ];

    const fingerprints = new CapabilityFingerprintBuilder().fingerprints(files, manifests, {});

    expect(fingerprintFor("src/auth/google.ts", fingerprints)?.importedDependencies).toEqual([
      "passport-google-oauth20",
    ]);
    expect(fingerprintFor("src/billing/checkout.ts", fingerprints)?.importedDependencies).toEqual([
      "stripe",
    ]);
    expect(fingerprintFor("src/auth/types.ts", fingerprints)?.importedDependencies).toEqual([]);
  });

  it("detects express routes as surface", () => {
    const file = fileSymbols("src/auth/routes.ts", {
      exports: [{ name: "authRouter", kind: "variable", line: 1 }],
    });
    const fingerprints = new CapabilityFingerprintBuilder().fingerprints([file], [], {
      "src/auth/routes.ts": `router.get("/auth/google", googleLogin);
app.post("/auth/google/callback", googleCallback);`,
    });

    const fingerprint = fingerprintFor("src/auth/routes.ts", fingerprints);
    expect(fingerprint?.routes).toEqual([
      {
        framework: "express",
        method: "GET",
        path: "/auth/google",
        handler: "googleLogin",
        line: 1,
      },
      {
        framework: "express",
        method: "POST",
        path: "/auth/google/callback",
        handler: "googleCallback",
        line: 2,
      },
    ]);
    expect(fingerprint?.publicExports).toEqual([
      { name: "authRouter", kind: "variable", line: 1 },
    ]);
  });

  it("emits lexicon hints for known libraries", () => {
    const manifests = new DependencyManifestParser().parse({
      "package.json": `{
  "dependencies": {
    "passport-google-oauth20": "latest"
  }
}`,
    });
    const files = [
      fileSymbols("src/auth/google.ts", {
        symbols: [{ name: "googleOAuthCallback", kind: "function", line: 4 }],
        imports: [{ moduleSpecifier: "passport-google-oauth20", resolvedTarget: null, line: 1 }],
        exports: [{ name: "googleOAuthCallback", kind: "function", line: 4 }],
      }),
    ];

    const builder = new CapabilityFingerprintBuilder();
    const fingerprints = builder.fingerprints(files, manifests, {
      "src/auth/google.ts": `const clientId = process.env.GOOGLE_CLIENT_ID;
const callbackUrl = config.get("auth.google.callbackUrl");
export function googleOAuthCallback() {}`,
    });
    const fingerprint = fingerprintFor("src/auth/google.ts", fingerprints);
    const aggregate = builder.aggregate(fingerprints, new Set(["src/auth/google.ts"]));

    expect(fingerprint?.capabilityHints).toEqual([
      { library: "passport-google-oauth20", labels: ["auth", "google", "oauth"] },
    ]);
    expect(fingerprint?.envVars).toEqual(["GOOGLE_CLIENT_ID"]);
    expect(fingerprint?.configKeys).toEqual(["auth.google.callbackUrl"]);
    expect(fingerprint?.namingTokens).toContain("google");
    expect(aggregate.hasPublicSurface).toBe(true);
    expect(aggregate.capabilityHints).toEqual(fingerprint?.capabilityHints);
  });

  it("maps firebase_auth and Stripe mobile dependencies to hints", () => {
    const manifests = new DependencyManifestParser().parse({
      "pubspec.yaml": `dependencies:
  firebase_auth: ^5.0.0
  dio: ^5.4.0
  flutter_stripe: ^11.0.0`,
      "android/app/build.gradle": `dependencies {
  implementation 'com.android.billingclient:billing-ktx:7.0.0'
}`,
    });
    const files = [
      fileSymbols("lib/features/auth/auth_repository.dart", {
        imports: [
          {
            moduleSpecifier: "package:firebase_auth/firebase_auth.dart",
            resolvedTarget: null,
            line: 1,
          },
          { moduleSpecifier: "package:dio/dio.dart", resolvedTarget: null, line: 2 },
        ],
      }),
      fileSymbols("lib/features/payments/checkout.dart", {
        imports: [{ moduleSpecifier: "package:flutter_stripe/flutter_stripe.dart", resolvedTarget: null, line: 1 }],
      }),
      fileSymbols("android/app/src/main/kotlin/Billing.kt", {
        imports: [{ moduleSpecifier: "com.android.billingclient.api.BillingClient", resolvedTarget: null, line: 1 }],
      }),
    ];

    const builder = new CapabilityFingerprintBuilder();
    const fingerprints = builder.fingerprints(files, manifests, {});
    const aggregate = builder.aggregate(
      fingerprints,
      new Set(["lib/features/auth/auth_repository.dart"]),
    );

    expect(
      fingerprintFor("lib/features/auth/auth_repository.dart", fingerprints)?.importedDependencies,
    ).toEqual(["firebase_auth", "dio"]);
    expect(
      fingerprintFor("lib/features/auth/auth_repository.dart", fingerprints)?.capabilityHints,
    ).toEqual([
      { library: "firebase_auth", labels: ["auth", "firebase"] },
      { library: "dio", labels: ["network"] },
    ]);
    expect(
      fingerprintFor("lib/features/payments/checkout.dart", fingerprints)?.capabilityHints,
    ).toEqual([{ library: "flutter_stripe", labels: ["payments", "billing"] }]);
    expect(
      fingerprintFor("android/app/src/main/kotlin/Billing.kt", fingerprints)?.capabilityHints,
    ).toEqual([
      { library: "com.android.billingclient:billing-ktx", labels: ["payments", "billing"] },
    ]);
    expect(aggregate.hasPublicSurface).toBe(true);
  });
});
