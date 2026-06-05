// Secret redaction. Ported from app/Sources/GunkApp/Extract/SecretRedactor.swift.

import { readFileSync } from "node:fs";
import { basename } from "node:path";

export interface Redaction {
  path: string;
  reason: string;
}

export type SecretRedactionResult =
  | { kind: "write"; data: Buffer; redactions: Redaction[] }
  | { kind: "skip"; redactions: Redaction[] };

const SECRET_NAME_PATTERNS = [".env*", "*.pem", "*.key", "id_rsa*", "credentials*", "*.p12", "*.pfx"];

const SECRET_CONTENT_PATTERNS = [/AKIA[0-9A-Z]{12,}/, /(?<![A-Za-z0-9])sk-[A-Za-z0-9_-]{12,}/];
const PRIVATE_KEY_BLOCK = /-----BEGIN [A-Z ]*PRIVATE KEY-----/;
const HIGH_ENTROPY = /[A-Za-z0-9+/=_-]{40,}/;
const SECRET_KEYWORD = /(secret|token|api[_-]?key|password|credential)/i;

function fnmatchStar(pattern: string, candidate: string): boolean {
  const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".");
  return new RegExp(`^${escaped}$`, "i").test(candidate);
}

export class SecretRedactor {
  redact(absPath: string, relpath: string): SecretRedactionResult {
    if (this.isSecretNamed(relpath)) {
      return { kind: "skip", redactions: [{ path: relpath, reason: "secret_filename" }] };
    }

    const data = readFileSync(absPath);
    let contents: string;
    try {
      contents = new TextDecoder("utf-8", { fatal: true }).decode(data);
    } catch {
      return { kind: "skip", redactions: [{ path: relpath, reason: "non_utf8_unscannable" }] };
    }

    if (PRIVATE_KEY_BLOCK.test(contents)) {
      return { kind: "skip", redactions: [{ path: relpath, reason: "private_key_block" }] };
    }

    let didRedact = false;
    const redactedLines = contents.split(/\r\n|\r|\n/).map((line) => {
      if (this.lineMatchesKnownSecret(line) || this.lineMatchesHighEntropySecret(line)) {
        didRedact = true;
        return "[gunk redacted: secret-like content]";
      }
      return line;
    });

    if (!didRedact) {
      return { kind: "write", data, redactions: [] };
    }

    return {
      kind: "write",
      data: Buffer.from(redactedLines.join("\n"), "utf-8"),
      redactions: [{ path: relpath, reason: "secret_like_content" }],
    };
  }

  private isSecretNamed(relpath: string): boolean {
    const normalized = relpath.replace(/\\/g, "/").replace(/^\/+|\/+$/g, "");
    const name = basename(normalized);
    const candidates = [name, normalized];
    return SECRET_NAME_PATTERNS.some((pattern) => candidates.some((c) => fnmatchStar(pattern, c)));
  }

  private lineMatchesKnownSecret(line: string): boolean {
    return SECRET_CONTENT_PATTERNS.some((pattern) => pattern.test(line));
  }

  private lineMatchesHighEntropySecret(line: string): boolean {
    return HIGH_ENTROPY.test(line) && SECRET_KEYWORD.test(line);
  }
}
