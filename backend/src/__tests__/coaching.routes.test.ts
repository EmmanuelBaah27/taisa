import express from 'express';
import request from 'supertest';

jest.mock('../db/connection', () => {
  throw new Error('The stateless coaching route must not import the backend database');
});

jest.mock('../services/coaching/coachingGateway', () => ({
  estimateConfiguredCoachingAttempts: jest.fn().mockReturnValue([
    {
      attemptId: 'primary',
      receipt: {
        provider: 'openai',
        model: 'openai-mock',
        inputTokens: 100,
        outputTokens: 100,
        estimatedCostUsd: 0.03,
      },
    },
    {
      attemptId: 'fallback',
      receipt: {
        provider: 'anthropic',
        model: 'anthropic-mock',
        inputTokens: 100,
        outputTokens: 100,
        estimatedCostUsd: 0.02,
      },
    },
  ]),
  requestCoaching: jest.fn().mockImplementation(async (_request, _provider, observer) => {
    const response = {
      requestId: '11111111-1111-4111-8111-111111111111',
      mode: 'coach',
      relevance: 'career-relevant',
      contextSufficiency: 'sufficient',
      reply: 'What changed?',
      stance: 'nudge',
      proposals: [],
      usage: {
        provider: 'openai',
        model: 'openai-mock',
        inputTokens: 5,
        outputTokens: 3,
        estimatedCostUsd: 0.01,
      },
    };
    observer.beginAttempt('primary');
    observer.settleAttempt({ attemptId: 'primary', receipt: response.usage });
    return {
      response,
      attempts: [{
        attemptId: 'primary',
        providerId: 'openai',
        result: { payload: response, usage: response.usage },
      }],
    };
  }),
}));

jest.mock('../services/usage/costLedger', () => {
  const actual = jest.requireActual('../services/usage/costLedger');
  return {
    ...actual,
    readCostCeilings: jest.fn().mockReturnValue({
      perRequestUsd: 0.05,
      dailyUsd: 1,
      monthlyUsd: 10,
    }),
    reserveAttempts: jest.fn().mockReturnValue({
      beginAttempt: jest.fn(),
      settleAttempt: jest.fn(),
      release: jest.fn(),
    }),
    recordUsage: jest.fn(),
  };
});

import coachingRouter from '../routes/coaching';

const app = express();
app.use(express.json());
app.use('/api/v1/coaching', coachingRouter);

const memory = {
  id: 'mem-1',
  type: 'goal',
  statement: 'Become a Staff Designer',
  provenance: 'user-confirmed',
  lifecycle: 'active',
  confidence: 'established',
  createdAt: '2026-08-09T00:00:00Z',
  confirmedAt: '2026-08-09T00:00:00Z',
  lastSupportedAt: '2026-08-09T00:00:00Z',
  statusChangedAt: '2026-08-09T00:00:00Z',
  sourceMessageIds: ['m1'],
};

const message = { role: 'user', content: 'I may prefer management' };

const evidence = {
  id: 'ev-1',
  statement: 'Led the product critique',
  occurredAt: '2026-08-08T00:00:00Z',
  sourceMessageIds: ['m1'],
  goalIds: ['mem-1'],
  actionIds: [],
};

const profile = {
  currentRole: 'Senior Product Designer',
  currentCompany: 'Taisa',
  careerStage: 'senior',
  coachingStyle: 'direct',
  accountabilityLevel: 'moderate',
  currentFocusArea: '',
  shortTermGoal: 'Grow into staff scope',
  longTermGoal: '',
};

const validRequest = {
  requestId: '11111111-1111-4111-8111-111111111111',
  submittedAt: '2026-08-09T00:00:00Z',
  input: 'I may prefer management',
  context: {
    profile,
    recentMessages: [message],
    memory: [memory],
    evidence: [evidence],
  },
};

beforeEach(() => {
  jest.clearAllMocks();
});

test('accepts supplied context without loading backend user data', async () => {
  const res = await request(app)
    .post('/api/v1/coaching/respond')
    .set('x-user-id', 'device-1')
    .send(validRequest);

  expect(res.status).toBe(200);
  expect(res.body.data.reply).toBe('What changed?');
  expect(res.body.data).toMatchObject({
    mode: 'coach',
    relevance: 'career-relevant',
    contextSufficiency: 'sufficient',
    stance: 'nudge',
    proposals: [],
  });
  const gateway = jest.requireMock('../services/coaching/coachingGateway');
  const usageLedger = jest.requireMock('../services/usage/costLedger');
  const reservation = usageLedger.reserveAttempts.mock.results[0].value;
  expect(gateway.requestCoaching).toHaveBeenCalledWith(validRequest, undefined, reservation);
  expect(usageLedger.reserveAttempts).toHaveBeenCalledWith(
    gateway.estimateConfiguredCoachingAttempts.mock.results[0].value,
    {
      perRequestUsd: 0.05,
      dailyUsd: 1,
      monthlyUsd: 10,
    },
  );
  expect(usageLedger.reserveAttempts.mock.invocationCallOrder[0]).toBeLessThan(
    gateway.requestCoaching.mock.invocationCallOrder[0],
  );
  expect(reservation.beginAttempt.mock.calls).toEqual([['primary']]);
  expect(reservation.settleAttempt.mock.calls).toEqual([[
    { attemptId: 'primary', receipt: res.body.data.usage },
  ]]);
  expect(reservation.beginAttempt).not.toHaveBeenCalledWith('fallback');
  expect(res.body.data).not.toHaveProperty('attempts');
});

test('settles failed primary conservatively then commits fallback actual usage', async () => {
  const gateway = jest.requireMock('../services/coaching/coachingGateway');
  const usageLedger = jest.requireMock('../services/usage/costLedger');
  const reservation = {
    beginAttempt: jest.fn(),
    settleAttempt: jest.fn(),
    release: jest.fn(),
  };
  usageLedger.reserveAttempts.mockReturnValueOnce(reservation);
  gateway.requestCoaching.mockImplementationOnce(async (_request, _provider, observer) => {
    const fallbackUsage = {
      provider: 'anthropic',
      model: 'anthropic-mock',
      inputTokens: 7,
      outputTokens: 4,
      estimatedCostUsd: 0.015,
    };
    observer.beginAttempt('primary');
    observer.settleAttempt({ attemptId: 'primary' });
    observer.beginAttempt('fallback');
    observer.settleAttempt({ attemptId: 'fallback', receipt: fallbackUsage });
    return {
      response: {
        requestId: validRequest.requestId,
        mode: 'coach',
        relevance: 'career-relevant',
        contextSufficiency: 'sufficient',
        reply: 'Fallback response',
        stance: 'nudge',
        proposals: [],
        usage: fallbackUsage,
      },
      attempts: [
        { attemptId: 'primary', providerId: 'openai', failureClass: 'rate_limit' },
        {
          attemptId: 'fallback',
          providerId: 'anthropic',
          result: { payload: {}, usage: fallbackUsage },
        },
      ],
    };
  });

  const res = await request(app)
    .post('/api/v1/coaching/respond')
    .set('x-user-id', 'device-1')
    .send(validRequest);

  expect(res.status).toBe(200);
  expect(res.body.data.usage.provider).toBe('anthropic');
  expect(reservation.beginAttempt.mock.calls).toEqual([['primary'], ['fallback']]);
  expect(reservation.settleAttempt.mock.calls).toEqual([
    [{ attemptId: 'primary' }],
    [{ attemptId: 'fallback', receipt: res.body.data.usage }],
  ]);
});

test.each([
  ['primary', 'openai'],
  ['fallback', 'anthropic'],
] as const)(
  'returns a paid %s success when actual usage exceeds its conservative reservation',
  async (answeringAttempt, answeringProvider) => {
    const gateway = jest.requireMock('../services/coaching/coachingGateway');
    const usageLedger = jest.requireMock('../services/usage/costLedger');
    const warning = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    const reservation = {
      beginAttempt: jest.fn(),
      settleAttempt: jest.fn((settlement) => {
        if (settlement.receipt) {
          throw new usageLedger.UsageExceedsReservationError(
            0.001,
            settlement.receipt.estimatedCostUsd,
          );
        }
      }),
      release: jest.fn(),
    };
    const providerUsage = (provider: 'openai' | 'anthropic') => ({
      provider,
      model: `${provider}-mock`,
      inputTokens: 7,
      outputTokens: 4,
      estimatedCostUsd: 0.015,
    });
    const providerResult = (provider: 'openai' | 'anthropic') => ({
      payload: {
        mode: 'coach' as const,
        relevance: 'career-relevant' as const,
        contextSufficiency: 'sufficient' as const,
        reply: `${provider} response`,
        stance: 'nudge' as const,
        proposals: [],
      },
      usage: providerUsage(provider),
    });
    const providers = {
      openai: {
        id: 'openai' as const,
        estimateMaximumUsage: jest.fn(() => providerUsage('openai')),
        respond: answeringAttempt === 'primary'
          ? jest.fn().mockResolvedValue(providerResult('openai'))
          : jest.fn().mockRejectedValue({ status: 503 }),
      },
      anthropic: {
        id: 'anthropic' as const,
        estimateMaximumUsage: jest.fn(() => providerUsage('anthropic')),
        respond: jest.fn().mockResolvedValue(providerResult('anthropic')),
      },
    };
    const environment = {
      TAISA_COACHING_PROVIDER: 'openai',
      TAISA_OPENAI_MODEL: 'openai-mock',
      TAISA_OPENAI_INPUT_PRICE_USD_PER_MILLION_TOKENS: '1',
      TAISA_OPENAI_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '1',
      TAISA_OPENAI_MAX_OUTPUT_TOKENS: '100',
      TAISA_OPENAI_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD: '10',
      TAISA_ANTHROPIC_MODEL: 'anthropic-mock',
      TAISA_ANTHROPIC_INPUT_PRICE_USD_PER_MILLION_TOKENS: '1',
      TAISA_ANTHROPIC_OUTPUT_PRICE_USD_PER_MILLION_TOKENS: '1',
      TAISA_ANTHROPIC_MAX_OUTPUT_TOKENS: '100',
      TAISA_ANTHROPIC_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD: '10',
    };
    const { getConfiguredFallbackProvider } = jest.requireActual(
      '../services/coaching/fallbackProvider',
    );
    const actualGateway = jest.requireActual('../services/coaching/coachingGateway');
    const provider = getConfiguredFallbackProvider(environment, providers);
    usageLedger.reserveAttempts.mockReturnValueOnce(reservation);
    gateway.requestCoaching.mockImplementationOnce((coachingRequest, _provider, observer) =>
      actualGateway.requestCoaching(coachingRequest, provider, observer),
    );

    const res = await request(app)
      .post('/api/v1/coaching/respond')
      .set('x-user-id', 'device-1')
      .send(validRequest);

    expect(res.status).toBe(200);
    expect(res.body.data.usage.provider).toBe(answeringProvider);
    expect(res.body.data).not.toHaveProperty('attempts');
    expect(providers.openai.respond).toHaveBeenCalledTimes(1);
    expect(providers.anthropic.respond).toHaveBeenCalledTimes(
      answeringAttempt === 'fallback' ? 1 : 0,
    );
    expect(warning).toHaveBeenCalledWith(
      '[Taisa diagnostic] COACHING_USAGE_EXCEEDED_RESERVATION',
    );
    warning.mockRestore();
  },
);

test('generic provider failures expose only an allowlisted operational classification', async () => {
  const gateway = jest.requireMock('../services/coaching/coachingGateway');
  gateway.requestCoaching.mockRejectedValueOnce(Object.assign(
    new Error('private provider payload'),
    { code: 'sk-secret-private-details', status: 503, type: 'provider_error' },
  ));

  const res = await request(app)
    .post('/api/v1/coaching/respond')
    .set('x-user-id', 'device-1')
    .send(validRequest);

  expect(res.status).toBe(500);
  expect(res.body.error.code).toBe(
    'COACHING_FAILED_HTTP_503_PROVIDER_ERROR',
  );
  expect(JSON.stringify(res.body)).not.toContain('private provider payload');
  expect(JSON.stringify(res.body)).not.toContain('SECRET_PRIVATE_DETAILS');
});

test('rejects a coaching request at the combined cost ceiling before either provider', async () => {
  const usageLedger = jest.requireMock('../services/usage/costLedger');
  usageLedger.reserveAttempts.mockImplementationOnce(() => {
    throw new usageLedger.CostLimitError();
  });

  const res = await request(app)
    .post('/api/v1/coaching/respond')
    .set('x-user-id', 'device-1')
    .send(validRequest);

  expect(res.status).toBe(429);
  expect(res.body.error.code).toBe('COST_LIMIT_EXCEEDED');
  expect(jest.requireMock('../services/coaching/coachingGateway').requestCoaching).not.toHaveBeenCalled();
});

test('rejects combined conservative request estimates above the per-request ceiling', async () => {
  const gateway = jest.requireMock('../services/coaching/coachingGateway');
  const usageLedger = jest.requireMock('../services/usage/costLedger');
  gateway.estimateConfiguredCoachingAttempts.mockReturnValueOnce([
    {
      attemptId: 'primary',
      receipt: { provider: 'openai', model: 'mock', estimatedCostUsd: 0.03 },
    },
    {
      attemptId: 'fallback',
      receipt: { provider: 'anthropic', model: 'mock', estimatedCostUsd: 0.021 },
    },
  ]);
  usageLedger.reserveAttempts.mockImplementationOnce((attempts: any[], ceilings: any) => {
    const combined = attempts.reduce((total, attempt) => total + attempt.receipt.estimatedCostUsd, 0);
    if (combined > ceilings.perRequestUsd) throw new usageLedger.CostLimitError();
  });

  const res = await request(app)
    .post('/api/v1/coaching/respond')
    .set('x-user-id', 'device-1')
    .send(validRequest);

  expect(res.status).toBe(429);
  expect(gateway.requestCoaching).not.toHaveBeenCalled();
});

test.each([
  ['input', { ...validRequest, input: 'x'.repeat(4001) }],
  [
    'memory',
    { ...validRequest, context: { ...validRequest.context, memory: Array(51).fill(memory) } },
  ],
  [
    'messages',
    {
      ...validRequest,
      context: { ...validRequest.context, recentMessages: Array(21).fill(message) },
    },
  ],
  [
    'evidence',
    { ...validRequest, context: { ...validRequest.context, evidence: Array(9).fill(evidence) } },
  ],
])('rejects oversized %s', async (_name, body) => {
  const res = await request(app)
    .post('/api/v1/coaching/respond')
    .set('x-user-id', 'device-1')
    .send(body);

  expect(res.status).toBe(400);
  expect(jest.requireMock('../services/coaching/coachingGateway').requestCoaching).not.toHaveBeenCalled();
});

test.each([
  [
    'archive-shaped profile',
    { ...validRequest, context: { ...validRequest.context, profile: { ...profile, id: 'profile-1' } } },
  ],
  [
    'profile field',
    {
      ...validRequest,
      context: { ...validRequest.context, profile: { ...profile, currentRole: 'x'.repeat(201) } },
    },
  ],
  [
    'memory statement',
    {
      ...validRequest,
      context: {
        ...validRequest.context,
        memory: [{ ...memory, statement: 'x'.repeat(4001) }],
      },
    },
  ],
  [
    'memory source IDs',
    {
      ...validRequest,
      context: {
        ...validRequest.context,
        memory: [{ ...memory, sourceMessageIds: Array(51).fill('m1') }],
      },
    },
  ],
  [
    'memory ID',
    {
      ...validRequest,
      context: { ...validRequest.context, memory: [{ ...memory, id: 'x'.repeat(129) }] },
    },
  ],
  [
    'evidence statement',
    {
      ...validRequest,
      context: {
        ...validRequest.context,
        evidence: [{ ...evidence, statement: 'x'.repeat(4001) }],
      },
    },
  ],
  [
    'evidence source IDs',
    {
      ...validRequest,
      context: {
        ...validRequest.context,
        evidence: [{ ...evidence, sourceMessageIds: Array(51).fill('m1') }],
      },
    },
  ],
  [
    'evidence goal IDs',
    {
      ...validRequest,
      context: {
        ...validRequest.context,
        evidence: [{ ...evidence, goalIds: Array(51).fill('goal-1') }],
      },
    },
  ],
  [
    'evidence action IDs',
    {
      ...validRequest,
      context: {
        ...validRequest.context,
        evidence: [{ ...evidence, actionIds: Array(51).fill('action-1') }],
      },
    },
  ],
])('rejects oversized nested %s', async (_name, body) => {
  const res = await request(app)
    .post('/api/v1/coaching/respond')
    .set('x-user-id', 'device-1')
    .send(body);

  expect(res.status).toBe(400);
  expect(jest.requireMock('../services/coaching/coachingGateway').requestCoaching).not.toHaveBeenCalled();
});

test('returns a recoverable error when structured provider output is invalid', async () => {
  jest.requireMock('../services/coaching/coachingGateway').requestCoaching.mockRejectedValueOnce({
    code: 'INVALID_COACHING_OUTPUT',
    recoverable: true,
  });

  const res = await request(app)
    .post('/api/v1/coaching/respond')
    .set('x-user-id', 'device-1')
    .send(validRequest);

  expect(res.status).toBe(502);
  expect(res.body).toEqual({
    success: false,
    error: {
      code: 'INVALID_COACHING_OUTPUT',
      message: 'The coaching provider returned an invalid structured response',
      recoverable: true,
    },
  });
});
