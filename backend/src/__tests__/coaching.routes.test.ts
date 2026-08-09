import express from 'express';
import request from 'supertest';

jest.mock('../db/connection', () => {
  throw new Error('The stateless coaching route must not import the backend database');
});

jest.mock('../services/coaching/coachingGateway', () => ({
  requestCoaching: jest.fn().mockResolvedValue({
    requestId: '11111111-1111-4111-8111-111111111111',
    reply: 'What changed?',
    stance: 'nudge',
    proposals: [],
    usage: {
      provider: 'anthropic',
      model: 'mock',
      inputTokens: 5,
      outputTokens: 3,
      estimatedCostUsd: 0,
    },
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
    reserveCost: jest.fn().mockReturnValue({ release: jest.fn() }),
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
  expect(jest.requireMock('../services/coaching/coachingGateway').requestCoaching).toHaveBeenCalledWith(validRequest);
  const usageLedger = jest.requireMock('../services/usage/costLedger');
  expect(usageLedger.reserveCost).toHaveBeenCalledWith(0.05, {
    perRequestUsd: 0.05,
    dailyUsd: 1,
    monthlyUsd: 10,
  });
  expect(usageLedger.reserveCost.mock.invocationCallOrder[0]).toBeLessThan(
    jest.requireMock('../services/coaching/coachingGateway').requestCoaching.mock.invocationCallOrder[0],
  );
  expect(jest.requireMock('../services/usage/costLedger').recordUsage).toHaveBeenCalledWith(
    res.body.data.usage,
  );
});

test('rejects a coaching request at the shared cost ceiling before the provider', async () => {
  const usageLedger = jest.requireMock('../services/usage/costLedger');
  usageLedger.reserveCost.mockImplementationOnce(() => {
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
