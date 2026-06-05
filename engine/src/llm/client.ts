// LLM provider clients ported from app/Sources/GunkApp/LLM. Structured-output
// requests use a JSON schema; responses are parsed into a plain JS value.

import type { PipelineStage } from "../contract/events.js";
import type { DecompositionObserver } from "../trace/trace.js";

export type LLMProvider = "OpenAI" | "Anthropic" | "Ollama";

export function defaultModel(provider: LLMProvider): string {
  switch (provider) {
    case "OpenAI":
      return "gpt-4.1-mini";
    case "Anthropic":
      return "claude-sonnet-4-20250514";
    case "Ollama":
      return "llama3.2";
  }
}

export type LLMRole = "system" | "user" | "assistant";

export interface LLMMessage {
  role: LLMRole;
  content: string;
}

export type JsonSchema = Record<string, unknown>;

export interface LLMRequest {
  model: string;
  messages: LLMMessage[];
  jsonSchemaName: string;
  jsonSchema: JsonSchema;
  maxTokens?: number;
  temperature?: number;
}

export interface LLMTokenUsage {
  inputTokens: number | null;
  outputTokens: number | null;
}

export interface LLMResponse {
  json: unknown;
  usage: LLMTokenUsage;
}

export interface LLMClient {
  readonly provider: LLMProvider;
  complete(request: LLMRequest): Promise<LLMResponse>;
}

export class LLMClientError extends Error {
  constructor(
    message: string,
    readonly code:
      | "missingAPIKey"
      | "invalidHTTPStatus"
      | "missingStructuredOutput"
      | "invalidStructuredOutput",
  ) {
    super(message);
    this.name = "LLMClientError";
  }
}

export type FetchImpl = typeof fetch;

function asObject(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function asNumber(value: unknown): number | null {
  return typeof value === "number" ? value : null;
}

export class OpenAIClient implements LLMClient {
  readonly provider: LLMProvider = "OpenAI";

  constructor(
    private readonly apiKey: string,
    private readonly baseURL = "https://api.openai.com/v1",
    private readonly fetchImpl: FetchImpl = fetch,
  ) {}

  body(request: LLMRequest): Record<string, unknown> {
    const object: Record<string, unknown> = {
      model: request.model,
      messages: request.messages.map((m) => ({ role: m.role, content: m.content })),
      response_format: {
        type: "json_schema",
        json_schema: {
          name: request.jsonSchemaName,
          strict: true,
          schema: request.jsonSchema,
        },
      },
    };
    if (request.maxTokens !== undefined) object.max_tokens = request.maxTokens;
    if (request.temperature !== undefined) object.temperature = request.temperature;
    return object;
  }

  async complete(request: LLMRequest): Promise<LLMResponse> {
    if (this.apiKey.length === 0) {
      throw new LLMClientError("Add an API key in Settings before dropping a folder.", "missingAPIKey");
    }
    const response = await this.fetchImpl(`${this.baseURL}/chat/completions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${this.apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify(this.body(request)),
    });
    if (response.status < 200 || response.status >= 300) {
      throw new LLMClientError(`LLM request failed with HTTP ${response.status}.`, "invalidHTTPStatus");
    }
    const root = asObject(await response.json());
    const choices = root?.choices;
    const firstChoice = Array.isArray(choices) ? asObject(choices[0]) : null;
    const message = asObject(firstChoice?.message);
    const content = message?.content;
    if (typeof content !== "string") {
      throw new LLMClientError("The LLM response did not include structured output.", "missingStructuredOutput");
    }
    const usage = asObject(root?.usage);
    return {
      json: JSON.parse(content),
      usage: {
        inputTokens: asNumber(usage?.prompt_tokens),
        outputTokens: asNumber(usage?.completion_tokens),
      },
    };
  }
}

export class AnthropicClient implements LLMClient {
  readonly provider: LLMProvider = "Anthropic";

  constructor(
    private readonly apiKey: string,
    private readonly baseURL = "https://api.anthropic.com/v1",
    private readonly fetchImpl: FetchImpl = fetch,
  ) {}

  body(request: LLMRequest): Record<string, unknown> {
    const object: Record<string, unknown> = {
      model: request.model,
      max_tokens: request.maxTokens ?? 1024,
      messages: request.messages
        .filter((m) => m.role !== "system")
        .map((m) => ({ role: m.role, content: m.content })),
      tools: [
        {
          name: "structured_output",
          description: "Return the response using the requested JSON schema.",
          input_schema: request.jsonSchema,
        },
      ],
      tool_choice: { type: "tool", name: "structured_output" },
    };
    const system = request.messages
      .filter((m) => m.role === "system")
      .map((m) => m.content)
      .join("\n\n");
    if (system.length > 0) object.system = system;
    if (request.temperature !== undefined) object.temperature = request.temperature;
    return object;
  }

  async complete(request: LLMRequest): Promise<LLMResponse> {
    if (this.apiKey.length === 0) {
      throw new LLMClientError("Add an API key in Settings before dropping a folder.", "missingAPIKey");
    }
    const response = await this.fetchImpl(`${this.baseURL}/messages`, {
      method: "POST",
      headers: {
        "x-api-key": this.apiKey,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(this.body(request)),
    });
    if (response.status < 200 || response.status >= 300) {
      throw new LLMClientError(`LLM request failed with HTTP ${response.status}.`, "invalidHTTPStatus");
    }
    const root = asObject(await response.json());
    const content = root?.content;
    const toolUse = Array.isArray(content)
      ? content
          .map(asObject)
          .find((block) => block?.type === "tool_use" && block?.name === "structured_output")
      : null;
    if (!toolUse || toolUse.input === undefined) {
      throw new LLMClientError("The LLM response did not include structured output.", "missingStructuredOutput");
    }
    const usage = asObject(root?.usage);
    return {
      json: toolUse.input,
      usage: {
        inputTokens: asNumber(usage?.input_tokens),
        outputTokens: asNumber(usage?.output_tokens),
      },
    };
  }
}

export class OllamaClient implements LLMClient {
  readonly provider: LLMProvider = "Ollama";

  constructor(
    private readonly baseURL = "http://localhost:11434",
    private readonly fetchImpl: FetchImpl = fetch,
  ) {}

  body(request: LLMRequest): Record<string, unknown> {
    const object: Record<string, unknown> = {
      model: request.model,
      stream: false,
      format: request.jsonSchema,
      messages: request.messages.map((m) => ({ role: m.role, content: m.content })),
    };
    if (request.temperature !== undefined) object.options = { temperature: request.temperature };
    return object;
  }

  async complete(request: LLMRequest): Promise<LLMResponse> {
    const response = await this.fetchImpl(`${this.baseURL}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(this.body(request)),
    });
    if (response.status < 200 || response.status >= 300) {
      throw new LLMClientError(`LLM request failed with HTTP ${response.status}.`, "invalidHTTPStatus");
    }
    const root = asObject(await response.json());
    const message = asObject(root?.message);
    const content = message?.content;
    if (typeof content !== "string") {
      throw new LLMClientError("The LLM response did not include structured output.", "missingStructuredOutput");
    }
    return {
      json: JSON.parse(content),
      usage: {
        inputTokens: asNumber(root?.prompt_eval_count),
        outputTokens: asNumber(root?.eval_count),
      },
    };
  }
}

/**
 * Wraps any LLMClient and reports each call (request, response, timing) to the
 * observer, tagged with the active pipeline stage. This is how prompts and raw
 * responses land in the run trace.
 */
export class TracingLLMClient implements LLMClient {
  stage: PipelineStage = "survey";

  constructor(
    private readonly inner: LLMClient,
    private readonly observer: DecompositionObserver,
    private readonly now: () => number = () => Date.now(),
  ) {}

  get provider(): LLMProvider {
    return this.inner.provider;
  }

  async complete(request: LLMRequest): Promise<LLMResponse> {
    const startedAt = this.now();
    const response = await this.inner.complete(request);
    const durationMs = this.now() - startedAt;
    this.observer.llmCall({
      stage: this.stage,
      provider: this.inner.provider,
      model: request.model,
      requestMessages: request.messages.map((m) => ({ role: m.role, content: m.content })),
      responseJson: response.json,
      inputTokens: response.usage.inputTokens,
      outputTokens: response.usage.outputTokens,
      durationMs,
    });
    return response;
  }
}

export function makeClient(
  provider: LLMProvider,
  options: { apiKey?: string; ollamaBaseURL?: string; fetchImpl?: FetchImpl } = {},
): LLMClient {
  switch (provider) {
    case "OpenAI":
      return new OpenAIClient(options.apiKey ?? "", undefined, options.fetchImpl);
    case "Anthropic":
      return new AnthropicClient(options.apiKey ?? "", undefined, options.fetchImpl);
    case "Ollama":
      return new OllamaClient(options.ollamaBaseURL, options.fetchImpl);
  }
}
