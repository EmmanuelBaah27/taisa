import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  TranscriptionIdempotencyStore,
  TranscriptionIdempotencyConflictError,
} from '../services/transcription/transcriptionIdempotencyStore';

const encryptionKeyBase64 = Buffer.alloc(32, 0x61).toString('base64');

describe('transcription idempotency receipts', () => {
  let databasePath: string;

  beforeEach(() => {
    databasePath = path.join(os.tmpdir(), `taisa-transcription-idempotency-${process.pid}-${Math.random()}.sqlite`);
  });

  afterEach(() => {
    for (const suffix of ['', '-wal', '-shm']) fs.rmSync(`${databasePath}${suffix}`, { force: true });
  });

  test('blocks replay after provider work begins and binds key to owner and audio', () => {
    const store = new TranscriptionIdempotencyStore({ databasePath, encryptionKeyBase64 });
    const input = { key: 'key-1', requestId: 'request-1', ownerId: 'device-1', audioSHA256: 'abc' };

    expect(store.begin(input)).toEqual({ status: 'start' });
    store.markProviderStarted(input.key);
    expect(store.begin(input)).toEqual({ status: 'ambiguous', requestId: input.requestId });
    expect(store.reconcile(input.requestId, input.ownerId))
      .toEqual({ status: 'ambiguous', requestId: input.requestId });
    expect(store.reconcile(input.requestId, 'other-device'))
      .toEqual({ status: 'missing', requestId: input.requestId });
    expect(store.authorizeRetry(input.requestId, input.ownerId))
      .toEqual({ status: 'authorized', requestId: input.requestId });
    expect(store.begin(input)).toEqual({ status: 'start' });
    expect(() => store.begin({ ...input, ownerId: 'device-2' }))
      .toThrow(TranscriptionIdempotencyConflictError);
    expect(() => store.begin({ ...input, audioSHA256: 'different' }))
      .toThrow(TranscriptionIdempotencyConflictError);
    store.close();
  });

  test('encrypted terminal receipt survives process restart and replays without provider work', () => {
    const input = { key: 'key-2', requestId: 'request-2', ownerId: 'device-1', audioSHA256: 'def' };
    const terminal = {
      type: 'transcript.completed', requestId: input.requestId, sequence: 2,
      transcript: 'private transcript', durationSeconds: 1, quality: 'clear',
      usage: { provider: 'openai', model: 'fixture', audioSeconds: 1, estimatedCostUsd: 0.1 },
    };
    const first = new TranscriptionIdempotencyStore({ databasePath, encryptionKeyBase64 });
    expect(first.begin(input)).toEqual({ status: 'start' });
    first.markProviderStarted(input.key);
    first.complete(input.key, terminal);
    first.close();

    const reopened = new TranscriptionIdempotencyStore({ databasePath, encryptionKeyBase64 });
    expect(reopened.begin(input)).toEqual({ status: 'completed', event: terminal });
    expect(fs.readFileSync(databasePath).includes(Buffer.from('private transcript'))).toBe(false);
    reopened.close();
  });
});
