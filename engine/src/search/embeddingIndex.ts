// Embedding index. Ported from app/Sources/GunkApp/Search/EmbeddingIndex.swift.

import type { Database } from "bun:sqlite";
import { basename, extname } from "node:path";

import {
  filesForGunk,
  gunkEmbedding,
  listGunkTags,
  upsertGunkEmbedding,
  type Gunk,
  type GunkEmbedding,
} from "../store/index.js";
import { LLMClientError } from "../llm/client.js";
import type { EmbeddingProvider } from "../llm/embeddings.js";

export class EmbeddingIndex {
  constructor(
    private readonly db: Database,
    private readonly embedder: EmbeddingProvider,
  ) {}

  async index(gunk: Gunk): Promise<GunkEmbedding> {
    const vector = await this.embedder.embed(this.document(gunk));
    if (vector.length === 0) {
      throw new LLMClientError("The LLM response was not valid structured output.", "invalidStructuredOutput");
    }
    upsertGunkEmbedding(this.db, gunk.id, vector, this.embedder.model);
    return gunkEmbedding(this.db, gunk.id)!;
  }

  private document(gunk: Gunk): string {
    const tags = listGunkTags(this.db, gunk.id).map((t) => t.tag);
    const files = filesForGunk(this.db, gunk.id).map((f) => f.relpath);
    return [
      gunk.name,
      gunk.purpose ?? "",
      gunk.language ?? "",
      tags.join(" "),
      files.join(" "),
      files.map((f) => signatureTokens(f)).join(" "),
    ]
      .filter((part) => part.length > 0)
      .join("\n");
  }
}

function signatureTokens(path: string): string {
  const name = basename(path, extname(path));
  return name.replace(/-/g, " ").replace(/_/g, " ");
}
