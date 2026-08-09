import express from 'express';
import request from 'supertest';

jest.mock('../services/coaching/coachingGateway', () => ({
  requestCoaching: jest.fn().mockResolvedValue({
    requestId: '11111111-1111-4111-8111-111111111111',
    reply: 'What changed?',
    stance: 'nudge',
    proposals: [],
    usage: { provider: 'anthropic', model: 'mock', estimatedCostUsd: 0 },
  }),
}));

import { coachingRateLimit } from '../middleware/coachingRateLimit';
import coachingRouter from '../routes/coaching';

const app = express();
app.use(express.json());
app.use('/api/v1/coaching', coachingRateLimit, coachingRouter);

const validRequest = {
  requestId: '11111111-1111-4111-8111-111111111111',
  submittedAt: '2026-08-09T00:00:00Z',
  input: 'I may prefer management',
  context: { profile: null, recentMessages: [], memory: [], evidence: [] },
};

test('shares the coaching limit by device ID while distinct device IDs stay independent', async () => {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const response = await request(app)
      .post('/api/v1/coaching/respond')
      .set('x-user-id', 'rate-device-1')
      .send(validRequest);
    expect(response.status).toBe(200);
  }

  const limited = await request(app)
    .post('/api/v1/coaching/respond')
    .set('x-user-id', 'rate-device-1')
    .send(validRequest);
  const independent = await request(app)
    .post('/api/v1/coaching/respond')
    .set('x-user-id', 'rate-device-2')
    .send(validRequest);

  expect(limited.status).toBe(429);
  expect(independent.status).toBe(200);
});

test('does not treat the device header as authorization', async () => {
  const response = await request(app).post('/api/v1/coaching/respond').send(validRequest);
  expect(response.status).toBe(200);
});
