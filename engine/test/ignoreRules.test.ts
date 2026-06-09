import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { scanFolder } from "../src/ingest/scanner.js";

let temporaryDirectory: string;

function writeData(relpath: string, data: Buffer | string): void {
  const filePath = path.join(temporaryDirectory, relpath);
  mkdirSync(path.dirname(filePath), { recursive: true });
  writeFileSync(filePath, data);
}

function writeFile(relpath: string, contents: string): void {
  writeData(relpath, Buffer.from(contents, "utf8"));
}

beforeEach(() => {
  temporaryDirectory = mkdtempSync(path.join(tmpdir(), "gunk-scan-"));
});

afterEach(() => {
  rmSync(temporaryDirectory, { recursive: true, force: true });
});

describe("SourceScanner / IgnoreRules", () => {
  it("skips ignored dirs and binaries", () => {
    writeFile("src/App.swift", 'print("ok")');
    writeFile(".git/config", "repo");
    writeFile("node_modules/pkg/index.js", "module");
    writeFile("dist/bundle.js", "bundle");
    writeFile(".DS_Store", "metadata");
    writeData("image.png", Buffer.from([0x89, 0x50, 0x00, 0x47]));

    const files = scanFolder(temporaryDirectory);

    expect(files.map((file) => file.relpath)).toEqual(["src/App.swift"]);
  });

  it("skips Python virtualenvs and dependency/tool caches", () => {
    writeFile("src/main.py", "print('ok')");
    writeFile(".venv/lib/python3.12/site-packages/numpy/core.py", "import numpy");
    writeFile("venv/lib/pkg/mod.py", "x = 1");
    writeFile("__pycache__/main.cpython-312.pyc", "bytecode");
    writeFile(".mypy_cache/3.12/main.data.json", "{}");
    writeFile(".tox/py312/log.txt", "log");
    writeFile(".gradle/caches/jar.bin", "cache");
    writeFile(".idea/workspace.xml", "<xml/>");

    const files = scanFolder(temporaryDirectory);

    expect(files.map((file) => file.relpath)).toEqual(["src/main.py"]);
  });

  it("skips likely secret files", () => {
    writeFile("src/App.swift", 'print("ok")');
    writeFile(".env", "TOKEN=secret");
    writeFile("certs/api.pem", "secret");
    writeFile("certs/api.key", "secret");
    writeFile("id_rsa", "secret");
    writeFile("credentials.json", "{}");
    writeFile("certs/archive.p12", "secret");

    const files = scanFolder(temporaryDirectory);

    expect(files.map((file) => file.relpath)).toEqual(["src/App.swift"]);
  });

  it("honors .gunkignore", () => {
    writeFile(
      ".gunkignore",
      `Generated.swift
ignored-dir/
*.snap`,
    );
    writeFile("Generated.swift", "generated");
    writeFile("ignored-dir/App.swift", "ignored");
    writeFile("snapshot.snap", "ignored");
    writeFile("Sources/App.swift", 'print("ok")');

    const files = scanFolder(temporaryDirectory);

    expect(files.map((file) => file.relpath)).toEqual(["Sources/App.swift"]);
  });
});
