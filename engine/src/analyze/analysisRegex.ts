// Port of AnalysisRegex.swift. Mirrors NSRegularExpression semantics closely:
// matching is global (all non-overlapping matches) and each match yields its
// capturing groups (group indices >= 1), dropping unmatched (NSNotFound) groups
// exactly as the Swift `compactMap` does.

function compile(pattern: string): RegExp | null {
  let source = pattern;
  let flags = "g";

  // JavaScript RegExp does not support an inline `(?m)` flag prefix, so lift it
  // out into the standard multiline flag.
  if (source.startsWith("(?m)")) {
    source = source.slice(4);
    flags += "m";
  }

  try {
    return new RegExp(source, flags);
  } catch {
    return null;
  }
}

export interface RawRegexMatch {
  /** Capturing groups (index >= 1), including unmatched groups as `undefined`. */
  groups: (string | undefined)[];
  /** UTF-16 offset of the start of the whole match. */
  index: number;
}

export function analysisRawMatches(text: string, pattern: string): RawRegexMatch[] {
  const regex = compile(pattern);
  if (!regex) {
    return [];
  }

  const out: RawRegexMatch[] = [];
  for (const match of text.matchAll(regex)) {
    const groups: (string | undefined)[] = [];
    for (let index = 1; index < match.length; index += 1) {
      groups.push(match[index]);
    }
    out.push({ groups, index: match.index ?? 0 });
  }

  return out;
}

export function analysisMatches(text: string, pattern: string): string[][] {
  return analysisRawMatches(text, pattern).map((match) =>
    match.groups.filter((group): group is string => group !== undefined),
  );
}

export function analysisFirstMatch(text: string, pattern: string): string | undefined {
  return analysisMatches(text, pattern)[0]?.[0];
}

export function lineNumberAtOffset(offset: number, contents: string): number {
  const end = Math.max(0, Math.min(offset, contents.length));
  let count = 1;
  for (let index = 0; index < end; index += 1) {
    if (contents[index] === "\n") {
      count += 1;
    }
  }
  return count;
}
