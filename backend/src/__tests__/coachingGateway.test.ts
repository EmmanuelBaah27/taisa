import type { CoachingProvider, ProviderCoachingInput } from '../services/coaching/provider';
import { getConfiguredProvider } from '../services/coaching/provider';
import { createOpenAIProvider } from '../services/coaching/openaiProvider';
import { createAnthropicProvider } from '../services/coaching/anthropicProvider';
import { CoachingResponsePayloadSchema } from '../schemas/coaching';
import {
  estimateConfiguredCoachingUsage,
  requestCoaching,
} from '../services/coaching/coachingGateway';
import { buildSeniorSelfPrompt } from '../prompts/system/seniorSelf';

jest.mock('../db/connection', () => {
  throw new Error('The stateless coaching gateway must not import the backend database');
});

const requestFixture = {
  requestId: '11111111-1111-4111-8111-111111111111',
  submittedAt: '2026-08-09T00:00:00Z',
  input: 'I may prefer management',
  context: {
    profile: null,
    recentMessages: [{ role: 'user' as const, content: 'I may prefer management' }],
    memory: [
      {
        id: 'mem-1',
        type: 'goal' as const,
        statement: 'Become a Staff Designer',
        provenance: 'user-confirmed' as const,
        lifecycle: 'active' as const,
        confidence: 'established' as const,
        createdAt: '2026-08-09T00:00:00Z',
        confirmedAt: '2026-08-09T00:00:00Z',
        lastSupportedAt: '2026-08-09T00:00:00Z',
        statusChangedAt: '2026-08-09T00:00:00Z',
        sourceMessageIds: ['m1'],
      },
    ],
    evidence: [],
  },
};

const coachingPayloadFixture = {
  mode: 'coach' as const,
  relevance: 'career-relevant' as const,
  contextSufficiency: 'sufficient' as const,
  reply: 'Earlier you preferred the Staff path. Has that changed?',
  stance: 'challenge' as const,
  proposals: [
    {
      operation: 'support' as const,
      targetId: 'mem-1',
      sourceMessageId: 'm1',
      reason: 'The user revisited the existing goal.',
      requiresConfirmation: false as const,
    },
  ],
};

const validPayloadFixtures = [
  ['coach', coachingPayloadFixture],
  [
    'clarify',
    {
      mode: 'clarify' as const,
      relevance: 'career-relevant' as const,
      contextSufficiency: 'insufficient' as const,
      reply: 'Which meeting are you referring to?',
      stance: null,
      proposals: [],
    },
  ],
  [
    'redirect',
    {
      mode: 'redirect' as const,
      relevance: 'outside-scope' as const,
      contextSufficiency: 'sufficient' as const,
      reply: 'I can help when this connects to your work or career.',
      stance: null,
      proposals: [],
    },
  ],
] as const;

const providerInput: ProviderCoachingInput = {
  systemPrompt: 'System prompt',
  userPrompt: JSON.stringify(requestFixture),
};

const openAIConfig = {
  model: 'openai-mock',
  inputPriceUsdPerMillionTokens: 2,
  outputPriceUsdPerMillionTokens: 8,
  maxOutputTokens: 2048,
  structuredOutputInputTokenOverhead: 512,
};

const anthropicConfig = {
  model: 'anthropic-mock',
  inputPriceUsdPerMillionTokens: 3,
  outputPriceUsdPerMillionTokens: 15,
  maxOutputTokens: 1024,
  structuredOutputInputTokenOverhead: 512,
};

test.each(validPayloadFixtures)(
  'the shared schema accepts a valid %s response mode',
  (_mode, payload) => {
    expect(CoachingResponsePayloadSchema.safeParse(payload).success).toBe(true);
  },
);

test.each([
  ['clarify response with proposals', { ...validPayloadFixtures[1][1], proposals: coachingPayloadFixture.proposals }],
  ['clarify response with a coaching stance', { ...validPayloadFixtures[1][1], stance: 'nudge' }],
  ['coach response with insufficient context', { ...coachingPayloadFixture, contextSufficiency: 'insufficient' }],
  ['redirect response with career relevance', { ...validPayloadFixtures[2][1], relevance: 'career-relevant' }],
  ['coach response with outside-scope relevance', { ...coachingPayloadFixture, relevance: 'outside-scope' }],
  ['clarify response with sufficient context', { ...validPayloadFixtures[1][1], contextSufficiency: 'sufficient' }],
  ['redirect response with insufficient context', { ...validPayloadFixtures[2][1], contextSufficiency: 'insufficient' }],
])('the shared schema rejects a %s mode-axis conflict', (_name, payload) => {
  expect(CoachingResponsePayloadSchema.safeParse(payload).success).toBe(false);
});

test.each(validPayloadFixtures)(
  'OpenAI and Anthropic adapters honor the same %s structured coaching contract with one SDK call',
  async (_mode, payloadFixture) => {
  const openAIParse = jest.fn().mockResolvedValue({
    choices: [{ message: { parsed: { response: payloadFixture } } }],
    usage: { prompt_tokens: 10, completion_tokens: 4 },
  });
  const anthropicCreate = jest.fn().mockResolvedValue({
    content: [{ type: 'tool_use', name: 'submit_coaching_response', input: payloadFixture }],
    usage: { input_tokens: 10, output_tokens: 4 },
  });

  const adapters = [
    {
      provider: createOpenAIProvider(openAIConfig, {
        beta: { chat: { completions: { parse: openAIParse } } },
      } as any),
      call: openAIParse,
      providerId: 'openai',
      expectedCostUsd: 0.000052,
    },
    {
      provider: createAnthropicProvider(anthropicConfig, {
        messages: { create: anthropicCreate },
      } as any),
      call: anthropicCreate,
      providerId: 'anthropic',
      expectedCostUsd: 0.00009,
    },
  ];

  for (const adapter of adapters) {
    const result = await adapter.provider.respond(providerInput);

    expect(result.payload).toEqual(payloadFixture);
    expect(result.usage.provider).toBe(adapter.providerId);
    expect(result.usage.model).toContain('mock');
    expect(result.usage.inputTokens).toBe(10);
    expect(result.usage.outputTokens).toBe(4);
    expect(result.usage.estimatedCostUsd).toBeCloseTo(adapter.expectedCostUsd);
    expect(adapter.call).toHaveBeenCalledTimes(1);
  }

  expect(openAIParse.mock.calls[0][0].response_format.type).toBe('json_schema');
  expect(openAIParse.mock.calls[0][0].response_format.json_schema.schema).toMatchObject({
    type: 'object',
    properties: {
      response: expect.objectContaining({ anyOf: expect.any(Array) }),
    },
    required: ['response'],
    additionalProperties: false,
  });
  expect(openAIParse.mock.calls[0][0].max_completion_tokens).toBe(2048);
  expect(openAIParse.mock.calls[0][0].max_tokens).toBeUndefined();
  expect(openAIParse.mock.calls[0][1]).toEqual({ maxRetries: 0 });
  expect(anthropicCreate.mock.calls[0][0]).toMatchObject({
    max_tokens: 1024,
    tool_choice: {
      type: 'tool',
      name: 'submit_coaching_response',
      disable_parallel_tool_use: true,
    },
    tools: [{ name: 'submit_coaching_response', input_schema: { type: 'object' } }],
  });
  expect(anthropicCreate.mock.calls[0][1]).toEqual({ maxRetries: 0 });
  const anthropicSchema = anthropicCreate.mock.calls[0][0].tools[0].input_schema;
  expect(anthropicSchema).toMatchObject({
    type: 'object',
    oneOf: expect.any(Array),
  });
  expect(anthropicSchema.oneOf).toEqual(expect.arrayContaining([
    expect.objectContaining({
      properties: expect.objectContaining({
        mode: { const: 'coach' },
        relevance: { type: 'string', enum: ['career-relevant', 'adjacent'] },
        contextSufficiency: { type: 'string', enum: ['sufficient', 'partial'] },
        stance: { type: 'string', enum: ['mirror', 'nudge', 'challenge', 'direct'] },
      }),
    }),
    expect.objectContaining({
      properties: expect.objectContaining({
        mode: { const: 'clarify' },
        contextSufficiency: { const: 'insufficient' },
        stance: { type: 'null' },
        proposals: { type: 'array', minItems: 0, maxItems: 0 },
      }),
    }),
    expect.objectContaining({
      properties: expect.objectContaining({
        mode: { const: 'redirect' },
        relevance: { const: 'outside-scope' },
        contextSufficiency: { type: 'string', enum: ['sufficient', 'partial'] },
        stance: { type: 'null' },
        proposals: { type: 'array', minItems: 0, maxItems: 0 },
      }),
    }),
  ]));
  expect(JSON.stringify(anthropicSchema)).toEqual(
    expect.stringContaining('propose-outcome'),
  );
  expect(JSON.stringify(openAIParse.mock.calls[0][0].response_format)).toEqual(
    expect.stringContaining('contextSufficiency'),
  );
},
);

test.each(['openai', 'anthropic'] as const)(
  'configuration selects %s and requestCoaching invokes exactly that provider once',
  async (providerId) => {
    const providers: Record<'openai' | 'anthropic', CoachingProvider> = {
      openai: {
        id: 'openai',
        respond: jest.fn().mockResolvedValue({
          payload: coachingPayloadFixture,
          usage: {
            provider: 'openai',
            model: 'openai-mock',
            inputTokens: 10,
            outputTokens: 4,
            estimatedCostUsd: 0.000052,
          },
        }),
      },
      anthropic: {
        id: 'anthropic',
        respond: jest.fn().mockResolvedValue({
          payload: coachingPayloadFixture,
          usage: {
            provider: 'anthropic',
            model: 'anthropic-mock',
            inputTokens: 10,
            outputTokens: 4,
            estimatedCostUsd: 0.00009,
          },
        }),
      },
    };
    const selected = getConfiguredProvider(
      {
        TAISA_COACHING_PROVIDER: providerId,
        TAISA_OPENAI_MODEL: 'openai-mock',
        TAISA_OPENAI_INPUT_PRICE_USD_PER_MILLION_TOKENS: '2',
        TAISA_OPENAI_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '8',
        TAISA_OPENAI_MAX_OUTPUT_TOKENS: '2048',
        TAISA_OPENAI_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD: '512',
        TAISA_ANTHROPIC_MODEL: 'anthropic-mock',
        TAISA_ANTHROPIC_INPUT_PRICE_USD_PER_MILLION_TOKENS: '3',
        TAISA_ANTHROPIC_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '15',
        TAISA_ANTHROPIC_MAX_OUTPUT_TOKENS: '1024',
        TAISA_ANTHROPIC_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD: '512',
      },
      providers,
    );

    const response = await requestCoaching(requestFixture, selected);

    expect(response).toMatchObject({
      requestId: requestFixture.requestId,
      ...coachingPayloadFixture,
      usage: { provider: providerId },
    });
    expect(providers[providerId].respond).toHaveBeenCalledTimes(1);
    expect(providers[providerId === 'openai' ? 'anthropic' : 'openai'].respond).not.toHaveBeenCalled();
  },
);

test.each([undefined, '', 'other'])(
  'missing or invalid provider configuration fails closed (%s)',
  (configuredProvider) => {
    expect(() =>
      getConfiguredProvider(
        { TAISA_COACHING_PROVIDER: configuredProvider },
        {
          openai: { id: 'openai', respond: jest.fn() },
          anthropic: { id: 'anthropic', respond: jest.fn() },
        },
      ),
    ).toThrow('TAISA_COACHING_PROVIDER must be configured as openai or anthropic');
  },
);

test.each([
  [
    'missing selected model',
    {
      TAISA_COACHING_PROVIDER: 'openai',
      TAISA_OPENAI_INPUT_PRICE_USD_PER_MILLION_TOKENS: '2',
      TAISA_OPENAI_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '8',
      TAISA_OPENAI_MAX_OUTPUT_TOKENS: '2048',
    },
    'TAISA_OPENAI_MODEL must be configured',
  ],
  [
    'non-numeric selected input price',
    {
      TAISA_COACHING_PROVIDER: 'anthropic',
      TAISA_ANTHROPIC_MODEL: 'anthropic-mock',
      TAISA_ANTHROPIC_INPUT_PRICE_USD_PER_MILLION_TOKENS: 'not-a-number',
      TAISA_ANTHROPIC_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '15',
      TAISA_ANTHROPIC_MAX_OUTPUT_TOKENS: '1024',
    },
    'TAISA_ANTHROPIC_INPUT_PRICE_USD_PER_MILLION_TOKENS must be a non-negative number',
  ],
  [
    'negative selected output price',
    {
      TAISA_COACHING_PROVIDER: 'openai',
      TAISA_OPENAI_MODEL: 'openai-mock',
      TAISA_OPENAI_INPUT_PRICE_USD_PER_MILLION_TOKENS: '2',
      TAISA_OPENAI_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '-1',
      TAISA_OPENAI_MAX_OUTPUT_TOKENS: '2048',
    },
    'TAISA_OPENAI_OUTPUT_PRICE_USD_PER_MILLION_TOKENS must be a non-negative number',
  ],
])('fails closed for %s', (_name, environment, expectedMessage) => {
  expect(() =>
    getConfiguredProvider(environment, {
      openai: { id: 'openai', respond: jest.fn() },
      anthropic: { id: 'anthropic', respond: jest.fn() },
    }),
  ).toThrow(expectedMessage);
});

test('conservatively estimates configured coaching input bytes and capped output tokens', () => {
  const environment = {
    TAISA_COACHING_PROVIDER: 'openai',
    TAISA_OPENAI_MODEL: 'openai-mock',
    TAISA_OPENAI_INPUT_PRICE_USD_PER_MILLION_TOKENS: '2',
    TAISA_OPENAI_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '8',
    TAISA_OPENAI_MAX_OUTPUT_TOKENS: '2048',
    TAISA_OPENAI_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD: '512',
  };
  const prompt = buildSeniorSelfPrompt(requestFixture);
  const conservativeInputTokens =
    Buffer.byteLength(prompt.systemPrompt, 'utf8') + Buffer.byteLength(prompt.userPrompt, 'utf8');

  expect(estimateConfiguredCoachingUsage(requestFixture, environment)).toEqual({
    provider: 'openai',
    model: 'openai-mock',
    inputTokens: conservativeInputTokens + 512,
    outputTokens: 2048,
    estimatedCostUsd:
      ((conservativeInputTokens + 512) * 2 + 2048 * 8) / 1_000_000,
  });
});

test('fails closed when selected provider structured-output overhead is not configured', () => {
  expect(() => getConfiguredProvider({
    TAISA_COACHING_PROVIDER: 'openai',
    TAISA_OPENAI_MODEL: 'openai-mock',
    TAISA_OPENAI_INPUT_PRICE_USD_PER_MILLION_TOKENS: '2',
    TAISA_OPENAI_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '8',
    TAISA_OPENAI_MAX_OUTPUT_TOKENS: '2048',
  }, {
    openai: { id: 'openai', respond: jest.fn() },
    anthropic: { id: 'anthropic', respond: jest.fn() },
  })).toThrow('TAISA_OPENAI_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD must be configured');
});

test('invalid structured output is recoverable and never triggers a retry', async () => {
  const selected: CoachingProvider = {
    id: 'openai',
    respond: jest.fn().mockResolvedValue({
      payload: { reply: '', stance: 'invented', proposals: [] },
      usage: {
        provider: 'openai',
        model: 'openai-mock',
        inputTokens: 10,
        outputTokens: 4,
        estimatedCostUsd: 0.000052,
      },
    }),
  };

  await expect(requestCoaching(requestFixture, selected)).rejects.toMatchObject({
    code: 'INVALID_COACHING_OUTPUT',
    recoverable: true,
  });
  expect(selected.respond).toHaveBeenCalledTimes(1);
});

test('Senior Self prompt serializes only the submitted turn and supplied context', () => {
  const prompt = buildSeniorSelfPrompt(requestFixture);

  expect(prompt.systemPrompt).toEqual(expect.stringContaining('Mirror'));
  expect(prompt.systemPrompt).toEqual(expect.stringContaining('Nudge'));
  expect(prompt.systemPrompt).toEqual(expect.stringContaining('Challenge'));
  expect(prompt.systemPrompt).toEqual(expect.stringContaining('Direct'));
  expect(JSON.parse(prompt.userPrompt)).toEqual(requestFixture);
});
