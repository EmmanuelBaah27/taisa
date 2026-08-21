import type { CoachingProvider, ProviderCoachingInput } from '../services/coaching/provider';
import { getConfiguredProvider } from '../services/coaching/provider';
import {
  ContentFreeFallbackError,
  ContentFreeFallbackInvalidOutputError,
  getConfiguredFallbackProvider,
} from '../services/coaching/fallbackProvider';
import { createOpenAIProvider } from '../services/coaching/openaiProvider';
import { createAnthropicProvider } from '../services/coaching/anthropicProvider';
import {
  COACHING_GATEWAY_LIMITS,
  firstCoachingResponseContractViolation,
} from '@taisa/shared';
import type { CoachingRequest } from '@taisa/shared';
import { CoachingResponsePayloadSchema } from '../schemas/coaching';
import {
  estimateConfiguredCoachingUsage,
  requestCoaching,
} from '../services/coaching/coachingGateway';
import { classifyOperationalProviderFailure } from '../services/coaching/providerFailure';
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

const invalidPayloadFixtures = [
  ['clarify response with proposals', { ...validPayloadFixtures[1][1], proposals: coachingPayloadFixture.proposals }],
  ['clarify response with a coaching stance', { ...validPayloadFixtures[1][1], stance: 'nudge' }],
  ['coach response with insufficient context', { ...coachingPayloadFixture, contextSufficiency: 'insufficient' }],
  ['redirect response with career relevance', { ...validPayloadFixtures[2][1], relevance: 'career-relevant' }],
  ['coach response with outside-scope relevance', { ...coachingPayloadFixture, relevance: 'outside-scope' }],
  ['clarify response with sufficient context', { ...validPayloadFixtures[1][1], contextSufficiency: 'sufficient' }],
  ['redirect response with insufficient context', { ...validPayloadFixtures[2][1], contextSufficiency: 'insufficient' }],
] as const;

const outcomePayloadFixture = {
  ...coachingPayloadFixture,
  proposals: [{
    operation: 'propose-outcome' as const,
    candidate: {
      kind: 'evidence' as const,
      statement: 'Facilitated roadmap alignment.',
      occurredAt: '2026-08-09T00:00:00Z',
      goalIds: ['goal-1'],
      actionIds: ['action-1'],
    },
    reason: 'This is grounded in the submitted context.',
    requiresConfirmation: true as const,
  }],
};

function portableResponse(payload: unknown) {
  return {
    ...(payload as object),
    requestId: requestFixture.requestId,
    usage: {
      provider: 'openai',
      model: 'fixture',
      inputTokens: 10,
      outputTokens: 4,
      estimatedCostUsd: 0.000052,
    },
  };
}

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

function environment(primaryId: 'openai' | 'anthropic') {
  return {
    TAISA_COACHING_PROVIDER: primaryId,
    TAISA_OPENAI_MODEL: openAIConfig.model,
    TAISA_OPENAI_INPUT_PRICE_USD_PER_MILLION_TOKENS: String(
      openAIConfig.inputPriceUsdPerMillionTokens,
    ),
    TAISA_OPENAI_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: String(
      openAIConfig.outputPriceUsdPerMillionTokens,
    ),
    TAISA_OPENAI_MAX_OUTPUT_TOKENS: String(openAIConfig.maxOutputTokens),
    TAISA_OPENAI_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD: String(
      openAIConfig.structuredOutputInputTokenOverhead,
    ),
    TAISA_ANTHROPIC_MODEL: anthropicConfig.model,
    TAISA_ANTHROPIC_INPUT_PRICE_USD_PER_MILLION_TOKENS: String(
      anthropicConfig.inputPriceUsdPerMillionTokens,
    ),
    TAISA_ANTHROPIC_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: String(
      anthropicConfig.outputPriceUsdPerMillionTokens,
    ),
    TAISA_ANTHROPIC_MAX_OUTPUT_TOKENS: String(anthropicConfig.maxOutputTokens),
    TAISA_ANTHROPIC_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD: String(
      anthropicConfig.structuredOutputInputTokenOverhead,
    ),
  };
}

function providerResult(providerId: 'openai' | 'anthropic') {
  return {
    payload: coachingPayloadFixture,
    usage: {
      provider: providerId,
      model: `${providerId}-mock`,
      inputTokens: 10,
      outputTokens: 4,
      estimatedCostUsd: providerId === 'openai' ? 0.000052 : 0.00009,
    },
  };
}

function providerRegistry(): Record<'openai' | 'anthropic', CoachingProvider> {
  return {
    openai: {
      id: 'openai',
      estimateMaximumUsage: jest.fn().mockReturnValue({
        provider: 'openai',
        model: openAIConfig.model,
        inputTokens: 100,
        outputTokens: openAIConfig.maxOutputTokens,
        estimatedCostUsd: 0.02,
      }),
      respond: jest.fn().mockResolvedValue(providerResult('openai')),
    },
    anthropic: {
      id: 'anthropic',
      estimateMaximumUsage: jest.fn().mockReturnValue({
        provider: 'anthropic',
        model: anthropicConfig.model,
        inputTokens: 100,
        outputTokens: anthropicConfig.maxOutputTokens,
        estimatedCostUsd: 0.03,
      }),
      respond: jest.fn().mockResolvedValue(providerResult('anthropic')),
    },
  };
}

function attemptObserver() {
  return {
    beginAttempt: jest.fn(),
    settleAttempt: jest.fn(),
  };
}

function other(providerId: 'openai' | 'anthropic') {
  return providerId === 'openai' ? 'anthropic' as const : 'openai' as const;
}

const operationalFailures = [
  ['timeout', { status: 408 }, 'timeout'],
  ['conflict', { status: 409 }, 'unavailable'],
  ['rate limit', { status: 429, type: 'rate_limit_error' }, 'rate_limit'],
  ['provider unavailable', { status: 503, type: 'provider_error' }, 'unavailable'],
  ['overloaded', { type: 'overloaded_error' }, 'overloaded'],
  ['authentication', { type: 'authentication_error' }, 'authentication'],
  ['permission', { type: 'permission_error' }, 'permission'],
  ['billing', { type: 'billing_error' }, 'billing'],
  ['network timeout', { code: 'ETIMEDOUT' }, 'timeout'],
  ['network reset', { code: 'ECONNRESET' }, 'network'],
] as const;

const nonOperationalFailures = [
  { status: 400, type: 'invalid_request_error' },
  { status: 403, type: 'safety_error' },
  { type: 'content_policy_error' },
  { code: 'UNKNOWN_PRIVATE_CODE' },
  new Error('message text is never classification input'),
  CoachingResponsePayloadSchema.safeParse({}).error,
];

test.each(validPayloadFixtures)(
  'the shared schema accepts a valid %s response mode',
  (_mode, payload) => {
    expect(CoachingResponsePayloadSchema.safeParse(payload).success).toBe(true);
  },
);

test.each(invalidPayloadFixtures)('the shared schema rejects a %s mode-axis conflict', (_name, payload) => {
  expect(CoachingResponsePayloadSchema.safeParse(payload).success).toBe(false);
});

test.each([
  ['empty proposal text', { ...outcomePayloadFixture, proposals: [{ ...outcomePayloadFixture.proposals[0], reason: '' }] }],
  ['whitespace-only proposal text', { ...outcomePayloadFixture, proposals: [{ ...outcomePayloadFixture.proposals[0], reason: '   ' }] }],
  ['oversized proposal text', { ...outcomePayloadFixture, proposals: [{ ...outcomePayloadFixture.proposals[0], reason: 'r'.repeat(COACHING_GATEWAY_LIMITS.maxTextLength + 1) }] }],
  ['malformed outcome timestamp', { ...outcomePayloadFixture, proposals: [{ ...outcomePayloadFixture.proposals[0], candidate: { ...outcomePayloadFixture.proposals[0].candidate, occurredAt: 'not-a-timestamp' } }] }],
  ['oversized outcome ID list', { ...outcomePayloadFixture, proposals: [{ ...outcomePayloadFixture.proposals[0], candidate: { ...outcomePayloadFixture.proposals[0].candidate, goalIds: Array(COACHING_GATEWAY_LIMITS.maxIdListLength + 1).fill('goal-1') } }] }],
  ['invalid outcome ID', { ...outcomePayloadFixture, proposals: [{ ...outcomePayloadFixture.proposals[0], candidate: { ...outcomePayloadFixture.proposals[0].candidate, actionIds: [''] } }] }],
  ['whitespace-only outcome ID', { ...outcomePayloadFixture, proposals: [{ ...outcomePayloadFixture.proposals[0], candidate: { ...outcomePayloadFixture.proposals[0].candidate, actionIds: ['   '] } }] }],
  ['oversized outcome ID', { ...outcomePayloadFixture, proposals: [{ ...outcomePayloadFixture.proposals[0], candidate: { ...outcomePayloadFixture.proposals[0].candidate, actionIds: ['a'.repeat(COACHING_GATEWAY_LIMITS.maxIdLength + 1)] } }] }],
])('the authoritative schema rejects %s', (_name, payload) => {
  expect(CoachingResponsePayloadSchema.safeParse(payload).success).toBe(false);
});

test.each(validPayloadFixtures)(
  'the portable client contract accepts the valid %s response mode',
  (_mode, payload) => {
    expect(firstCoachingResponseContractViolation(portableResponse(payload), requestFixture.requestId)).toBeNull();
  },
);

test.each(invalidPayloadFixtures)(
  'the portable client contract rejects the %s mode-axis conflict',
  (_name, payload) => {
    expect(firstCoachingResponseContractViolation(portableResponse(payload), requestFixture.requestId)).not.toBeNull();
  },
);

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
  const openAISchema = openAIParse.mock.calls[0][0].response_format.json_schema.schema;
  const countObjectProperties = (value: unknown): number => {
    if (Array.isArray(value)) {
      return value.reduce<number>((sum, item) => sum + countObjectProperties(item), 0);
    }
    if (!value || typeof value !== 'object') return 0;
    const record = value as Record<string, unknown>;
    const own = record.properties && typeof record.properties === 'object'
      ? Object.keys(record.properties as Record<string, unknown>).length
      : 0;
    return own + Object.values(record).reduce<number>(
      (sum, item) => sum + countObjectProperties(item),
      0,
    );
  };
  const objectPropertyCount = countObjectProperties(openAISchema);
  expect(objectPropertyCount).toBeLessThanOrEqual(5000);
  expect(openAISchema.definitions?.coaching_response).toBeUndefined();
  expect(JSON.stringify(openAISchema)).not.toMatch(/\"(?:minLength|maxLength)\":/);
  const arraysUseSingleItemSchemas = (value: unknown): boolean => {
    if (Array.isArray(value)) return value.every(arraysUseSingleItemSchemas);
    if (!value || typeof value !== 'object') return true;
    const record = value as Record<string, unknown>;
    if (record.type === 'array' && Array.isArray(record.items)) return false;
    return Object.values(record).every(arraysUseSingleItemSchemas);
  };
  expect(arraysUseSingleItemSchemas(openAISchema)).toBe(true);
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
  const coachBranch = anthropicSchema.oneOf.find((branch: any) => branch.properties.mode.const === 'coach');
  const proposalBranches = coachBranch.properties.proposals.items.oneOf;
  const proposalBranch = (operation: string) => proposalBranches.find(
    (branch: any) => branch.properties.operation.const === operation,
  );
  const textSchema = {
    type: 'string',
    minLength: 1,
    maxLength: COACHING_GATEWAY_LIMITS.maxTextLength,
    pattern: '\\S',
  };
  const idSchema = {
    type: 'string',
    minLength: 1,
    maxLength: COACHING_GATEWAY_LIMITS.maxIdLength,
    pattern: '\\S',
  };
  const timestampSchema = {
    type: 'string',
    maxLength: COACHING_GATEWAY_LIMITS.maxTimestampLength,
    format: 'date-time',
  };
  const proposedMemory = proposalBranch('propose');
  expect(proposedMemory.properties.reason).toEqual(textSchema);
  expect(proposedMemory.properties.candidate.properties.statement).toEqual(textSchema);
  expect(proposedMemory.properties.candidate.properties.sourceMessageIds).toEqual({
    type: 'array', items: idSchema, maxItems: COACHING_GATEWAY_LIMITS.maxIdListLength,
  });
  expect(proposedMemory.properties.candidate.properties.supersedesId).toEqual({
    anyOf: [idSchema, { type: 'null' }],
  });
  const transition = proposalBranch('transition');
  expect(transition.properties.targetId).toEqual(idSchema);
  expect(transition.properties.reason).toEqual(textSchema);
  const support = proposalBranch('support');
  expect(support.properties.targetId).toEqual(idSchema);
  expect(support.properties.sourceMessageId).toEqual(idSchema);
  expect(support.properties.reason).toEqual(textSchema);
  const outcome = proposalBranch('propose-outcome');
  const outcomeGoal = outcome.properties.candidate.oneOf.find(
    (branch: any) => branch.properties.kind.const === 'goal',
  );
  const outcomeEvidence = outcome.properties.candidate.oneOf.find(
    (branch: any) => branch.properties.kind.const === 'evidence',
  );
  expect(outcome.properties.reason).toEqual(textSchema);
  expect(outcomeGoal.properties.title).toEqual(textSchema);
  expect(outcomeGoal.properties.targetDate).toEqual({ anyOf: [timestampSchema, { type: 'null' }] });
  expect(outcomeEvidence.properties.occurredAt).toEqual(timestampSchema);
  expect(outcomeEvidence.properties.goalIds).toEqual({
    type: 'array', items: idSchema, maxItems: COACHING_GATEWAY_LIMITS.maxIdListLength,
  });
  expect(outcomeEvidence.properties.actionIds).toEqual({
    type: 'array', items: idSchema, maxItems: COACHING_GATEWAY_LIMITS.maxIdListLength,
  });
  expect(JSON.stringify(openAIParse.mock.calls[0][0].response_format)).toEqual(
    expect.stringContaining('contextSufficiency'),
  );
},
);

test.each(['openai', 'anthropic'] as const)(
  '%s primary success calls no fallback and reports one settled attempt',
  async (primaryId) => {
    const providers = providerRegistry();
    const observer = attemptObserver();
    const provider = getConfiguredFallbackProvider(environment(primaryId), providers);

    const outcome = await provider.respond(providerInput, observer);

    expect(outcome.result).toEqual(providerResult(primaryId));
    expect(outcome.attempts).toEqual([{
      attemptId: 'primary',
      providerId: primaryId,
      result: providerResult(primaryId),
    }]);
    expect(providers[primaryId].respond).toHaveBeenCalledTimes(1);
    expect(providers[other(primaryId)].respond).not.toHaveBeenCalled();
    expect(observer.beginAttempt.mock.calls).toEqual([['primary']]);
    expect(observer.settleAttempt.mock.calls).toEqual([[
      { attemptId: 'primary', receipt: providerResult(primaryId).usage },
    ]]);
  },
);

test.each(operationalFailures)(
  'one %s primary failure invokes the alternate exactly once',
  async (_name, failure, expectedFailureClass) => {
    const providers = providerRegistry();
    const observer = attemptObserver();
    providers.openai.respond = jest.fn().mockRejectedValue(failure);

    const outcome = await getConfiguredFallbackProvider(
      environment('openai'), providers,
    ).respond(providerInput, observer);

    expect(outcome.result.usage.provider).toBe('anthropic');
    expect(outcome.attempts.map(({ attemptId }) => attemptId)).toEqual([
      'primary', 'fallback',
    ]);
    expect(outcome.attempts[0]).toEqual(expect.objectContaining({
      attemptId: 'primary',
      providerId: 'openai',
      failureClass: expectedFailureClass,
    }));
    expect(outcome.attempts[0]).not.toHaveProperty('result');
    expect(outcome.attempts[1]).toEqual(expect.objectContaining({
      attemptId: 'fallback',
      providerId: 'anthropic',
      result: providerResult('anthropic'),
    }));
    expect(providers.openai.respond).toHaveBeenCalledTimes(1);
    expect(providers.anthropic.respond).toHaveBeenCalledTimes(1);
    expect(observer.beginAttempt.mock.calls).toEqual([['primary'], ['fallback']]);
    expect(observer.settleAttempt.mock.calls).toEqual([
      [{ attemptId: 'primary' }],
      [{ attemptId: 'fallback', receipt: providerResult('anthropic').usage }],
    ]);
  },
);

test.each(['openai', 'anthropic'] as const)(
  '%s primary operational failure calls its configured alternate',
  async (primaryId) => {
    const providers = providerRegistry();
    const observer = attemptObserver();
    providers[primaryId].respond = jest.fn().mockRejectedValue({ status: 503 });

    const outcome = await getConfiguredFallbackProvider(
      environment(primaryId), providers,
    ).respond(providerInput, observer);

    expect(outcome.result.usage.provider).toBe(other(primaryId));
    expect(providers[primaryId].respond).toHaveBeenCalledTimes(1);
    expect(providers[other(primaryId)].respond).toHaveBeenCalledTimes(1);
  },
);

test.each(nonOperationalFailures)(
  'a non-operational primary failure never invokes fallback',
  async (failure) => {
    const providers = providerRegistry();
    const observer = attemptObserver();
    providers.openai.respond = jest.fn().mockRejectedValue(failure);

    await expect(getConfiguredFallbackProvider(
      environment('openai'), providers,
    ).respond(providerInput, observer)).rejects.toBe(failure);

    expect(providers.anthropic.respond).not.toHaveBeenCalled();
    expect(observer.beginAttempt.mock.calls).toEqual([['primary']]);
    expect(observer.settleAttempt.mock.calls).toEqual([[{ attemptId: 'primary' }]]);
  },
);

test('observer settlement failure is not misclassified as a provider failure', async () => {
  const providers = providerRegistry();
  const settlementFailure = new Error('ledger settlement failed');
  const observer = attemptObserver();
  observer.settleAttempt.mockImplementation(() => {
    throw settlementFailure;
  });

  await expect(getConfiguredFallbackProvider(
    environment('openai'), providers,
  ).respond(providerInput, observer)).rejects.toBe(settlementFailure);

  expect(providers.openai.respond).toHaveBeenCalledTimes(1);
  expect(providers.anthropic.respond).not.toHaveBeenCalled();
  expect(observer.settleAttempt).toHaveBeenCalledTimes(1);
});

test('both operational failures expose classifications and attempt IDs but no raw errors', async () => {
  const providers = providerRegistry();
  const observer = attemptObserver();
  providers.openai.respond = jest.fn().mockRejectedValue({
    status: 429,
    type: 'rate_limit_error',
    payload: 'PRIMARY_PROVIDER_SECRET',
  });
  providers.anthropic.respond = jest.fn().mockRejectedValue({
    type: 'overloaded_error',
    payload: 'FALLBACK_PROVIDER_SECRET',
  });

  let thrown: unknown;
  try {
    await getConfiguredFallbackProvider(
      environment('openai'), providers,
    ).respond(providerInput, observer);
  } catch (error) {
    thrown = error;
  }

  expect(thrown).toBeInstanceOf(ContentFreeFallbackError);
  expect(thrown).toMatchObject({
    attempts: [
      { attemptId: 'primary', failureClass: 'rate_limit' },
      { attemptId: 'fallback', failureClass: 'overloaded' },
    ],
  });
  expect(JSON.stringify(thrown)).not.toContain('PRIMARY_PROVIDER_SECRET');
  expect(JSON.stringify(thrown)).not.toContain('FALLBACK_PROVIDER_SECRET');
  expect(observer.beginAttempt.mock.calls).toEqual([['primary'], ['fallback']]);
  expect(observer.settleAttempt.mock.calls).toEqual([
    [{ attemptId: 'primary' }],
    [{ attemptId: 'fallback' }],
  ]);
});

test('fallback invalid output is recoverable without retaining Zod details or payload content', async () => {
  const providers = providerRegistry();
  const observer = attemptObserver();
  const secret = 'FALLBACK_ZOD_SECRET';
  const malformedFallback = CoachingResponsePayloadSchema.safeParse({
    ...coachingPayloadFixture,
    stance: secret,
  });
  if (malformedFallback.success) throw new Error('Expected malformed fallback fixture');
  expect(JSON.stringify(malformedFallback.error)).toContain(secret);
  providers.openai.respond = jest.fn().mockRejectedValue({
    status: 429,
    type: 'rate_limit_error',
  });
  providers.anthropic.respond = jest.fn().mockRejectedValue(malformedFallback.error);

  let thrown: unknown;
  try {
    await getConfiguredFallbackProvider(
      environment('openai'), providers,
    ).respond(providerInput, observer);
  } catch (error) {
    thrown = error;
  }

  expect(thrown).toBeInstanceOf(ContentFreeFallbackInvalidOutputError);
  expect(thrown).toMatchObject({
    code: 'INVALID_COACHING_OUTPUT',
    recoverable: true,
    attempts: [
      { attemptId: 'primary', failureClass: 'rate_limit' },
      { attemptId: 'fallback', failureClass: 'invalid_output' },
    ],
  });
  expect(thrown).not.toHaveProperty('cause');
  expect(thrown).not.toHaveProperty('issues');
  expect(JSON.stringify(thrown)).not.toContain(secret);
  expect(JSON.stringify(thrown)).not.toContain('stance');
  expect(providers.openai.respond).toHaveBeenCalledTimes(1);
  expect(providers.anthropic.respond).toHaveBeenCalledTimes(1);
  expect(observer.settleAttempt.mock.calls).toEqual([
    [{ attemptId: 'primary' }],
    [{ attemptId: 'fallback' }],
  ]);
});

test.each(['openai', 'anthropic'] as const)(
  '%s primary retains provider and model identity in ordered maximum estimates',
  (primaryId) => {
    const providers = providerRegistry();
    const estimates = getConfiguredFallbackProvider(
      environment(primaryId), providers,
    ).estimateMaximumAttempts(providerInput);

    expect(estimates).toEqual([
      {
        attemptId: 'primary',
        receipt: expect.objectContaining({
          provider: primaryId,
          model: `${primaryId}-mock`,
        }),
      },
      {
        attemptId: 'fallback',
        receipt: expect.objectContaining({
          provider: other(primaryId),
          model: `${other(primaryId)}-mock`,
        }),
      },
    ]);
  },
);

test.each(['openai', 'anthropic'] as const)(
  'maximum estimation fails when the %s estimate is unavailable',
  (missingId) => {
    const providers = providerRegistry();
    providers[missingId].estimateMaximumUsage = undefined;

    expect(() => getConfiguredFallbackProvider(environment('openai'), providers)).toThrow(
      `${missingId} provider must estimate maximum usage`,
    );
  },
);

test.each(
  Object.keys(environment('openai')).filter((name) => name !== 'TAISA_COACHING_PROVIDER'),
)('fallback startup fails when %s is absent', (missingName) => {
  const configured = { ...environment('openai') } as Record<string, string | undefined>;
  delete configured[missingName];

  expect(() => getConfiguredFallbackProvider(configured, providerRegistry())).toThrow(
    `${missingName} must be configured`,
  );
});

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

test('Senior Self decides safety, relevance, context sufficiency, then coaching stance', () => {
  const { systemPrompt } = buildSeniorSelfPrompt(requestFixture);

  const safety = systemPrompt.indexOf('1. Safety');
  const relevance = systemPrompt.indexOf('2. Relevance');
  const contextSufficiency = systemPrompt.indexOf('3. Context sufficiency');
  const stance = systemPrompt.indexOf('4. Coaching stance');

  expect(safety).toBeGreaterThanOrEqual(0);
  expect(relevance).toBeGreaterThan(safety);
  expect(contextSufficiency).toBeGreaterThan(relevance);
  expect(stance).toBeGreaterThan(contextSufficiency);
  expect(systemPrompt).toContain('Career-relevant');
  expect(systemPrompt).toContain('Adjacent personal context');
  expect(systemPrompt).toContain("Outside Taisa's scope");
});

test('Senior Self treats ambiguous references as missing context and makes clarify neutral', () => {
  const { systemPrompt } = buildSeniorSelfPrompt(requestFixture);

  for (const referent of ['this', 'that meeting', 'the video', 'what happened earlier']) {
    expect(systemPrompt).toContain(referent);
  }
  expect(systemPrompt).toContain('possible missing referents, not facts');
  expect(systemPrompt).toContain('ask one neutral clarifying question');
  expect(systemPrompt).toContain('Never diagnose or infer emotion');
});

test('Senior Self constrains redirect bridges and permits proposals only while coaching', () => {
  const { systemPrompt } = buildSeniorSelfPrompt(requestFixture);

  expect(systemPrompt).toContain('briefly acknowledge');
  expect(systemPrompt).toContain('at most one optional work bridge');
  expect(systemPrompt).toContain('Only coach responses may carry proposals');
});

test('Senior Self classifies relevance from the current turn before consulting career context', () => {
  const { systemPrompt } = buildSeniorSelfPrompt(requestFixture);

  expect(systemPrompt).toContain(
    'Classify relevance from the primary subject of the current user turn before consulting bounded context.',
  );
  expect(systemPrompt).toContain(
    'Never make a turn career-relevant merely because profile, conversation history, memory, or evidence contains work.',
  );
  expect(systemPrompt).toContain(
    'Use bounded context only after the relevance decision.',
  );
  expect(systemPrompt).toContain(
    "Career-relevant: the primary subject is the user's work, career, professional decisions, workplace relationships, goals, actions, or evidence.",
  );
  expect(systemPrompt).toContain(
    'Adjacent personal context: the primary subject is personal, but the user has stated a concrete effect on their work, wellbeing at work, professional decisions, relationships, or goals.',
  );
  expect(systemPrompt).toContain(
    "Outside Taisa's scope: neither condition above is met.",
  );
});

test('Senior Self applies the approved sufficiency limits before allowing advice or proposals', () => {
  const { systemPrompt } = buildSeniorSelfPrompt(requestFixture);

  expect(systemPrompt).toContain(
    'Sufficient: the response can be grounded without inventing a material fact.',
  );
  expect(systemPrompt).toContain(
    'Partially sufficient: a useful bounded response is possible. Answer only the supported portion and state the material limitation.',
  );
  expect(systemPrompt).toContain(
    'Insufficient: a missing referent, event, participant, purpose, or source is necessary to answer. State what is unknown and ask one neutral clarifying question.',
  );
  expect(systemPrompt).toContain(
    'If clarification is necessary, do not offer advice or propose memory, evidence, goals, or actions.',
  );
  expect(systemPrompt).toContain(
    'A partially sufficient response may propose an outcome only when that proposal is grounded entirely in the supported portion.',
  );
});

test('an off-topic current turn with career profile and history receives a structured redirect', async () => {
  const offTopicRequest: CoachingRequest = {
    ...requestFixture,
    input: 'What is the capital of Ghana?',
    context: {
      profile: {
        currentRole: 'Product Designer',
        currentCompany: 'Taisa',
        careerStage: 'mid',
        coachingStyle: 'direct',
        accountabilityLevel: 'moderate',
        shortTermGoal: 'Lead a design initiative',
        longTermGoal: 'Become a design director',
        currentFocusArea: 'Stakeholder management',
      },
      recentMessages: [
        { role: 'user' as const, content: 'I need to prepare for my design review.' },
        { role: 'assistant' as const, content: 'What decision needs the clearest framing?' },
      ],
      memory: requestFixture.context.memory,
      evidence: requestFixture.context.evidence,
    },
  };
  const provider: CoachingProvider = {
    id: 'openai',
    respond: jest.fn(async (prompt) => {
      expect(JSON.parse(prompt.userPrompt)).toEqual(offTopicRequest);
      return {
        payload: {
          mode: 'redirect' as const,
          relevance: 'outside-scope' as const,
          contextSufficiency: 'sufficient' as const,
          reply: 'I can help when this connects to your work or career.',
          stance: null,
          proposals: [],
        },
        usage: {
          provider: 'openai' as const, model: 'fixture', inputTokens: 10, outputTokens: 4,
          estimatedCostUsd: 0.000052,
        },
      };
    }),
  };

  const response = await requestCoaching(offTopicRequest, provider);

  expect(response).toMatchObject({
    mode: 'redirect', relevance: 'outside-scope', contextSufficiency: 'sufficient',
    stance: null, proposals: [],
  });
  expect(provider.respond).toHaveBeenCalledTimes(1);
});

test.each([
  [{ status: 408 }, 'timeout'],
  [{ status: 409 }, 'unavailable'],
  [{ status: 429, type: 'rate_limit_error' }, 'rate_limit'],
  [{ status: 503, type: 'provider_error' }, 'unavailable'],
  [{ type: 'overloaded_error' }, 'overloaded'],
  [{ type: 'authentication_error' }, 'authentication'],
  [{ type: 'permission_error' }, 'permission'],
  [{ type: 'billing_error' }, 'billing'],
  [{ code: 'ETIMEDOUT' }, 'timeout'],
  [{ code: 'ECONNRESET' }, 'network'],
])('classifies an allowlisted operational failure', (error, expected) => {
  expect(classifyOperationalProviderFailure(error)).toBe(expected);
});

test.each([
  { status: 400, type: 'invalid_request_error' },
  { status: 400, type: 'provider_error' },
  { status: 403, type: 'safety_error' },
  { status: 503, type: 'content_policy_error' },
  { status: 503, type: 'invalid_request_error' },
  { status: 503, type: 'safety_error' },
  { type: 'content_policy_error' },
  { code: 'UNKNOWN_PRIVATE_CODE' },
  new Error('message text is never classification input'),
])('fails closed for non-operational or unknown errors', (error) => {
  expect(classifyOperationalProviderFailure(error)).toBeNull();
});
