// Embedding providers ported from app/Sources/GunkApp/Search/EmbeddingIndex.swift.

import { LLMClientError, type FetchImpl, type LLMProvider } from "./client.js";

export interface EmbeddingProvider {
  readonly model: string;
  embed(text: string): Promise<number[]>;
}

function asObject(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function numberArray(value: unknown): number[] | null {
  return Array.isArray(value) && value.every((v) => typeof v === "number")
    ? (value as number[])
    : null;
}

export class OllamaEmbeddingProvider implements EmbeddingProvider {
  constructor(
    readonly model = "nomic-embed-text",
    private readonly baseURL = "http://localhost:11434",
    private readonly fetchImpl: FetchImpl = fetch,
  ) {}

  async embed(text: string): Promise<number[]> {
    const response = await this.fetchImpl(`${this.baseURL}/api/embeddings`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ model: this.model, prompt: text }),
    });
    if (response.status < 200 || response.status >= 300) {
      throw new LLMClientError(`LLM request failed with HTTP ${response.status}.`, "invalidHTTPStatus");
    }
    const root = asObject(await response.json());
    const embedding = numberArray(root?.embedding);
    if (embedding) return embedding;
    const embeddings = root?.embeddings;
    const first = Array.isArray(embeddings) ? numberArray(embeddings[0]) : null;
    if (first) return first;
    throw new LLMClientError("The LLM response was not valid structured output.", "invalidStructuredOutput");
  }
}

export class OpenAIEmbeddingProvider implements EmbeddingProvider {
  constructor(
    private readonly apiKey: string,
    readonly model = "text-embedding-3-small",
    private readonly baseURL = "https://api.openai.com/v1",
    private readonly fetchImpl: FetchImpl = fetch,
  ) {}

  async embed(text: string): Promise<number[]> {
    if (this.apiKey.length === 0) {
      throw new LLMClientError("Add an API key in Settings before dropping a folder.", "missingAPIKey");
    }
    const response = await this.fetchImpl(`${this.baseURL}/embeddings`, {
      method: "POST",
      headers: { Authorization: `Bearer ${this.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: this.model, input: text }),
    });
    if (response.status < 200 || response.status >= 300) {
      throw new LLMClientError(`LLM request failed with HTTP ${response.status}.`, "invalidHTTPStatus");
    }
    const root = asObject(await response.json());
    const data = root?.data;
    const first = Array.isArray(data) ? asObject(data[0]) : null;
    const embedding = numberArray(first?.embedding);
    if (!embedding) {
      throw new LLMClientError("The LLM response was not valid structured output.", "invalidStructuredOutput");
    }
    return embedding;
  }
}

export function makeEmbeddingProvider(
  provider: LLMProvider,
  options: { apiKey?: string; ollamaBaseURL?: string; fetchImpl?: FetchImpl } = {},
): EmbeddingProvider {
  switch (provider) {
    case "OpenAI":
      return new OpenAIEmbeddingProvider(options.apiKey ?? "", undefined, undefined, options.fetchImpl);
    case "Anthropic":
    case "Ollama":
      return new OllamaEmbeddingProvider(undefined, options.ollamaBaseURL, options.fetchImpl);
  }
}
