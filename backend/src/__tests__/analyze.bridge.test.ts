import request from 'supertest';
import express from 'express';

const mockAnalysis = {
  id: 'a1',
  summary: 'Test summary',
  wins: [],
  challenges: [],
  coachNote: 'Great session.',
  actionItems: [],
  themes: [],
  sentiment: 'positive',
  energyLevel: 4,
  momentumSignal: 'steady',
};

const mockEntry = {
  id: 'entry-1',
  user_id: 'u1',
  raw_transcript: 'Test transcript',
  edited_transcript: 'Test transcript',
  status: 'pending',
};

// Mock DB so the route can find the entry and insert messages without a real DB
const mockRun = jest.fn();
const mockGet = jest.fn().mockReturnValue(mockEntry);
const mockPrepare = jest.fn(() => ({ get: mockGet, run: mockRun }));

jest.mock('../db/connection', () => ({
  getDb: jest.fn(() => ({ prepare: mockPrepare })),
}));

jest.mock('../services/claude/journalAgent', () => ({
  analyzeEntry: jest.fn().mockResolvedValue(mockAnalysis),
}));

jest.mock('../services/claude/chatAgent', () => ({
  startSession: jest.fn().mockResolvedValue('mock-session-id'),
}));

import analyzeRouter from '../routes/analyze';

const app = express();
app.use(express.json());
app.use('/api/v1/analyze', analyzeRouter);

describe('POST /api/v1/analyze/:entryId bridge', () => {
  test('returns sessionId alongside analysis', async () => {
    const res = await request(app)
      .post('/api/v1/analyze/entry-1')
      .set('x-user-id', 'u1');
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveProperty('sessionId');
    expect(res.body.data.sessionId).toBe('mock-session-id');
  });

  test('returns 401 without x-user-id', async () => {
    const res = await request(app).post('/api/v1/analyze/entry-1');
    expect(res.status).toBe(401);
  });
});
