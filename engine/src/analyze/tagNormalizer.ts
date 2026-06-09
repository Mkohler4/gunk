// Deterministic normalization for module tags. Keeps the AI-discovered tag set
// clean and byte-stable: lowercase kebab-case, deduped, and capped.

export const MAX_TAGS_PER_MODULE = 6;

/**
 * Normalize a single raw tag into a lowercase kebab-case slug, or `null` when
 * nothing meaningful remains. Spaces/underscores become hyphens, any character
 * outside `[a-z0-9-]` is dropped, and repeated/leading/trailing hyphens are
 * collapsed.
 */
export function normalizeTag(raw: string): string | null {
  const slug = raw
    .toLowerCase()
    .trim()
    .replace(/[\s_]+/g, "-")
    .replace(/[^a-z0-9-]+/g, "")
    .replace(/-+/g, "-")
    .replace(/^-+|-+$/g, "");

  return slug.length === 0 ? null : slug;
}

/**
 * Normalize a list of raw tags: slug each, drop empties, dedupe (stable order),
 * and cap at {@link MAX_TAGS_PER_MODULE}.
 */
export function normalizeTags(raw: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const value of raw) {
    const slug = normalizeTag(value);
    if (slug === null || seen.has(slug)) {
      continue;
    }
    seen.add(slug);
    out.push(slug);
    if (out.length >= MAX_TAGS_PER_MODULE) {
      break;
    }
  }
  return out;
}
