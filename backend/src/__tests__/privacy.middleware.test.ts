import express from 'express';
import fs from 'fs';
import os from 'os';
import path from 'path';
import request from 'supertest';
import type { UsageReceipt } from '@taisa/shared';
import { contentSafeErrorHandler, requestContext } from '../middleware/requestContext';
import coachingRouter from '../routes/coaching';
import { createTranscribeRouter } from '../routes/transcribe';
import { CostLedger, CostLimitError } from '../services/usage/costLedger';

jest.mock('../services/coaching/coachingGateway', () => ({
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
  TAISA_TRANSCRIPTION_MODEL: 'whisper-mock',
  TAISA_TRANSCRIPTION_MAX_DURATION_SECONDS: '300',
  TAISA_TRANSCRIPTION_PRICE_USD_PER_MINUTE: '0.006',
  TAISA_AI_COST_CEILING_PER_REQUEST_USD: '0.05',
  TAISA_AI_COST_CEILING_DAILY_USD: '1',
  TAISA_AI_COST_CEILING_MONTHLY_USD: '10',
};

function createAudioFixture(): string {
  const fixturePath = path.join(
    os.tmpdir(),
    `taisa-transcription-fixture-${process.pid}-${Math.random().toString(16).slice(2)}.m4a`,
  );
  fs.writeFileSync(fixturePath, Buffer.from('synthetic audio fixture'));
  return fixturePath;
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

describe('content-free request telemetry', () => {
  let logSpy: jest.SpyInstance;
  const originalCostEnvironment = {
    perRequest: process.env.TAISA_AI_COST_CEILING_PER_REQUEST_USD,
    daily: process.env.TAISA_AI_COST_CEILING_DAILY_USD,
    monthly: process.env.TAISA_AI_COST_CEILING_MONTHLY_USD,
  };

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
      .set('x-request-id', 'safe-request-1')
      .send(validRequest);

    expect(response.status).toBe(200);
    expect(response.headers['x-request-id']).toBe('safe-request-1');

    const output = logSpy.mock.calls.flat().join(' ');
    const event = JSON.parse(String(logSpy.mock.calls[0][0]));
    expect(event).toEqual({
      requestId: 'safe-request-1',
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

  test('logs only safe error metadata and returns a fixed public message', async () => {
    const errorSpy = jest.spyOn(console, 'error').mockImplementation(() => undefined);
    const app = express();
    app.use(requestContext);
    app.get('/failure', () => {
      throw new Error('provider payload contains private response text');
    });
    app.use(contentSafeErrorHandler);

    const response = await request(app)
      .get('/failure')
      .set('x-request-id', 'safe-error-request');

    expect(response.status).toBe(500);
    expect(response.body).toEqual({
      success: false,
      error: { code: 'INTERNAL_ERROR', message: 'An internal error occurred' },
    });
    const serialized = errorSpy.mock.calls.flat().join(' ');
    expect(serialized).toContain('safe-error-request');
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

  test.each([
    ['succeeds', jest.fn().mockResolvedValue({ text: 'private transcript' }), 200],
    ['fails', jest.fn().mockRejectedValue(new Error('provider payload: private transcript')), 500],
  ])('deletes uploaded audio when transcription %s', async (_case, create, expectedStatus) => {
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
      .field('durationSeconds', '60')
      .attach('audio', fixturePath);

    expect(response.status).toBe(expectedStatus);
    expect(capturedTempPath).not.toBe('');
    expect(fs.existsSync(capturedTempPath)).toBe(false);
    if (expectedStatus === 500) {
      expect(errorSpy.mock.calls.flat().join(' ')).not.toContain('private transcript');
      expect(JSON.stringify(response.body)).not.toContain('private transcript');
    }
  });

  test('returns transcript but records only content-free transcription usage', async () => {
    const ledger = new CostLedger();
    const create = jest.fn().mockResolvedValue({ text: 'private transcript' });
    jest.spyOn(console, 'info').mockImplementation(() => undefined);

    const response = await request(createTranscriptionApp({ create, ledger }))
      .post('/api/v1/transcribe')
      .field('durationSeconds', '60')
      .attach('audio', fixturePath);

    expect(response.status).toBe(200);
    expect(response.body.data.transcript).toBe('private transcript');
    expect(response.body.data.usage).toEqual({
      provider: 'openai',
      model: 'whisper-mock',
      audioSeconds: 60,
      estimatedCostUsd: 0.006,
    });
    expect(ledger.listUsage()).toEqual([
      {
        recordedAt: expect.any(String),
        receipt: response.body.data.usage,
      },
    ]);
    expect(JSON.stringify(ledger.listUsage())).not.toContain('private transcript');
  });

  test('rejects audio above the configured duration ceiling before OpenAI', async () => {
    const create = jest.fn().mockResolvedValue({ text: 'must not be called' });
    jest.spyOn(console, 'info').mockImplementation(() => undefined);

    const response = await request(createTranscriptionApp({ create }))
      .post('/api/v1/transcribe')
      .field('durationSeconds', '301')
      .attach('audio', fixturePath);

    expect(response.status).toBe(413);
    expect(response.body.error.code).toBe('AUDIO_DURATION_LIMIT_EXCEEDED');
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
          TAISA_TRANSCRIPTION_PRICE_USD_PER_MINUTE: '1',
          TAISA_AI_COST_CEILING_PER_REQUEST_USD: '0.50',
        },
      }),
    )
      .post('/api/v1/transcribe')
      .field('durationSeconds', '60')
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
      .field('durationSeconds', '60')
      .attach('audio', fixturePath);

    expect(response.status).toBe(503);
    expect(response.body.error.code).toBe('TRANSCRIPTION_CONFIG_ERROR');
    expect(create).not.toHaveBeenCalled();
  });
});

describe('content-free usage ledger', () => {
  const receipt: UsageReceipt = {
    provider: 'openai',
    model: 'whisper-mock',
    audioSeconds: 60,
    estimatedCostUsd: 0.006,
  };

  test('strips fields outside UsageReceipt before recording', () => {
    const ledger = new CostLedger();
    ledger.recordUsage({ ...receipt, transcript: 'private transcript' } as UsageReceipt);

    const serialized = JSON.stringify(ledger.listUsage());
    expect(serialized).not.toContain('private transcript');
    expect(Object.keys(ledger.listUsage()[0].receipt)).toEqual([
      'provider',
      'model',
      'audioSeconds',
      'estimatedCostUsd',
    ]);
  });

  test('counts recorded and reserved spend against daily and monthly ceilings', () => {
    const ledger = new CostLedger();
    const at = new Date('2026-08-09T12:00:00Z');
    ledger.recordUsage({ ...receipt, estimatedCostUsd: 0.4 }, at);

    const first = ledger.reserveCost(
      0.3,
      { perRequestUsd: 0.5, dailyUsd: 1, monthlyUsd: 2 },
      at,
    );

    expect(() =>
      ledger.reserveCost(0.4, { perRequestUsd: 0.5, dailyUsd: 1, monthlyUsd: 2 }, at),
    ).toThrow(CostLimitError);
    first.release();
    expect(() =>
      ledger.reserveCost(0.4, { perRequestUsd: 0.5, dailyUsd: 1, monthlyUsd: 2 }, at),
    ).not.toThrow();
  });
});
