import request from 'supertest';
import express from 'express';

jest.mock('../services/claude/chatAgent', () => ({
  startSession: jest.fn().mockResolvedValue('mock-session-id'),
  sendMessage: jest.fn().mockResolvedValue('Here is my coaching response.'),
  getMessages: jest.fn().mockResolvedValue([
    { id: 'm1', role: 'user', content: 'Hello', created_at: '2026-01-01T00:00:01Z' },
    { id: 'm2', role: 'assistant', content: 'Hi there!', created_at: '2026-01-01T00:00:02Z' },
  ]),
}));

import chatRouter from '../routes/chat';
import { requestContext } from '../middleware/requestContext';

const app = express();
app.use(requestContext);
app.use(express.json());
app.use('/api/v1/chat', chatRouter);

let requestLogSpy: jest.SpyInstance;

beforeAll(() => {
  requestLogSpy = jest.spyOn(console, 'info').mockImplementation(() => undefined);
});

afterAll(() => {
  requestLogSpy.mockRestore();
});

describe('POST /api/v1/chat/session/start', () => {
  test('returns sessionId with valid userId', async () => {
    const res = await request(app)
      .post('/api/v1/chat/session/start')
      .set('x-user-id', 'u1')
      .send({});
    expect(res.status).toBe(201);
    expect(res.body.success).toBe(true);
    expect(res.body.data.sessionId).toBe('mock-session-id');
  });

  test('returns 401 without x-user-id header', async () => {
    const res = await request(app)
      .post('/api/v1/chat/session/start')
      .send({});
    expect(res.status).toBe(401);
  });

  test('accepts optional entryId in body', async () => {
    const { startSession } = require('../services/claude/chatAgent');
    (startSession as jest.Mock).mockClear();
    const res = await request(app)
      .post('/api/v1/chat/session/start')
      .set('x-user-id', 'u1')
      .send({ entryId: 'entry-abc' });
    expect(res.status).toBe(201);
    expect(startSession).toHaveBeenCalledWith({ userId: 'u1', entryId: 'entry-abc' });
  });

  test('rejects entryId that is not a string', async () => {
    const res = await request(app)
      .post('/api/v1/chat/session/start')
      .set('x-user-id', 'u1')
      .send({ entryId: 123 });
    expect(res.status).toBe(400);
  });
});

describe('POST /api/v1/chat/message', () => {
  test('returns reply with valid body', async () => {
    const res = await request(app)
      .post('/api/v1/chat/message')
      .set('x-user-id', 'u1')
      .send({ sessionId: 'sess1', message: 'Hello coach' });
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.reply).toBe('Here is my coaching response.');
  });

  test('returns 400 if sessionId is missing', async () => {
    const res = await request(app)
      .post('/api/v1/chat/message')
      .set('x-user-id', 'u1')
      .send({ message: 'Hello' });
    expect(res.status).toBe(400);
  });

  test('returns 400 if message exceeds 4000 chars', async () => {
    const res = await request(app)
      .post('/api/v1/chat/message')
      .set('x-user-id', 'u1')
      .send({ sessionId: 'sess1', message: 'a'.repeat(4001) });
    expect(res.status).toBe(400);
  });

  test('returns 400 if message is empty string', async () => {
    const res = await request(app)
      .post('/api/v1/chat/message')
      .set('x-user-id', 'u1')
      .send({ sessionId: 'sess1', message: '' });
    expect(res.status).toBe(400);
  });

  test('returns 401 without x-user-id header', async () => {
    const res = await request(app)
      .post('/api/v1/chat/message')
      .send({ sessionId: 'sess1', message: 'Hello' });
    expect(res.status).toBe(401);
  });

  test('returns 404 when sendMessage throws Session not found', async () => {
    const { sendMessage } = require('../services/claude/chatAgent');
    (sendMessage as jest.Mock).mockRejectedValueOnce(new Error('Session not found'));
    const res = await request(app)
      .post('/api/v1/chat/message')
      .set('x-user-id', 'u1')
      .send({ sessionId: 'bad-sess', message: 'Hello' });
    expect(res.status).toBe(404);
  });

  test('does not log submitted content or provider payloads when messaging fails', async () => {
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => undefined);
    const { sendMessage } = require('../services/claude/chatAgent');
    (sendMessage as jest.Mock).mockRejectedValueOnce(
      new Error('provider payload contains private coaching message'),
    );

    const res = await request(app)
      .post('/api/v1/chat/message')
      .set('x-user-id', 'u1')
      .send({ sessionId: 'sess1', message: 'private coaching message' });

    expect(res.status).toBe(500);
    expect(requestLogSpy.mock.calls.flat().join(' ')).not.toContain('private coaching message');
    expect(errorSpy.mock.calls.flat().join(' ')).not.toContain('private coaching message');

    errorSpy.mockRestore();
  });
});

describe('GET /api/v1/chat/session/:sessionId/messages', () => {
  test('returns messages array', async () => {
    const res = await request(app)
      .get('/api/v1/chat/session/sess1/messages')
      .set('x-user-id', 'u1');
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(Array.isArray(res.body.data.messages)).toBe(true);
    expect(res.body.data.messages).toHaveLength(2);
  });

  test('returns 401 without x-user-id header', async () => {
    const res = await request(app)
      .get('/api/v1/chat/session/sess1/messages');
    expect(res.status).toBe(401);
  });

  test('returns 404 when getMessages throws Session not found', async () => {
    const { getMessages } = require('../services/claude/chatAgent');
    (getMessages as jest.Mock).mockRejectedValueOnce(new Error('Session not found'));
    const res = await request(app)
      .get('/api/v1/chat/session/bad-sess/messages')
      .set('x-user-id', 'u1');
    expect(res.status).toBe(404);
  });
});

describe('GET /api/v1/chat/sessions', () => {
  test('returns sessions list with valid userId', async () => {
    const res = await request(app)
      .get('/api/v1/chat/sessions')
      .set('x-user-id', 'u1');
    // Route exists (not 404)
    expect(res.status).not.toBe(404);
  });

  test('returns 401 without x-user-id', async () => {
    const res = await request(app).get('/api/v1/chat/sessions');
    expect(res.status).toBe(401);
  });
});

describe('GET /api/v1/chat/session/:id', () => {
  test('returns 401 without x-user-id', async () => {
    const res = await request(app).get('/api/v1/chat/session/abc');
    expect(res.status).toBe(401);
  });
});
