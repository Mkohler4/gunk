import { spawnSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  mkdtempSync,
  readdirSync,
  rmSync,
  statSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, relative, resolve } from "node:path";

import type { LanguageKind } from "../models.js";
import type { Gunk } from "../store/index.js";

export interface BuildVerifyResult {
  bundlePath: string;
  language: LanguageKind | "mixed" | "unsupported";
  built: boolean;
  skipped: boolean;
  command: string | null;
  log: string;
}

export interface BuildVerifierOptions {
  timeoutMs?: number;
  cwd?: string;
  env?: NodeJS.ProcessEnv;
}

interface BuildCommand {
  executable: string;
  args: string[];
  display: string;
}

const MAX_LOG_CHARS = 8_000;

function truncateLog(log: string): string {
  return log.length > MAX_LOG_CHARS
    ? `${log.slice(0, MAX_LOG_CHARS)}\n[truncated]`
    : log;
}

function filesUnder(root: string): string[] {
  const out: string[] = [];
  const visit = (dir: string) => {
    for (const entry of readdirSync(dir)) {
      if (entry === "node_modules" || entry === ".git") continue;
      const path = join(dir, entry);
      const stat = statSync(path);
      if (stat.isDirectory()) {
        visit(path);
      } else if (stat.isFile()) {
        out.push(relative(root, path).replace(/\\/g, "/"));
      }
    }
  };
  visit(root);
  return out.sort((a, b) => a.localeCompare(b));
}

function languageForFiles(files: string[]): BuildVerifyResult["language"] {
  if (files.some((file) => file.endsWith(".dart"))) return "dart";
  if (files.some((file) => file.endsWith(".kt") || file.endsWith(".kts"))) return "kotlin";
  if (files.some((file) => file.endsWith(".java"))) return "java";
  if (files.some((file) => /\.(ts|tsx|js|jsx|mts|mjs)$/.test(file))) return "typeScript";
  return "unsupported";
}

function toolExists(
  command: string,
  args: string[] = ["--version"],
  cwd = process.cwd(),
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const result = spawnSync(command, args, {
    cwd,
    env,
    encoding: "utf8",
    timeout: 5_000,
  });
  return !result.error && result.status === 0;
}

function localTool(name: string, cwd: string): string | null {
  const candidates = [
    resolve(cwd, "node_modules", ".bin", name),
    resolve(cwd, "..", "node_modules", ".bin", name),
    resolve(cwd, "engine", "node_modules", ".bin", name),
  ];
  return candidates.find((candidate) => existsSync(candidate)) ?? null;
}

function commandFor(
  language: BuildVerifyResult["language"],
  files: string[],
  cwd: string,
  env: NodeJS.ProcessEnv,
): BuildCommand | null {
  switch (language) {
    case "typeScript": {
      const tsc = localTool("tsc", cwd) ?? "tsc";
      if (!toolExists(tsc, ["--version"], cwd, env)) return null;
      const sourceFiles = files.filter((file) => /\.(ts|tsx|js|jsx|mts|mjs)$/.test(file));
      return {
        executable: tsc,
        args: [
          "--noEmit",
          "--skipLibCheck",
          "--module",
          "ESNext",
          "--target",
          "ES2022",
          "--moduleResolution",
          "bundler",
          "--esModuleInterop",
          "--allowJs",
          "--checkJs",
          "false",
          "--noImplicitAny",
          "false",
          "--strict",
          "false",
          ...sourceFiles,
        ],
        display: `tsc --noEmit ${sourceFiles.join(" ")}`,
      };
    }
    case "dart":
      if (!toolExists("dart", ["--version"], cwd, env)) return null;
      return { executable: "dart", args: ["analyze", "."], display: "dart analyze ." };
    case "kotlin": {
      if (!toolExists("kotlinc", ["-version"], cwd, env)) return null;
      const sourceFiles = files.filter((file) => file.endsWith(".kt") || file.endsWith(".kts"));
      return {
        executable: "kotlinc",
        args: [...sourceFiles, "-d", "build-verify.jar"],
        display: `kotlinc ${sourceFiles.join(" ")} -d build-verify.jar`,
      };
    }
    case "java": {
      if (!toolExists("javac", ["-version"], cwd, env)) return null;
      const sourceFiles = files.filter((file) => file.endsWith(".java"));
      return {
        executable: "javac",
        args: ["-d", "classes", ...sourceFiles],
        display: `javac -d classes ${sourceFiles.join(" ")}`,
      };
    }
    default:
      return null;
  }
}

export class BuildVerifier {
  private readonly timeoutMs: number;
  private readonly cwd: string;
  private readonly env: NodeJS.ProcessEnv;

  constructor(options: BuildVerifierOptions = {}) {
    this.timeoutMs = options.timeoutMs ?? 15_000;
    this.cwd = options.cwd ?? process.cwd();
    this.env = options.env ?? process.env;
  }

  verify(bundlePath: string): BuildVerifyResult {
    const resolvedBundlePath = resolve(bundlePath);
    const tempRoot = mkdtempSync(join(tmpdir(), "gunk-build-verify-"));
    const workDir = join(tempRoot, basename(resolvedBundlePath));

    try {
      cpSync(resolvedBundlePath, workDir, { recursive: true });
      const files = filesUnder(workDir);
      const language = languageForFiles(files);
      const command = commandFor(language, files, this.cwd, this.env);
      if (!command) {
        return {
          bundlePath: resolvedBundlePath,
          language,
          built: false,
          skipped: true,
          command: null,
          log: language === "unsupported" ? "No supported build verifier for bundle." : "Build tool not available.",
        };
      }

      const result = spawnSync(command.executable, command.args, {
        cwd: workDir,
        env: this.env,
        encoding: "utf8",
        timeout: this.timeoutMs,
      });
      const timedOut = result.error?.message.includes("ETIMEDOUT") ?? false;
      const log = truncateLog(
        [
          `$ ${command.display}`,
          result.stdout.trim(),
          result.stderr.trim(),
          timedOut ? `Timed out after ${this.timeoutMs}ms.` : "",
          result.error && !timedOut ? result.error.message : "",
        ]
          .filter((line) => line.length > 0)
          .join("\n"),
      );

      return {
        bundlePath: resolvedBundlePath,
        language,
        built: !timedOut && result.status === 0,
        skipped: false,
        command: command.display,
        log,
      };
    } catch (error) {
      return {
        bundlePath: resolvedBundlePath,
        language: "unsupported",
        built: false,
        skipped: false,
        command: null,
        log: error instanceof Error ? error.message : String(error),
      };
    } finally {
      rmSync(tempRoot, { recursive: true, force: true });
    }
  }

  verifyGunks(gunks: Gunk[]): BuildVerifyResult[] {
    return gunks
      .map((gunk) => gunk.bundlePath)
      .filter((bundlePath): bundlePath is string => bundlePath !== null)
      .map((bundlePath) => this.verify(bundlePath));
  }
}
