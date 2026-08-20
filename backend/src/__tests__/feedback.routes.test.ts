import express from 'express';
import request from 'supertest';
import { FeedbackRepository } from '../feedback/feedbackRepository';
import { createFeedbackRouter } from '../routes/feedback';

const KEY = Buffer.alloc(32, 7).toString('base64');
const payload = {
  idempotencyId: 'feedback-attempt-1',
  consentedAt: '2026-08-13T15:00:00.000Z',
  example: {
    requestId: 'request-1',
    kind: 'voice',
    stance: 'challenge',
    reaction: 'unhelpful',
    note: 'It assumed context.',
    userTurn: 'A synthetic work situation',
    assistantReply: 'A synthetic coaching reply',
    contextManifest: { includedMemoryIds: ['memory-1'] },
    usedContext: ['Synthetic context used for this response'],
  },
};

function app(repository: FeedbackRepository, owner = 'credential-1') {
  const value = express();
  value.use(express.json());
  value.use((_req, res, next) => { res.locals.deviceCredentialId = owner; next(); });
  value.use('/feedback-examples', createFeedbackRouter(repository));
  return value;
}

test('stores an explicitly consented example as ciphertext and retries idempotently', async () => {
  const repository = new FeedbackRepository({ encryptionKeyBase64: KEY });
  const first = await request(app(repository)).post('/feedback-examples').send(payload);
  const second = await request(app(repository)).post('/feedback-examples').send(payload);
  expect(first.status).toBe(201);
  expect(second.body.data.receiptId).toBe(first.body.data.receiptId);
  const persisted = repository.inspectPersistedValues();
  expect(persisted).not.toContain(payload.example.userTurn);
  expect(persisted).not.toContain(payload.example.assistantReply);
  repository.close();
});

test('rejects missing consent and oversized content without storing it', async () => {
  const repository = new FeedbackRepository({ encryptionKeyBase64: KEY });
  expect((await request(app(repository)).post('/feedback-examples').send({
    ...payload,
    consentedAt: null,
  })).status).toBe(400);
  expect((await request(app(repository)).post('/feedback-examples').send({
    ...payload,
    example: { ...payload.example, contextManifest: { nested: 'x'.repeat(50_000) } },
  })).status).toBe(400);
  expect((await request(app(repository)).post('/feedback-examples').send({
    ...payload,
    example: { ...payload.example, userTurn: 'x'.repeat(20_001) },
  })).status).toBe(400);
  expect(repository.count()).toBe(0);
  repository.close();
});

test('deletion is scoped to the enrolled device credential', async () => {
  const repository = new FeedbackRepository({ encryptionKeyBase64: KEY });
  const created = await request(app(repository)).post('/feedback-examples').send(payload);
  const receiptId = created.body.data.receiptId;
  expect((await request(app(repository, 'other')).delete(`/feedback-examples/${receiptId}`)).status)
    .toBe(204);
  expect(repository.count()).toBe(1);
  expect((await request(app(repository)).delete(`/feedback-examples/${receiptId}`)).status).toBe(204);
  expect((await request(app(repository)).delete(`/feedback-examples/${receiptId}`)).status).toBe(204);
  expect(repository.count()).toBe(0);
  repository.close();
});
