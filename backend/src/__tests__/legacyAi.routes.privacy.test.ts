import express from 'express';
import request from 'supertest';

const mockEntry = {
  id: 'entry-1',
  user_id: 'u1',
  raw_transcript: 'private entry transcript',
  edited_transcript: null,
};

const mockProfile = {
  id: 'u1',
  current_role: 'Designer',
  current_company: 'Private Company',
  industry: 'Technology',
  years_of_experience: 10,
  career_stage: 'senior',
  short_term_goal: 'private goal',
  long_term_goal: 'private long goal',
  current_focus_area: 'private focus',
  coaching_style: 'direct',
  accountability_level: 'moderate',
  growth_trajectory: 'steady',
  open_action_item_count: 0,
  total_entry_count: 1,
  last_entry_at: null,
  created_at: '2026-08-09T00:00:00Z',
  updated_at: '2026-08-09T00:00:00Z',
};

const mockRun = jest.fn();
const mockPrepare = jest.fn((sql: string) => ({
  get: jest.fn(() => {
    if (sql.includes('FROM journal_entries WHERE id')) return mockEntry;
    if (sql.includes('FROM users WHERE id')) return mockProfile;
    return undefined;
  }),
  all: jest.fn(() => {
    if (sql.includes('FROM journal_entries je LEFT JOIN entry_analyses')) {
      return [
        {
          recorded_at: '2026-08-09T00:00:00Z',
          wins: '[]',
          challenges: '[]',
          momentum_signal: 'steady',
          sentiment: 'neutral',
          energy_level: 3,
          coach_note: 'private coach note',
        },
      ];
    }
    return [];
  }),
  run: mockRun,
}));

jest.mock('../db/connection', () => ({
  getDb: jest.fn(() => ({ prepare: mockPrepare })),
}));

jest.mock('../services/claude/journalAgent', () => ({
  analyzeEntry: jest.fn().mockRejectedValue(new Error('provider payload: secret-analysis')),
}));

jest.mock('../services/claude/chatAgent', () => ({
  startSession: jest.fn(),
}));

jest.mock('../services/claude/performanceReviewAgent', () => ({
  analyzePerformanceReview: jest
    .fn()
    .mockRejectedValue(new Error('provider payload: secret-review')),
}));

jest.mock('../services/claude/client', () => ({
  MOCK_AI: false,
  parseAnthropicError: jest.fn(() => ({ code: 'AI_ERROR', message: 'provider secret' })),
  callClaudeJson: jest.fn().mockRejectedValue(new Error('provider payload: secret-trajectory')),
}));

import { requestContext } from '../middleware/requestContext';
import analyzeRouter from '../routes/analyze';
import reviewsRouter from '../routes/reviews';
import trajectoryRouter from '../routes/trajectory';

const app = express();
app.use(requestContext);
app.use(express.json());
app.use('/api/v1/analyze', analyzeRouter);
app.use('/api/v1/reviews', reviewsRouter);
app.use('/api/v1/trajectory', trajectoryRouter);

describe.each([
  {
    name: 'analyze',
    request: () => request(app).post('/api/v1/analyze/entry-1').set('x-user-id', 'u1'),
    secret: 'secret-analysis',
    publicMessage: 'Unable to analyze entry',
  },
  {
    name: 'reviews',
    request: () =>
      request(app)
        .post('/api/v1/reviews')
        .set('x-user-id', 'u1')
        .send({ rawText: 'private review body' }),
    secret: 'secret-review',
    publicMessage: 'Unable to analyze performance review',
  },
  {
    name: 'trajectory',
    request: () =>
      request(app).post('/api/v1/trajectory/generate').set('x-user-id', 'u1'),
    secret: 'secret-trajectory',
    publicMessage: 'Unable to generate trajectory',
  },
])('$name provider failure', ({ request: makeRequest, secret, publicMessage }) => {
  test('logs only content-free error metadata and returns fixed public text', async () => {
    const requestLog = jest.spyOn(console, 'info').mockImplementation(() => undefined);
    const errorLog = jest.spyOn(console, 'error').mockImplementation(() => undefined);

    const response = await makeRequest();

    expect(response.status).toBe(500);
    expect(response.body).toEqual({
      success: false,
      error: { code: 'AI_ERROR', message: publicMessage },
    });
    const logs = `${requestLog.mock.calls.flat().join(' ')} ${errorLog.mock.calls.flat().join(' ')}`;
    expect(logs).not.toContain(secret);
    expect(logs).not.toContain('private review body');
    expect(JSON.stringify(response.body)).not.toContain(secret);
    errorLog.mockRestore();
    requestLog.mockRestore();
  });
});
