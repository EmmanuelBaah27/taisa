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

const validRequest = {
  requestId: '11111111-1111-4111-8111-111111111111',
  submittedAt: '2026-08-09T00:00:00Z',
  input: 'I may prefer management',
  context: {
    profile: null,
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
