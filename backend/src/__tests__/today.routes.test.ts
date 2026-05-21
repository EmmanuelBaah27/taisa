import request from 'supertest';
import express from 'express';

// Mock DB with enough data for all three endpoints
const mockUser = { current_focus_area: 'Shipping the design system' };

const mockDbState = {
  user: mockUser as any,
  actionItems: [] as any[],
  themes: [] as any[],
  entries: [] as any[],
  analyses: [] as any[],
};

const mockDb = {
  prepare: jest.fn((sql: string) => ({
    get: jest.fn((...args: any[]) => {
      if (sql.includes('SELECT current_focus_area FROM users')) return mockDbState.user;
      if (sql.includes('SELECT last_entry_at FROM users')) return { last_entry_at: new Date().toISOString() };
      if (sql.includes('SELECT id FROM users')) return mockDbState.user;
      if (sql.includes('SELECT COUNT(*)')) return { c: 0 };
      if (sql.includes('FROM action_items') && !sql.includes('all')) return null;
      if (sql.includes('FROM career_themes') && !sql.includes('all')) return null;
      if (sql.includes('FROM entry_analyses') && !sql.includes('all')) return null;
      return null;
    }),
    all: jest.fn((...args: any[]) => {
      if (sql.includes('FROM career_themes')) return mockDbState.themes;
      if (sql.includes('FROM action_items')) return mockDbState.actionItems;
      if (sql.includes('FROM entry_analyses')) return mockDbState.analyses;
      return [];
    }),
    run: jest.fn(),
  })),
};

jest.mock('../db/connection', () => ({
  getDb: jest.fn(() => mockDb),
}));

import todayRouter from '../routes/today';

const app = express();
app.use(express.json());
app.use('/api/v1/today', todayRouter);

describe('GET /api/v1/today/card', () => {
  test('returns 401 without x-user-id', async () => {
    const res = await request(app).get('/api/v1/today/card');
    expect(res.status).toBe(401);
  });

  test('returns card or null with valid userId', async () => {
    const res = await request(app)
      .get('/api/v1/today/card')
      .set('x-user-id', 'u1');
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data).toHaveProperty('card');
  });
});

describe('GET /api/v1/today/digest', () => {
  test('returns 401 without x-user-id', async () => {
    const res = await request(app).get('/api/v1/today/digest');
    expect(res.status).toBe(401);
  });

  test('returns showDigest boolean', async () => {
    const res = await request(app)
      .get('/api/v1/today/digest')
      .set('x-user-id', 'u1');
    expect(res.status).toBe(200);
    expect(typeof res.body.data.showDigest).toBe('boolean');
  });
});

describe('GET /api/v1/today/you', () => {
  test('returns 401 without x-user-id', async () => {
    const res = await request(app).get('/api/v1/today/you');
    expect(res.status).toBe(401);
  });

  test('returns you profile data', async () => {
    const res = await request(app)
      .get('/api/v1/today/you')
      .set('x-user-id', 'u1');
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveProperty('currentFocus');
    expect(res.body.data).toHaveProperty('themes');
    expect(res.body.data).toHaveProperty('openLoops');
  });
});
