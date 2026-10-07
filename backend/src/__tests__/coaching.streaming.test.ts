import type { CoachingRequest, CoachingResponse } from '@taisa/shared';
import { createHash } from 'node:crypto';
import express from 'express';
import supertest from 'supertest';
import { CoachingIdempotencyStore } from '../services/coaching/coachingIdempotencyStore';
import {
  executeCoachingStream,
  extractReplyPrefix,
} from '../services/coaching/streamingCoaching';
import { requestStreamingCoaching } from '../services/coaching/coachingGateway';
import { createCoachingRouter } from '../routes/coaching';

const request: CoachingRequest = {
  requestId: '11111111-1111-4111-8111-111111111111',
  submittedAt: '2026-10-07T00:00:00.000Z',
  input: 'I led the critique.',
  context: { profile: null, recentMessages: [], memory: [], evidence: [] },
};

const response: CoachingResponse = {
  requestId: request.requestId,
  reply: 'What changed because you led it?',
  mode: 'coach',
  relevance: 'career-relevant',
  contextSufficiency: 'sufficient',
  stance: 'nudge',
  proposals: [],
  usage: { provider: 'anthropic', model: 'fixture', estimatedCostUsd: 0.01 },
};

const receiptEncryptionKey = Buffer.alloc(32, 9).toString('base64');
const ownerId = 'device-owner-1';

function createStore() {
  return new CoachingIdempotencyStore({
    databasePath: ':memory:',
    encryptionKeyBase64: receiptEncryptionKey,
  });
}

async function collect<T>(stream: AsyncIterable<T>): Promise<T[]> {
  const values: T[] = [];
  for await (const value of stream) values.push(value);
  return values;
}

test('duplicate stream request replays one authoritative terminal without a second paid execution', async () => {
  const store = createStore();
  const paidExecution = jest.fn(async function* () {
    yield { kind: 'delta' as const, delta: 'What changed ' };
    yield { kind: 'delta' as const, delta: 'because you led it?' };
    yield { kind: 'completed' as const, response };
  });

  const first = await collect(executeCoachingStream({ request, idempotencyKey: 'turn-1', ownerId, store, paidExecution }));
  const second = await collect(executeCoachingStream({ request, idempotencyKey: 'turn-1', ownerId, store, paidExecution }));

  expect(paidExecution).toHaveBeenCalledTimes(1);
  expect(second.at(-1)).toEqual(first.at(-1));
  expect(first.map((event) => event.sequence)).toEqual([0, 1, 2]);
  store.close();
});

test('ambiguous provider-started work does not invoke paid execution', async () => {
  const store = createStore();
  store.begin({ key: 'turn-2', requestId: request.requestId, requestHash: 'forced-hash', ownerId });
  store.markProviderStarted('turn-2');
  const paidExecution = jest.fn();

  await expect(collect(executeCoachingStream({
    request,
    idempotencyKey: 'turn-2',
    ownerId,
    requestHash: 'forced-hash',
    store,
    paidExecution,
  }))).rejects.toMatchObject({ code: 'AMBIGUOUS_PAID_WORK' });
  expect(paidExecution).not.toHaveBeenCalled();
  store.close();
});

test('executor exposes the first delta before paid execution reaches its terminal', async () => {
  const store = createStore();
  let terminalReleased = false;
  const paidExecution = async function* () {
    yield { kind: 'delta' as const, delta: 'What changed?' };
    terminalReleased = true;
    yield { kind: 'completed' as const, response };
  };
  const stream = executeCoachingStream({ request, idempotencyKey: 'turn-live-1', ownerId, store, paidExecution });
  const iterator = stream[Symbol.asyncIterator]();

  expect(await iterator.next()).toMatchObject({
    value: { type: 'coaching.delta', sequence: 0, delta: 'What changed?' },
    done: false,
  });
  expect(terminalReleased).toBe(false);
  await iterator.return?.();
  store.close();
});

test('extracts genuine growing reply text from partial structured JSON', () => {
  expect(extractReplyPrefix('{"mode":"coach","reply":"What')).toBe('What');
  expect(extractReplyPrefix('{"mode":"coach","reply":"What changed\\nnext')).toBe('What changed\nnext');
  expect(extractReplyPrefix('{"mode":"coach","reply":"split\\u2014')).toBe('split—');
  expect(extractReplyPrefix('{"mode":"coach","reply":"unfinished\\u20')).toBe('unfinished');
});

test('gateway forwards provider deltas before validating the structured terminal response', async () => {
  let terminalReleased = false;
  const provider = {
    async *stream() {
      yield { kind: 'delta' as const, delta: 'What changed?' };
      terminalReleased = true;
      yield {
        kind: 'completed' as const,
        result: {
          payload: {
            mode: 'coach', relevance: 'career-relevant', contextSufficiency: 'sufficient',
            reply: 'What changed?', stance: 'nudge', proposals: [],
          },
          usage: response.usage,
        },
        attempts: [],
      };
    },
  };
  const stream = requestStreamingCoaching(request, provider as any, {
    beginAttempt: jest.fn(), settleAttempt: jest.fn(),
  });
  const iterator = stream[Symbol.asyncIterator]();

  expect(await iterator.next()).toEqual({ value: { kind: 'delta', delta: 'What changed?' }, done: false });
  expect(terminalReleased).toBe(false);
  expect(await iterator.next()).toMatchObject({
    value: { kind: 'completed', response: { ...response, reply: 'What changed?' } },
    done: false,
  });
});

test('stream endpoint emits ordered NDJSON and replays its terminal without a second execution', async () => {
  const store = createStore();
  const paidExecution = jest.fn(async function* () {
    yield { kind: 'delta' as const, delta: 'What changed?' };
    yield { kind: 'completed' as const, response: { ...response, reply: 'What changed?' } };
  });
  const app = express();
  app.use(express.json());
  app.use('/api/v1/coaching', createCoachingRouter({ idempotencyStore: store, paidExecution }));

  const first = await supertest(app).post('/api/v1/coaching/respond/stream')
    .set('X-User-ID', ownerId).set('Idempotency-Key', 'turn-http-1').send(request);
  const replay = await supertest(app).post('/api/v1/coaching/respond/stream')
    .set('X-User-ID', ownerId).set('Idempotency-Key', 'turn-http-1').send(request);
  const reconciliation = await supertest(app).get(`/api/v1/coaching/requests/${request.requestId}`)
    .set('X-User-ID', ownerId);

  expect(first.status).toBe(200);
  expect(first.headers['content-type']).toContain('application/x-ndjson');
  expect(first.text.trim().split('\n').map((line) => JSON.parse(line)).map((event) => event.sequence)).toEqual([0, 1]);
  expect(replay.text.trim().split('\n').map((line) => JSON.parse(line))).toEqual([
    first.text.trim().split('\n').map((line) => JSON.parse(line)).at(-1),
  ]);
  expect(paidExecution).toHaveBeenCalledTimes(1);
  expect(reconciliation.body.data).toMatchObject({ status: 'completed', terminalSequence: 1 });
  store.close();
});

test('stream endpoint returns a conflict before committing headers for ambiguous paid work', async () => {
  const store = createStore();
  const requestHash = createHash('sha256').update(JSON.stringify(request)).digest('hex');
  store.begin({ key: 'turn-http-ambiguous', requestId: request.requestId, requestHash, ownerId });
  store.markProviderStarted('turn-http-ambiguous');
  const app = express();
  app.use(express.json());
  app.use('/api/v1/coaching', createCoachingRouter({ idempotencyStore: store, paidExecution: jest.fn() }));

  const result = await supertest(app).post('/api/v1/coaching/respond/stream')
    .set('X-User-ID', ownerId)
    .set('Idempotency-Key', 'turn-http-ambiguous')
    .send(request);

  expect(result.status).toBe(409);
  expect(result.body.error.code).toBe('AMBIGUOUS_PAID_WORK');
  store.close();
});

test('stream endpoint terminates a started stream with a typed durable failure event', async () => {
  const store = createStore();
  const paidExecution = async function* () {
    yield { kind: 'delta' as const, delta: 'Partial' };
    throw { status: 503 };
  };
  const app = express();
  app.use(express.json());
  app.use('/api/v1/coaching', createCoachingRouter({ idempotencyStore: store, paidExecution }));

  const result = await supertest(app).post('/api/v1/coaching/respond/stream')
    .set('X-User-ID', ownerId).set('Idempotency-Key', 'turn-http-failure').send(request);
  const events = result.text.trim().split('\n').map((line) => JSON.parse(line));

  expect(result.status).toBe(200);
  expect(events).toEqual([
    expect.objectContaining({ type: 'coaching.delta', sequence: 0 }),
    expect.objectContaining({ type: 'coaching.failed', sequence: 1, code: 'COACHING_UNAVAILABLE', retryable: false }),
  ]);
  expect(store.reconcile(request.requestId, ownerId)).toMatchObject({
    status: 'failed', code: 'COACHING_UNAVAILABLE', retryable: false,
  });
  store.close();
});

test('reconciliation requires ownership and explicit resolution authorizes one replacement attempt', async () => {
  const store = createStore();
  const requestHash = createHash('sha256').update(JSON.stringify(request)).digest('hex');
  store.begin({ key: 'turn-http-resolve', requestId: request.requestId, requestHash, ownerId });
  store.markProviderStarted('turn-http-resolve');
  const paidExecution = jest.fn(async function* () {
    yield { kind: 'completed' as const, response };
  });
  const app = express();
  app.use(express.json());
  app.use('/api/v1/coaching', createCoachingRouter({ idempotencyStore: store, paidExecution }));

  expect((await supertest(app).get(`/api/v1/coaching/requests/${request.requestId}`)).status).toBe(401);
  expect((await supertest(app).get(`/api/v1/coaching/requests/${request.requestId}`)
    .set('X-User-ID', 'other-device')).status).toBe(404);
  expect((await supertest(app).post(`/api/v1/coaching/requests/${request.requestId}/resolve`)
    .set('X-User-ID', 'other-device').send({ decision: 'retry' })).status).toBe(404);
  expect((await supertest(app).post(`/api/v1/coaching/requests/${request.requestId}/resolve`)
    .set('X-User-ID', ownerId).send({ decision: 'retry' })).status).toBe(200);

  const retried = await supertest(app).post('/api/v1/coaching/respond/stream')
    .set('X-User-ID', ownerId).set('Idempotency-Key', 'turn-http-resolve').send(request);
  expect(retried.status).toBe(200);
  expect(paidExecution).toHaveBeenCalledTimes(1);
  store.close();
});

test('production ownership ignores spoofable legacy headers', async () => {
  const store = createStore();
  const app = express();
  app.use(express.json());
  app.use('/api/v1/coaching', createCoachingRouter({
    idempotencyStore: store,
    allowLegacyOwnerHeader: false,
    paidExecution: jest.fn(),
  }));

  const result = await supertest(app).post('/api/v1/coaching/respond/stream')
    .set('X-User-ID', ownerId).set('Idempotency-Key', 'spoofed-owner').send(request);

  expect(result.status).toBe(401);
  expect(result.body.error.code).toBe('DEVICE_AUTHENTICATION_REQUIRED');
  store.close();
});
