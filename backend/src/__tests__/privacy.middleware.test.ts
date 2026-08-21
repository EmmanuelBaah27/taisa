import express from 'express';
import fs from 'fs';
import os from 'os';
import path from 'path';
import request from 'supertest';
import type { UsageReceipt } from '@taisa/shared';

jest.mock(
  'music-metadata',
  () => {
    const fileSystem = jest.requireActual('fs');
    return {
      parseFile: jest.fn(async (filePath: string) => {
      const wav = fileSystem.readFileSync(filePath);
      const byteRate = wav.readUInt32LE(28);
      const dataLength = wav.readUInt32LE(40);
      return { format: { duration: dataLength / byteRate } };
      }),
    };
  },
  { virtual: true },
);

import { contentSafeErrorHandler, requestContext } from '../middleware/requestContext';
import coachingRouter from '../routes/coaching';
import { cleanupStaleTranscriptionUploads, createTranscribeRouter } from '../routes/transcribe';
import {
  CostLedger,
  CostLimitError,
  UsageExceedsReservationError,
} from '../services/usage/costLedger';

jest.mock('../services/coaching/coachingGateway', () => ({
  estimateConfiguredCoachingUsage: jest.fn().mockReturnValue({
    provider: 'openai',
    model: 'mock',
    inputTokens: 1,
    outputTokens: 1,
    estimatedCostUsd: 0,
  }),
  requestCoaching: jest.fn().mockResolvedValue({
    requestId: '11111111-1111-4111-8111-111111111111',
    reply: 'What changed?',
    stance: 'nudge',
    proposals: [],
    usage: { provider: 'openai', model: 'mock', estimatedCostUsd: 0 },
  }),
}));

const validRequest = {
  requestId: '11111111-1111-4111-8111-111111111111',
  submittedAt: '2026-08-09T00:00:00Z',
  input: 'private coaching input must never be logged',
  context: {
    profile: null,
    recentMessages: [],
    memory: [
      {
        id: 'mem-1',
        type: 'goal',
        statement: 'private memory statement must never be logged',
        provenance: 'user-confirmed',
        lifecycle: 'active',
        confidence: 'established',
        createdAt: '2026-08-09T00:00:00Z',
        confirmedAt: '2026-08-09T00:00:00Z',
        lastSupportedAt: '2026-08-09T00:00:00Z',
        statusChangedAt: '2026-08-09T00:00:00Z',
        sourceMessageIds: ['m1'],
      },
    ],
    evidence: [],
  },
};

const transcriptionEnvironment = {
  TAISA_TRANSCRIPTION_MODEL: 'gpt-4o-mini-transcribe',
  TAISA_TRANSCRIPTION_MAX_DURATION_SECONDS: '300',
  TAISA_TRANSCRIPTION_MAX_UPLOAD_BYTES: '100000',
  TAISA_TRANSCRIPTION_PRICE_USD_PER_MINUTE: '0.006',
  TAISA_AI_COST_CEILING_PER_REQUEST_USD: '0.05',
  TAISA_AI_COST_CEILING_DAILY_USD: '1',
  TAISA_AI_COST_CEILING_MONTHLY_USD: '10',
};

function createAudioFixture(durationSeconds = 1): string {
  const fixturePath = path.join(
    os.tmpdir(),
    `taisa-transcription-fixture-${process.pid}-${Math.random().toString(16).slice(2)}.wav`,
  );
  const sampleRate = 8000;
  const channelCount = 1;
  const bitsPerSample = 16;
  const dataLength = sampleRate * channelCount * (bitsPerSample / 8) * durationSeconds;
  const wav = Buffer.alloc(44 + dataLength);
  wav.write('RIFF', 0);
  wav.writeUInt32LE(36 + dataLength, 4);
  wav.write('WAVE', 8);
  wav.write('fmt ', 12);
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20);
  wav.writeUInt16LE(channelCount, 22);
  wav.writeUInt32LE(sampleRate, 24);
  wav.writeUInt32LE(sampleRate * channelCount * (bitsPerSample / 8), 28);
  wav.writeUInt16LE(channelCount * (bitsPerSample / 8), 32);
  wav.writeUInt16LE(bitsPerSample, 34);
  wav.write('data', 36);
  wav.writeUInt32LE(dataLength, 40);
  fs.writeFileSync(fixturePath, wav);
  return fixturePath;
}

function createLedgerPath(): string {
  return path.join(
    os.tmpdir(),
    `taisa-usage-ledger-${process.pid}-${Math.random().toString(16).slice(2)}.sqlite`,
  );
}

async function removeLedgerFiles(databasePath: string): Promise<void> {
  await Promise.all(
    [databasePath, `${databasePath}-wal`, `${databasePath}-shm`].map((filePath) =>
      fs.promises.rm(filePath, { force: true }),
    ),
  );
}

function createTranscriptionApp(options: {
  create: jest.Mock;
  ledger?: CostLedger;
  environment?: Record<string, string | undefined>;
}) {
  const app = express();
  app.use(requestContext);
  app.use(
    '/api/v1/transcribe',
    createTranscribeRouter({
      client: { audio: { transcriptions: { create: options.create } } } as any,
      ledger: options.ledger ?? new CostLedger(),
      environment: options.environment ?? transcriptionEnvironment,
    }),
  );
  return app;
}

async function* successfulTranscriptionStream(text: string) {
  yield {
    type: 'transcript.text.delta' as const,
    delta: text,
    logprobs: [{ logprob: -0.1 }],
  };
  yield {
    type: 'transcript.text.done' as const,
    text,
    logprobs: [{ logprob: -0.1 }],
  };
}

function createSuccessfulTranscription(text = 'private transcript'): jest.Mock {
  return jest.fn(async () => successfulTranscriptionStream(text));
}

function parseTranscriptionStream(text: string): Array<Record<string, unknown>> {
  return text.trim().split('\n').filter(Boolean).map((line) => JSON.parse(line));
}

describe('content-free request telemetry', () => {
  let logSpy: jest.SpyInstance;
  const requestLedgerPath = createLedgerPath();
  const originalCostEnvironment = {
    perRequest: process.env.TAISA_AI_COST_CEILING_PER_REQUEST_USD,
    daily: process.env.TAISA_AI_COST_CEILING_DAILY_USD,
    monthly: process.env.TAISA_AI_COST_CEILING_MONTHLY_USD,
    ledgerPath: process.env.TAISA_USAGE_LEDGER_PATH,
  };

  beforeAll(() => {
    process.env.TAISA_USAGE_LEDGER_PATH = requestLedgerPath;
  });

  afterAll(async () => {
    if (originalCostEnvironment.ledgerPath === undefined) {
      delete process.env.TAISA_USAGE_LEDGER_PATH;
    } else {
      process.env.TAISA_USAGE_LEDGER_PATH = originalCostEnvironment.ledgerPath;
    }
    await removeLedgerFiles(requestLedgerPath);
  });

  beforeEach(() => {
    process.env.TAISA_AI_COST_CEILING_PER_REQUEST_USD = '0.05';
    process.env.TAISA_AI_COST_CEILING_DAILY_USD = '1';
    process.env.TAISA_AI_COST_CEILING_MONTHLY_USD = '10';
    logSpy = jest.spyOn(console, 'info').mockImplementation(() => undefined);
  });

  afterEach(() => {
    for (const [name, value] of [
      ['TAISA_AI_COST_CEILING_PER_REQUEST_USD', originalCostEnvironment.perRequest],
      ['TAISA_AI_COST_CEILING_DAILY_USD', originalCostEnvironment.daily],
      ['TAISA_AI_COST_CEILING_MONTHLY_USD', originalCostEnvironment.monthly],
    ] as const) {
      if (value === undefined) delete process.env[name];
      else process.env[name] = value;
    }
    logSpy.mockRestore();
  });

  test('logs method, route, status, latency, and requestId without content', async () => {
    const app = express();
    app.use(requestContext);
    app.use(express.json());
    app.use('/api/v1/coaching', coachingRouter);

    const response = await request(app)
      .post('/api/v1/coaching/respond?debug=private-query')
      .set('x-user-id', 'device-1')
      .set('x-request-id', '11111111-1111-4111-8111-111111111111')
      .send(validRequest);

    expect(response.status).toBe(200);
    expect(response.headers['x-request-id']).toBe('11111111-1111-4111-8111-111111111111');

    const output = logSpy.mock.calls.flat().join(' ');
    const event = JSON.parse(String(logSpy.mock.calls[0][0]));
    expect(event).toEqual({
      requestId: '11111111-1111-4111-8111-111111111111',
      method: 'POST',
      route: '/api/v1/coaching/respond',
      status: 200,
      latencyMs: expect.any(Number),
    });
    expect(output).not.toContain('private-query');
    expect(output).not.toContain(validRequest.input);
    expect(output).not.toContain(validRequest.context.memory[0].statement);
    expect(output).not.toContain('device-1');
  });

  test('replaces a content-shaped request ID before logging it', async () => {
    const app = express();
    app.use(requestContext);
    app.get('/health', (_req, res) => res.sendStatus(204));

    const response = await request(app)
      .get('/health')
      .set('x-request-id', 'private content with spaces');

    expect(response.headers['x-request-id']).not.toBe('private content with spaces');
    expect(logSpy.mock.calls.flat().join(' ')).not.toContain('private content with spaces');
  });

  test('replaces a non-UUID telemetry request ID before logging it', async () => {
    const app = express();
    app.use(requestContext);
    app.get('/health', (_req, res) => res.sendStatus(204));

    const response = await request(app)
      .get('/health')
      .set('x-request-id', 'safe-request-1');

    expect(response.headers['x-request-id']).not.toBe('safe-request-1');
    expect(response.headers['x-request-id']).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );
    expect(logSpy.mock.calls.flat().join(' ')).not.toContain('safe-request-1');
  });

  test('logs only safe error metadata and returns a fixed public message', async () => {
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => undefined);
    const app = express();
    app.use(requestContext);
    app.get('/failure', () => {
      const providerError = new Error('provider payload contains private response text');
      providerError.stack =
        'Error: provider payload contains private response text\n' +
        '    at upstreamProvider (private response text:1:1)';
      throw providerError;
    });
    app.use(contentSafeErrorHandler);

    const response = await request(app)
      .get('/failure')
      .set('x-request-id', '22222222-2222-4222-8222-222222222222');

    expect(response.status).toBe(500);
    expect(response.body).toEqual({
      success: false,
      error: { code: 'INTERNAL_ERROR', message: 'An internal error occurred' },
    });
    const serialized = errorSpy.mock.calls.flat().join(' ');
    expect(serialized).toContain('22222222-2222-4222-8222-222222222222');
    expect(serialized).toContain('INTERNAL_ERROR');
    expect(serialized).not.toContain('private response text');
    errorSpy.mockRestore();
  });
});

describe('transcription privacy and spend boundaries', () => {
  let fixturePath: string;

  beforeEach(() => {
    fixturePath = createAudioFixture();
  });

  afterEach(async () => {
    await fs.promises.rm(fixturePath, { force: true });
    jest.restoreAllMocks();
  });

  test('removes stale uploaded audio before a restarted server accepts new work', async () => {
    const uploadDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'taisa-stale-audio-'));
    const stalePath = path.join(uploadDirectory, 'stale-upload');
    fs.writeFileSync(stalePath, 'private stale audio');

    await cleanupStaleTranscriptionUploads(uploadDirectory);

    expect(fs.existsSync(stalePath)).toBe(false);
    fs.rmSync(uploadDirectory, { recursive: true, force: true });
  });

  test.each(['succeeds', 'fails'])('deletes uploaded audio when transcription %s', async (outcome) => {
    const create = outcome === 'succeeds'
      ? createSuccessfulTranscription()
      : jest.fn().mockRejectedValue(new Error('provider payload: private transcript'));
    let capturedTempPath = '';
    const actualRm = fs.promises.rm.bind(fs.promises);
    jest.spyOn(fs.promises, 'rm').mockImplementation(async (filePath, options) => {
      if (String(filePath) !== fixturePath) capturedTempPath = String(filePath);
      return actualRm(filePath, options);
    });
    jest.spyOn(console, 'info').mockImplementation(() => undefined);
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => undefined);

    const response = await request(createTranscriptionApp({ create }))
      .post('/api/v1/transcribe')
      .field('durationSeconds', '1')
      .attach('audio', fixturePath);

    expect(response.status).toBe(200);
    expect(capturedTempPath).not.toBe('');
    expect(fs.existsSync(capturedTempPath)).toBe(false);
    if (outcome === 'fails') {
      expect(errorSpy.mock.calls.flat().join(' ')).not.toContain('private transcript');
      expect(response.text).not.toContain('private transcript');
    }
  });

  test('returns a content-free failure when temporary audio cleanup fails', async () => {
    const actualRm = fs.promises.rm.bind(fs.promises);
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => undefined);
    jest.spyOn(fs.promises, 'rm').mockImplementation(async (filePath, options) => {
      if (String(filePath) !== fixturePath) {
        const error = new Error('private temporary path could not be removed');
        Object.assign(error, { code: 'EACCES' });
        throw error;
      }
      return actualRm(filePath, options);
    });

    const response = await request(createTranscriptionApp({
      create: createSuccessfulTranscription(),
    }))
      .post('/api/v1/transcribe')
      .attach('audio', fixturePath)
      .timeout({ response: 1000 });

    expect(response.status).toBe(200);
    expect(response.headers['content-type']).toMatch(/application\/x-ndjson/);
    expect(errorSpy.mock.calls.flat().join(' ')).not.toContain('private temporary path');
    errorSpy.mockRestore();
  });

  test('returns transcript but records only content-free transcription usage', async () => {
    const databasePath = createLedgerPath();
    const ledger = new CostLedger({ databasePath });
    const create = createSuccessfulTranscription();
    jest.spyOn(console, 'info').mockImplementation(() => undefined);

    const response = await request(createTranscriptionApp({ create, ledger }))
      .post('/api/v1/transcribe')
      .attach('audio', fixturePath);

    expect(response.status).toBe(200);
    const events = parseTranscriptionStream(response.text);
    const completed = events.find((event) => event.type === 'transcript.completed');
    expect(completed?.transcript).toBe('private transcript');
    expect(completed?.usage).toEqual({
      provider: 'openai',
      model: 'gpt-4o-mini-transcribe',
      audioSeconds: 1,
      estimatedCostUsd: 0.0001,
    });
    expect(ledger.listUsage()).toEqual([
      {
        recordedAt: expect.any(String),
        receipt: completed?.usage,
      },
    ]);
    expect(JSON.stringify(ledger.listUsage())).not.toContain('private transcript');
    ledger.close();
    await removeLedgerFiles(databasePath);
  });

  test('measures uploaded audio and rejects duration above the configured ceiling before OpenAI', async () => {
    const create = jest.fn().mockResolvedValue({ text: 'must not be called' });
    jest.spyOn(console, 'info').mockImplementation(() => undefined);

    const response = await request(
      createTranscriptionApp({
        create,
        environment: {
          ...transcriptionEnvironment,
          TAISA_TRANSCRIPTION_MAX_DURATION_SECONDS: '0.5',
        },
      }),
    )
      .post('/api/v1/transcribe')
      .field('durationSeconds', '0.5')
      .attach('audio', fixturePath);

    expect(response.status).toBe(413);
    expect(response.body.error.code).toBe('AUDIO_DURATION_LIMIT_EXCEEDED');
    expect(create).not.toHaveBeenCalled();
  });

  test('rejects materially spoofed caller duration before OpenAI', async () => {
    const create = jest.fn().mockResolvedValue({ text: 'must not be called' });
    jest.spyOn(console, 'info').mockImplementation(() => undefined);

    const response = await request(createTranscriptionApp({ create }))
      .post('/api/v1/transcribe')
      .field('durationSeconds', '60')
      .attach('audio', fixturePath);

    expect(response.status).toBe(422);
    expect(response.body.error.code).toBe('AUDIO_DURATION_MISMATCH');
    expect(create).not.toHaveBeenCalled();
  });

  test('rejects an upload above the configured byte limit before OpenAI', async () => {
    const create = jest.fn().mockResolvedValue({ text: 'must not be called' });
    jest.spyOn(console, 'info').mockImplementation(() => undefined);

    const response = await request(
      createTranscriptionApp({
        create,
        environment: {
          ...transcriptionEnvironment,
          TAISA_TRANSCRIPTION_MAX_UPLOAD_BYTES: '100',
        },
      }),
    )
      .post('/api/v1/transcribe')
      .attach('audio', fixturePath);

    expect(response.status).toBe(413);
    expect(response.body.error.code).toBe('AUDIO_UPLOAD_LIMIT_EXCEEDED');
    expect(create).not.toHaveBeenCalled();
  });

  test('rejects a transcription that exceeds the per-request cost ceiling before OpenAI', async () => {
    const create = jest.fn().mockResolvedValue({ text: 'must not be called' });
    jest.spyOn(console, 'info').mockImplementation(() => undefined);

    const response = await request(
      createTranscriptionApp({
        create,
        environment: {
          ...transcriptionEnvironment,
          TAISA_TRANSCRIPTION_PRICE_USD_PER_MINUTE: '60',
          TAISA_AI_COST_CEILING_PER_REQUEST_USD: '0.50',
        },
      }),
    )
      .post('/api/v1/transcribe')
      .attach('audio', fixturePath);

    expect(response.status).toBe(429);
    expect(response.body.error.code).toBe('COST_LIMIT_EXCEEDED');
    expect(create).not.toHaveBeenCalled();
  });

  test('fails closed before OpenAI when cost configuration is missing', async () => {
    const create = jest.fn().mockResolvedValue({ text: 'must not be called' });
    jest.spyOn(console, 'info').mockImplementation(() => undefined);
    jest.spyOn(console, 'error').mockImplementation(() => undefined);

    const response = await request(
      createTranscriptionApp({
        create,
        environment: { ...transcriptionEnvironment, TAISA_AI_COST_CEILING_DAILY_USD: undefined },
      }),
    )
      .post('/api/v1/transcribe')
      .attach('audio', fixturePath);

    expect(response.status).toBe(503);
    expect(response.body.error.code).toBe('TRANSCRIPTION_CONFIG_ERROR');
    expect(create).not.toHaveBeenCalled();
  });

  test('consumes the reserved estimate when OpenAI fails after invocation begins', async () => {
    const databasePath = createLedgerPath();
    const ledger = new CostLedger({ databasePath });
    const create = jest.fn().mockRejectedValue(new Error('ambiguous provider timeout'));
    jest.spyOn(console, 'info').mockImplementation(() => undefined);
    jest.spyOn(console, 'error').mockImplementation(() => undefined);

    const response = await request(createTranscriptionApp({ create, ledger }))
      .post('/api/v1/transcribe')
      .attach('audio', fixturePath);

    expect(response.status).toBe(200);
    expect(parseTranscriptionStream(response.text)).toEqual([
      expect.objectContaining({ type: 'transcript.failed', code: 'TRANSCRIPTION_FAILED' }),
    ]);
    expect(create).toHaveBeenCalledTimes(1);
    expect(ledger.listUsage()).toEqual([
      {
        recordedAt: expect.any(String),
        receipt: {
          provider: 'openai',
          model: 'gpt-4o-mini-transcribe',
          audioSeconds: 1,
          estimatedCostUsd: 0.0001,
        },
      },
    ]);
    ledger.close();
    await removeLedgerFiles(databasePath);
  });

  test('leaves no reservation or usage when validation fails before OpenAI', async () => {
    const databasePath = createLedgerPath();
    const ledger = new CostLedger({ databasePath });
    const create = jest.fn().mockResolvedValue({ text: 'must not be called' });
    jest.spyOn(console, 'info').mockImplementation(() => undefined);

    const response = await request(createTranscriptionApp({ create, ledger }))
      .post('/api/v1/transcribe')
      .field('durationSeconds', '60')
      .attach('audio', fixturePath);

    expect(response.status).toBe(422);
    expect(create).not.toHaveBeenCalled();
    expect(ledger.listUsage()).toEqual([]);
    const fullReservation = ledger.reserveUsage(
      {
        provider: 'openai',
        model: 'gpt-4o-mini-transcribe',
        audioSeconds: 1,
        estimatedCostUsd: 1,
      },
      { perRequestUsd: 1, dailyUsd: 1, monthlyUsd: 1 },
    );
    fullReservation.release();
    ledger.close();
    await removeLedgerFiles(databasePath);
  });

  test('disables OpenAI SDK retries for each transcription request', async () => {
    const create = createSuccessfulTranscription();
    jest.spyOn(console, 'info').mockImplementation(() => undefined);

    const response = await request(createTranscriptionApp({ create }))
      .post('/api/v1/transcribe')
      .attach('audio', fixturePath);

    expect(response.status).toBe(200);
    expect(create).toHaveBeenCalledTimes(1);
    expect(create.mock.calls[0][1].maxRetries).toBe(0);
    expect(create.mock.calls[0][1].signal).toBeInstanceOf(AbortSignal);
  });
});

describe('content-free usage ledger', () => {
  const receipt: UsageReceipt = {
    provider: 'openai',
    model: 'gpt-4o-mini-transcribe',
    audioSeconds: 60,
    estimatedCostUsd: 0.006,
  };
  const attemptEstimates = [
    {
      attemptId: 'primary' as const,
      receipt: { provider: 'openai' as const, model: 'o', estimatedCostUsd: 0.03 },
    },
    {
      attemptId: 'fallback' as const,
      receipt: { provider: 'anthropic' as const, model: 'a', estimatedCostUsd: 0.02 },
    },
  ];
  const ceilings = { perRequestUsd: 0.05, dailyUsd: 1, monthlyUsd: 10 };
  const primaryActual: UsageReceipt = {
    provider: 'openai',
    model: 'o',
    inputTokens: 12,
    outputTokens: 8,
    estimatedCostUsd: 0.018,
  };
  const fallbackActual: UsageReceipt = {
    provider: 'anthropic',
    model: 'a',
    inputTokens: 13,
    outputTokens: 9,
    estimatedCostUsd: 0.017,
  };

  test('strips fields outside UsageReceipt before recording', () => {
    const databasePath = createLedgerPath();
    const ledger = new CostLedger({ databasePath });
    ledger.recordUsage({ ...receipt, transcript: 'private transcript' } as UsageReceipt);

    const serialized = JSON.stringify(ledger.listUsage());
    expect(serialized).not.toContain('private transcript');
    expect(Object.keys(ledger.listUsage()[0].receipt)).toEqual([
      'provider',
      'model',
      'audioSeconds',
      'estimatedCostUsd',
    ]);
    ledger.close();
    fs.rmSync(databasePath, { force: true });
  });

  test('counts recorded and reserved spend against daily and monthly ceilings', () => {
    const databasePath = createLedgerPath();
    const ledger = new CostLedger({ databasePath });
    const at = new Date('2026-08-09T12:00:00Z');
    ledger.recordUsage({ ...receipt, estimatedCostUsd: 0.4 }, at);

    const first = ledger.reserveUsage(
      { ...receipt, estimatedCostUsd: 0.3 },
      { perRequestUsd: 0.5, dailyUsd: 1, monthlyUsd: 2 },
      at,
    );

    expect(() =>
      ledger.reserveUsage(
        { ...receipt, estimatedCostUsd: 0.4 },
        { perRequestUsd: 0.5, dailyUsd: 1, monthlyUsd: 2 },
        at,
      ),
    ).toThrow(CostLimitError);
    first.release();
    expect(() =>
      ledger.reserveUsage(
        { ...receipt, estimatedCostUsd: 0.4 },
        { perRequestUsd: 0.5, dailyUsd: 1, monthlyUsd: 2 },
        at,
      ),
    ).not.toThrow();
    ledger.close();
    fs.rmSync(databasePath, { force: true });
  });

  test('reserves both attempt maxima as one request before provider work', () => {
    const ledger = new CostLedger();
    const reservation = ledger.reserveAttempts(attemptEstimates, ceilings);

    expect(() =>
      ledger.reserveUsage(
        { provider: 'openai', model: 'next', estimatedCostUsd: 0.96 },
        { perRequestUsd: 1, dailyUsd: 1, monthlyUsd: 10 },
      ),
    ).toThrow(CostLimitError);

    reservation.release();
    ledger.close();
  });

  test('includes legacy reservations when checking multi-attempt daily and monthly totals', () => {
    const ledger = new CostLedger();
    const legacyReservation = ledger.reserveUsage(
      { provider: 'openai', model: 'legacy', estimatedCostUsd: 0.96 },
      { perRequestUsd: 1, dailyUsd: 1, monthlyUsd: 1 },
    );

    expect(() =>
      ledger.reserveAttempts(attemptEstimates, {
        perRequestUsd: 0.05,
        dailyUsd: 1,
        monthlyUsd: 1,
      }),
    ).toThrow(CostLimitError);

    legacyReservation.release();
    ledger.close();
  });

  test('rejects the whole request when combined attempt maxima exceed the per-request ceiling', () => {
    const ledger = new CostLedger();

    expect(() =>
      ledger.reserveAttempts(
        [
          {
            attemptId: 'primary',
            receipt: { provider: 'openai', model: 'o', estimatedCostUsd: 0.03 },
          },
          {
            attemptId: 'fallback',
            receipt: { provider: 'anthropic', model: 'a', estimatedCostUsd: 0.021 },
          },
        ],
        ceilings,
      ),
    ).toThrow(CostLimitError);
    expect(ledger.listUsage()).toEqual([]);
    ledger.close();
  });

  test('records actual primary success and no unused fallback estimate', () => {
    const ledger = new CostLedger();
    const reservation = ledger.reserveAttempts(attemptEstimates, ceilings);

    reservation.beginAttempt('primary');
    reservation.settleAttempt({ attemptId: 'primary', receipt: primaryActual });
    reservation.release();

    expect(ledger.listUsage().map(({ receipt: storedReceipt }) => storedReceipt)).toEqual([
      primaryActual,
    ]);
    ledger.close();
  });

  test('records failed primary estimate and actual fallback usage separately', () => {
    const ledger = new CostLedger();
    const reservation = ledger.reserveAttempts(attemptEstimates, ceilings);

    reservation.beginAttempt('primary');
    reservation.settleAttempt({ attemptId: 'primary' });
    reservation.beginAttempt('fallback');
    reservation.settleAttempt({ attemptId: 'fallback', receipt: fallbackActual });
    reservation.release();

    expect(ledger.listUsage().map(({ receipt: storedReceipt }) => storedReceipt)).toEqual([
      attemptEstimates[0].receipt,
      fallbackActual,
    ]);
    ledger.close();
  });

  test('recovers only the in-flight primary estimate after restart', () => {
    const databasePath = createLedgerPath();
    const first = new CostLedger({ databasePath });
    const reservation = first.reserveAttempts(attemptEstimates, ceilings);
    reservation.beginAttempt('primary');
    first.close();

    const restarted = new CostLedger({ databasePath });
    expect(restarted.listUsage().map(({ receipt: storedReceipt }) => storedReceipt)).toEqual([
      attemptEstimates[0].receipt,
    ]);
    restarted.close();
    fs.rmSync(databasePath, { force: true });
  });

  test('recovers both conservative estimates after fallback begins before restart', () => {
    const databasePath = createLedgerPath();
    const first = new CostLedger({ databasePath });
    const reservation = first.reserveAttempts(attemptEstimates, ceilings);
    reservation.beginAttempt('primary');
    reservation.settleAttempt({ attemptId: 'primary' });
    reservation.beginAttempt('fallback');
    first.close();

    const restarted = new CostLedger({ databasePath });
    expect(restarted.listUsage().map(({ receipt: storedReceipt }) => storedReceipt)).toEqual([
      attemptEstimates[0].receipt,
      attemptEstimates[1].receipt,
    ]);
    restarted.close();
    fs.rmSync(databasePath, { force: true });
  });

  test('rejects invalid multi-attempt IDs and ordering without recording usage', () => {
    const ledger = new CostLedger();

    expect(() =>
      ledger.reserveAttempts(
        [attemptEstimates[0], { ...attemptEstimates[0] }],
        ceilings,
      ),
    ).toThrow('exactly one primary and one fallback');
    expect(() =>
      ledger.reserveAttempts(
        [
          attemptEstimates[0],
          { attemptId: 'unknown' as any, receipt: attemptEstimates[1].receipt },
        ],
        ceilings,
      ),
    ).toThrow('exactly one primary and one fallback');

    const reservation = ledger.reserveAttempts(attemptEstimates, ceilings);
    expect(() => reservation.beginAttempt('fallback')).toThrow('primary must begin first');
    expect(() => reservation.settleAttempt({ attemptId: 'primary' })).toThrow('not in flight');
    expect(ledger.listUsage()).toEqual([]);

    reservation.beginAttempt('primary');
    reservation.settleAttempt({ attemptId: 'primary' });
    expect(() => reservation.beginAttempt('primary')).toThrow('already settled');
    expect(() => reservation.settleAttempt({ attemptId: 'unknown' as any })).toThrow('Unknown attempt');
    expect(ledger.listUsage().map(({ receipt: storedReceipt }) => storedReceipt)).toEqual([
      attemptEstimates[0].receipt,
    ]);

    reservation.release();
    ledger.close();
  });

  test('keeps successful usage in its reserved UTC day across a day rollover', () => {
    const databasePath = createLedgerPath();
    const ledger = new CostLedger({ databasePath });
    const reservedAt = new Date('2026-08-09T23:59:59Z');
    const nextDay = new Date('2026-08-10T00:00:01Z');
    jest.useFakeTimers().setSystemTime(nextDay);

    try {
      const crossing = ledger.reserveUsage(
        { ...receipt, estimatedCostUsd: 0.04 },
        { perRequestUsd: 0.05, dailyUsd: 0.05, monthlyUsd: 1 },
        reservedAt,
      );
      crossing.beginProviderInvocation();
      crossing.commit({ ...receipt, estimatedCostUsd: 0.04 });

      expect(ledger.listUsage()[0].recordedAt).toBe(reservedAt.toISOString());
      const next = ledger.reserveUsage(
        { ...receipt, estimatedCostUsd: 0.04 },
        { perRequestUsd: 0.05, dailyUsd: 0.05, monthlyUsd: 1 },
        nextDay,
      );
      next.release();
    } finally {
      jest.useRealTimers();
      ledger.close();
      fs.rmSync(databasePath, { force: true });
    }
  });

  test('keeps successful usage in its reserved UTC month across a month rollover', () => {
    const databasePath = createLedgerPath();
    const ledger = new CostLedger({ databasePath });
    const reservedAt = new Date('2026-08-31T23:59:59Z');
    const nextMonth = new Date('2026-09-01T00:00:01Z');
    jest.useFakeTimers().setSystemTime(nextMonth);

    try {
      const crossing = ledger.reserveUsage(
        { ...receipt, estimatedCostUsd: 0.04 },
        { perRequestUsd: 0.05, dailyUsd: 1, monthlyUsd: 0.05 },
        reservedAt,
      );
      crossing.beginProviderInvocation();
      crossing.commit({ ...receipt, estimatedCostUsd: 0.04 });

      expect(ledger.listUsage()[0].recordedAt).toBe(reservedAt.toISOString());
      const next = ledger.reserveUsage(
        { ...receipt, estimatedCostUsd: 0.04 },
        { perRequestUsd: 0.05, dailyUsd: 1, monthlyUsd: 0.05 },
        nextMonth,
      );
      next.release();
    } finally {
      jest.useRealTimers();
      ledger.close();
      fs.rmSync(databasePath, { force: true });
    }
  });

  test('persists content-free receipts and in-flight estimates across restart', () => {
    const databasePath = createLedgerPath();
    const first = new CostLedger({ databasePath });
    first.recordUsage(receipt, new Date('2026-08-09T12:00:00Z'));
    const inFlight = first.reserveUsage(
      { ...receipt, estimatedCostUsd: 0.01 },
      { perRequestUsd: 1, dailyUsd: 1, monthlyUsd: 1 },
      new Date('2026-08-09T12:01:00Z'),
    );
    inFlight.beginProviderInvocation();
    first.close();

    const restarted = new CostLedger({ databasePath });
    expect(restarted.listUsage().map((entry) => entry.receipt.estimatedCostUsd)).toEqual([
      0.006,
      0.01,
    ]);
    restarted.close();
    fs.rmSync(databasePath, { force: true });
  });

  test('enforces concurrent reservations atomically across ledger connections', () => {
    const databasePath = createLedgerPath();
    const first = new CostLedger({ databasePath });
    const second = new CostLedger({ databasePath });
    const at = new Date('2026-08-09T12:00:00Z');

    const held = first.reserveUsage(
      { ...receipt, estimatedCostUsd: 0.6 },
      { perRequestUsd: 1, dailyUsd: 1, monthlyUsd: 1 },
      at,
    );
    expect(() =>
      second.reserveUsage(
        { ...receipt, estimatedCostUsd: 0.5 },
        { perRequestUsd: 1, dailyUsd: 1, monthlyUsd: 1 },
        at,
      ),
    ).toThrow(CostLimitError);

    held.release();
    first.close();
    second.close();
    fs.rmSync(databasePath, { force: true });
  });

  test('records authoritative usage and surfaces an overrun above the reserved bound', () => {
    const databasePath = createLedgerPath();
    const ledger = new CostLedger({ databasePath });
    const reservation = ledger.reserveUsage(
      { ...receipt, estimatedCostUsd: 0.01 },
      { perRequestUsd: 1, dailyUsd: 1, monthlyUsd: 1 },
    );
    reservation.beginProviderInvocation();

    expect(() => reservation.commit({ ...receipt, estimatedCostUsd: 0.02 })).toThrow(
      UsageExceedsReservationError,
    );
    expect(ledger.listUsage()[0].receipt.estimatedCostUsd).toBe(0.02);
    ledger.close();
    fs.rmSync(databasePath, { force: true });
  });
});
