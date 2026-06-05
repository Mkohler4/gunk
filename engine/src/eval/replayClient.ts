import { readFileSync } from "node:fs";

import type {
  LLMClient,
  LLMProvider,
  LLMRequest,
  LLMResponse,
} from "../llm/client.js";
import type { LlmCallRecord, RunTrace } from "../trace/trace.js";

function messagesKey(messages: LLMRequest["messages"]): string {
  return JSON.stringify(
    messages.map((message) => ({
      role: message.role,
      content: message.content,
    })),
  );
}

function recordMessagesKey(record: LlmCallRecord): string {
  return JSON.stringify(
    record.requestMessages.map((message) => ({
      role: message.role,
      content: message.content,
    })),
  );
}

function provider(value: string): LLMProvider {
  if (value === "OpenAI" || value === "Anthropic" || value === "Ollama") {
    return value;
  }
  return "OpenAI";
}

export class ReplayClient implements LLMClient {
  readonly provider: LLMProvider;
  private readonly calls: LlmCallRecord[];
  private nextIndex = 0;

  constructor(trace: Pick<RunTrace, "provider" | "llmCalls">) {
    this.provider = provider(trace.provider);
    this.calls = trace.llmCalls;
  }

  static fromFile(path: string): ReplayClient {
    return new ReplayClient(JSON.parse(readFileSync(path, "utf8")) as RunTrace);
  }

  async complete(request: LLMRequest): Promise<LLMResponse> {
    const expected = this.calls[this.nextIndex];
    if (!expected) {
      throw new Error(
        `Replay tape exhausted before ${request.jsonSchemaName} call.`,
      );
    }

    if (messagesKey(request.messages) !== recordMessagesKey(expected)) {
      throw new Error(
        `Replay tape stale at call ${this.nextIndex + 1} (${expected.stage}).`,
      );
    }

    this.nextIndex += 1;
    return {
      json: expected.responseJson,
      usage: {
        inputTokens: expected.inputTokens,
        outputTokens: expected.outputTokens,
      },
    };
  }

  assertExhausted(): void {
    if (this.nextIndex !== this.calls.length) {
      throw new Error(
        `Replay tape has ${this.calls.length - this.nextIndex} unused call(s).`,
      );
    }
  }
}
