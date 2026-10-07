import { CoachingIdempotencyStore } from '../services/coaching/coachingIdempotencyStore';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const encryptionKeyBase64 = Buffer.alloc(32, 7).toString('base64');

function createStore(databasePath = ':memory:') {
  return new CoachingIdempotencyStore({ databasePath, encryptionKeyBase64 });
}

const requestId = '11111111-1111-4111-8111-111111111111';
const key = 'turn-1-coaching';
const ownerId = 'device-owner-1';

test('replays one authoritative completion for a duplicate idempotency key', () => {
  const store = createStore();
  const first = store.begin({ key, requestId, requestHash: 'hash-1', ownerId });
  expect(first).toEqual({ status: 'start' });

  store.markProviderStarted(key);
  store.complete(key, {
    requestId,
    reply: 'Keep going.',
    mode: 'coach',
    relevance: 'career-relevant',
    contextSufficiency: 'sufficient',
    stance: 'nudge',
    proposals: [],
    usage: { provider: 'anthropic', model: 'fixture', estimatedCostUsd: 0.01 },
  }, 'receipt-1');

  expect(store.begin({ key, requestId, requestHash: 'hash-1', ownerId })).toMatchObject({
    status: 'completed',
    idempotencyReceipt: 'receipt-1',
    response: { reply: 'Keep going.' },
  });
  store.close();
});

test('rejects one idempotency key reused for different request content', () => {
  const store = createStore();
  store.begin({ key, requestId, requestHash: 'hash-1', ownerId });
  expect(() => store.begin({ key, requestId, requestHash: 'hash-2', ownerId }))
    .toThrow('IDEMPOTENCY_KEY_REUSED');
  store.close();
});

test('reports provider-started work as ambiguous after relaunch', () => {
  const store = createStore();
  store.begin({ key, requestId, requestHash: 'hash-1', ownerId });
  store.markProviderStarted(key);

  expect(store.reconcile(requestId, ownerId)).toEqual({ status: 'ambiguous', requestId });
  store.close();
});

test('durable replay never writes coaching text as plaintext', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'taisa-coaching-receipt-'));
  const databasePath = path.join(directory, 'usage.sqlite');
  const store = createStore(databasePath);
  store.begin({ key, requestId, requestHash: 'hash-private', ownerId });
  store.markProviderStarted(key);
  store.complete(key, {
    requestId,
    reply: 'PRIVATE_COACHING_REPLY_SENTINEL',
    mode: 'coach', relevance: 'career-relevant', contextSufficiency: 'sufficient',
    stance: 'nudge', proposals: [],
    usage: { provider: 'anthropic', model: 'fixture', estimatedCostUsd: 0.01 },
  }, 'receipt-private');
  store.close();

  expect(fs.readFileSync(databasePath).includes(Buffer.from('PRIVATE_COACHING_REPLY_SENTINEL'))).toBe(false);
});

test('reconciliation is owner-bound and explicit retry authorization resets only ambiguous work', () => {
  const store = createStore();
  store.begin({ key, requestId, requestHash: 'hash-1', ownerId });
  store.markProviderStarted(key);

  expect(store.reconcile(requestId, 'other-device')).toEqual({ status: 'missing', requestId });
  expect(() => store.authorizeRetry(requestId, 'other-device')).toThrow('REQUEST_NOT_FOUND');
  expect(store.authorizeRetry(requestId, ownerId)).toEqual({ status: 'authorized', requestId });
  expect(store.begin({ key, requestId, requestHash: 'hash-1', ownerId })).toEqual({ status: 'start' });
  expect(() => store.authorizeRetry(requestId, ownerId)).toThrow('IDEMPOTENCY_STATE_CONFLICT');
  store.close();
});
