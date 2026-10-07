import { createOpenAIProvider } from '../services/coaching/openaiProvider';
import { createAnthropicProvider } from '../services/coaching/anthropicProvider';
import { getConfiguredFallbackProvider } from '../services/coaching/fallbackProvider';
import { UsageExceedsReservationError } from '../services/usage/costLedger';
import { CoachingResponsePayloadSchema } from '../schemas/coaching';

const config = {
  model: 'fixture-model',
  inputPriceUsdPerMillionTokens: 1,
  outputPriceUsdPerMillionTokens: 2,
  maxOutputTokens: 200,
  structuredOutputInputTokenOverhead: 10,
};
const input = { systemPrompt: 'system', userPrompt: 'user' };
const payload = {
  mode: 'coach', relevance: 'career-relevant', contextSufficiency: 'sufficient',
  reply: 'What changed?', stance: 'nudge', proposals: [],
};

async function collect<T>(stream: AsyncIterable<T>): Promise<T[]> {
  const items: T[] = [];
  for await (const item of stream) items.push(item);
  return items;
}

test('OpenAI adapter emits reply deltas before its validated terminal payload', async () => {
  const stream = {
    async *[Symbol.asyncIterator]() {
      yield { choices: [{ delta: { content: '{"mode":"coach","reply":"What ' } }] };
      yield { choices: [{ delta: { content: 'changed?","relevance":"career-relevant"}' } }] };
    },
    finalChatCompletion: jest.fn().mockResolvedValue({
      choices: [{ message: { parsed: { response: payload } } }],
      usage: { prompt_tokens: 10, completion_tokens: 5 },
    }),
  };
  const client = { beta: { chat: { completions: { stream: jest.fn(() => stream) } } } };
  const provider = createOpenAIProvider(config, client as any);

  const items = await collect(provider.streamRespond!(input));
  expect(items).toEqual([
    { kind: 'delta', delta: 'What ' },
    { kind: 'delta', delta: 'changed?' },
    { kind: 'completed', result: expect.objectContaining({ payload }) },
  ]);
});

test('Anthropic adapter emits tool-input reply deltas before its validated terminal payload', async () => {
  const stream = {
    async *[Symbol.asyncIterator]() {
      yield { type: 'content_block_delta', delta: { type: 'input_json_delta', partial_json: '{"reply":"What ' } };
      yield { type: 'content_block_delta', delta: { type: 'input_json_delta', partial_json: 'changed?"}' } };
    },
    finalMessage: jest.fn().mockResolvedValue({
      content: [{ type: 'tool_use', name: 'submit_coaching_response', input: payload }],
      usage: { input_tokens: 10, output_tokens: 5 },
    }),
  };
  const client = { messages: { stream: jest.fn(() => stream) } };
  const provider = createAnthropicProvider(config, client as any);

  const items = await collect(provider.streamRespond!(input));
  expect(items).toEqual([
    { kind: 'delta', delta: 'What ' },
    { kind: 'delta', delta: 'changed?' },
    { kind: 'completed', result: expect.objectContaining({ payload }) },
  ]);
});

test('fallback is allowed only before the primary emits visible text', async () => {
  const failedPrimary = {
    id: 'openai' as const,
    estimateMaximumUsage: () => ({ provider: 'openai' as const, model: 'fixture', estimatedCostUsd: 0.01 }),
    respond: jest.fn(),
    async *streamRespond() { throw { status: 503 }; },
  };
  const successfulFallback = {
    id: 'anthropic' as const,
    estimateMaximumUsage: () => ({ provider: 'anthropic' as const, model: 'fixture', estimatedCostUsd: 0.01 }),
    respond: jest.fn(),
    async *streamRespond() {
      yield { kind: 'delta' as const, delta: 'Fallback' };
      yield { kind: 'completed' as const, result: { payload, usage: { provider: 'anthropic' as const, model: 'fixture', estimatedCostUsd: 0.01 } } };
    },
  };
  const environment = {
    TAISA_COACHING_PROVIDER: 'openai',
    TAISA_OPENAI_MODEL: 'fixture', TAISA_OPENAI_INPUT_PRICE_USD_PER_MILLION_TOKENS: '1',
    TAISA_OPENAI_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '1', TAISA_OPENAI_MAX_OUTPUT_TOKENS: '10',
    TAISA_OPENAI_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD: '1',
    TAISA_ANTHROPIC_MODEL: 'fixture', TAISA_ANTHROPIC_INPUT_PRICE_USD_PER_MILLION_TOKENS: '1',
    TAISA_ANTHROPIC_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '1', TAISA_ANTHROPIC_MAX_OUTPUT_TOKENS: '10',
    TAISA_ANTHROPIC_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD: '1',
  };
  const provider = getConfiguredFallbackProvider(environment, {
    openai: failedPrimary, anthropic: successfulFallback,
  });
  const observer = { beginAttempt: jest.fn(), settleAttempt: jest.fn() };

  const items = await collect((provider as any).stream(input, observer));
  expect(items[0]).toEqual({ kind: 'delta', delta: 'Fallback' });
  expect(observer.beginAttempt.mock.calls).toEqual([['primary'], ['fallback']]);
});

test('invalid primary structured output falls back before visible text', async () => {
  const malformed = CoachingResponsePayloadSchema.safeParse({
    ...payload,
    stance: 'not-a-valid-stance',
  });
  if (malformed.success) throw new Error('Expected malformed primary fixture');
  const failedPrimary = {
    id: 'openai' as const,
    estimateMaximumUsage: () => ({ provider: 'openai' as const, model: 'fixture', estimatedCostUsd: 0.01 }),
    respond: jest.fn(),
    async *streamRespond() { throw malformed.error; },
  };
  const successfulFallback = {
    id: 'anthropic' as const,
    estimateMaximumUsage: () => ({ provider: 'anthropic' as const, model: 'fixture', estimatedCostUsd: 0.01 }),
    respond: jest.fn(),
    async *streamRespond() {
      yield { kind: 'completed' as const, result: { payload, usage: { provider: 'anthropic' as const, model: 'fixture', estimatedCostUsd: 0.01 } } };
    },
  };
  const environment = {
    TAISA_COACHING_PROVIDER: 'openai',
    TAISA_OPENAI_MODEL: 'fixture', TAISA_OPENAI_INPUT_PRICE_USD_PER_MILLION_TOKENS: '1',
    TAISA_OPENAI_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '1', TAISA_OPENAI_MAX_OUTPUT_TOKENS: '10',
    TAISA_OPENAI_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD: '1',
    TAISA_ANTHROPIC_MODEL: 'fixture', TAISA_ANTHROPIC_INPUT_PRICE_USD_PER_MILLION_TOKENS: '1',
    TAISA_ANTHROPIC_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '1', TAISA_ANTHROPIC_MAX_OUTPUT_TOKENS: '10',
    TAISA_ANTHROPIC_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD: '1',
  };
  const provider = getConfiguredFallbackProvider(environment, {
    openai: failedPrimary, anthropic: successfulFallback,
  });
  const observer = { beginAttempt: jest.fn(), settleAttempt: jest.fn() };

  await expect(collect(provider.stream(input, observer))).resolves.toMatchObject([
    { kind: 'completed', result: { payload } },
  ]);
  expect(observer.beginAttempt.mock.calls).toEqual([['primary'], ['fallback']]);
});

test('invalid primary structured output does not leak buffered text before fallback', async () => {
  const malformed = CoachingResponsePayloadSchema.safeParse({
    ...payload,
    stance: 'not-a-valid-stance',
  });
  if (malformed.success) throw new Error('Expected malformed primary fixture');
  const failedPrimary = {
    id: 'openai' as const,
    estimateMaximumUsage: () => ({ provider: 'openai' as const, model: 'fixture', estimatedCostUsd: 0.01 }),
    respond: jest.fn(),
    async *streamRespond() {
      yield { kind: 'delta' as const, delta: 'Unvalidated primary text' };
      throw malformed.error;
    },
  };
  const successfulFallback = {
    id: 'anthropic' as const,
    estimateMaximumUsage: () => ({ provider: 'anthropic' as const, model: 'fixture', estimatedCostUsd: 0.01 }),
    respond: jest.fn(),
    async *streamRespond() {
      yield { kind: 'delta' as const, delta: 'Validated fallback text' };
      yield { kind: 'completed' as const, result: { payload, usage: { provider: 'anthropic' as const, model: 'fixture', estimatedCostUsd: 0.01 } } };
    },
  };
  const environment = {
    TAISA_COACHING_PROVIDER: 'openai',
    TAISA_OPENAI_MODEL: 'fixture', TAISA_OPENAI_INPUT_PRICE_USD_PER_MILLION_TOKENS: '1',
    TAISA_OPENAI_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '1', TAISA_OPENAI_MAX_OUTPUT_TOKENS: '10',
    TAISA_OPENAI_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD: '1',
    TAISA_ANTHROPIC_MODEL: 'fixture', TAISA_ANTHROPIC_INPUT_PRICE_USD_PER_MILLION_TOKENS: '1',
    TAISA_ANTHROPIC_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '1', TAISA_ANTHROPIC_MAX_OUTPUT_TOKENS: '10',
    TAISA_ANTHROPIC_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD: '1',
  };
  const provider = getConfiguredFallbackProvider(environment, {
    openai: failedPrimary, anthropic: successfulFallback,
  });
  const observer = { beginAttempt: jest.fn(), settleAttempt: jest.fn() };

  await expect(collect(provider.stream(input, observer))).resolves.toMatchObject([
    { kind: 'delta', delta: 'Validated fallback text' },
    { kind: 'completed', result: { payload } },
  ]);
  expect(observer.beginAttempt.mock.calls).toEqual([['primary'], ['fallback']]);
});

test('a streamed paid answer survives a usage overrun without settling the attempt twice', async () => {
  const successfulPrimary = {
    id: 'openai' as const,
    estimateMaximumUsage: () => ({ provider: 'openai' as const, model: 'fixture', estimatedCostUsd: 0.01 }),
    respond: jest.fn(),
    async *streamRespond() {
      yield { kind: 'completed' as const, result: { payload, usage: { provider: 'openai' as const, model: 'fixture', estimatedCostUsd: 0.02 } } };
    },
  };
  const unusedFallback = {
    id: 'anthropic' as const,
    estimateMaximumUsage: () => ({ provider: 'anthropic' as const, model: 'fixture', estimatedCostUsd: 0.01 }),
    respond: jest.fn(),
    async *streamRespond() { throw new Error('must not run'); },
  };
  const environment = {
    TAISA_COACHING_PROVIDER: 'openai',
    TAISA_OPENAI_MODEL: 'fixture', TAISA_OPENAI_INPUT_PRICE_USD_PER_MILLION_TOKENS: '1',
    TAISA_OPENAI_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '1', TAISA_OPENAI_MAX_OUTPUT_TOKENS: '10',
    TAISA_OPENAI_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD: '1',
    TAISA_ANTHROPIC_MODEL: 'fixture', TAISA_ANTHROPIC_INPUT_PRICE_USD_PER_MILLION_TOKENS: '1',
    TAISA_ANTHROPIC_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '1', TAISA_ANTHROPIC_MAX_OUTPUT_TOKENS: '10',
    TAISA_ANTHROPIC_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD: '1',
  };
  const provider = getConfiguredFallbackProvider(environment, {
    openai: successfulPrimary, anthropic: unusedFallback,
  });
  const observer = {
    beginAttempt: jest.fn(),
    settleAttempt: jest.fn((settlement) => {
      if (settlement.receipt) throw new UsageExceedsReservationError(0.01, 0.02);
    }),
  };

  await expect(collect(provider.stream(input, observer))).resolves.toMatchObject([
    { kind: 'completed', result: { payload } },
  ]);
  expect(observer.settleAttempt).toHaveBeenCalledTimes(1);
});
