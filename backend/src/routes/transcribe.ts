import { Router } from 'express';
import type { NextFunction, Request, Response } from 'express';
import multer from 'multer';
import OpenAI from 'openai';
import fs from 'fs';
import { createHash } from 'node:crypto';
import type { UsageReceipt } from '@taisa/shared';
import { logRequestError } from '../middleware/requestContext';
import {
  CostLimitError,
  costLedger,
  readCostCeilings,
  type CostCeilings,
  type CostReservation,
  type UsageLedger,
} from '../services/usage/costLedger';
import { measureAudioDurationSeconds } from '../services/transcription/audioDuration';
import {
  streamTranscription,
  type StreamingTranscriptionProvider,
} from '../services/transcription/streamingTranscription';
import {
  TranscriptionIdempotencyConflictError,
  TranscriptionIdempotencyStore,
  TranscriptionRequestNotFoundError,
} from '../services/transcription/transcriptionIdempotencyStore';

type TranscriptionClient = Pick<OpenAI, 'audio'>;
const UPLOAD_DIRECTORY = '/tmp/beats-audio/';

interface TranscribeRouterOptions {
  client?: TranscriptionClient;
  ledger?: UsageLedger;
  environment?: Record<string, string | undefined>;
  idempotencyStore?: TranscriptionIdempotencyStore;
  allowLegacyOwnerHeader?: boolean;
}

interface TranscriptionConfig {
  model: string;
  maxDurationSeconds: number;
  maxUploadBytes: number;
  priceUsdPerMinute: number;
  ceilings: CostCeilings;
}

interface RouteResult {
  status: number;
  body: Record<string, unknown>;
}

class TranscriptionBoundaryError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly shouldLog = false,
    readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'TranscriptionBoundaryError';
  }
}

function requiredString(environment: Record<string, string | undefined>, name: string): string {
  const value = environment[name]?.trim();
  if (!value) throw new Error(`${name} must be configured`);
  return value;
}

function requiredNonNegativeNumber(
  environment: Record<string, string | undefined>,
  name: string,
): number {
  const value = Number(requiredString(environment, name));
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`${name} must be a non-negative number`);
  }
  return value;
}

function loadTranscriptionConfig(
  environment: Record<string, string | undefined>,
): TranscriptionConfig {
  const model = requiredString(environment, 'TAISA_TRANSCRIPTION_MODEL');
  if (model !== 'gpt-4o-transcribe' && model !== 'gpt-4o-mini-transcribe') {
    throw new Error('TAISA_TRANSCRIPTION_MODEL must support streaming log probabilities');
  }
  const maxDurationSeconds = requiredNonNegativeNumber(
    environment,
    'TAISA_TRANSCRIPTION_MAX_DURATION_SECONDS',
  );
  if (maxDurationSeconds === 0) {
    throw new Error('TAISA_TRANSCRIPTION_MAX_DURATION_SECONDS must be greater than zero');
  }

  return {
    model,
    maxDurationSeconds,
    maxUploadBytes: loadMaxUploadBytes(environment),
    priceUsdPerMinute: requiredNonNegativeNumber(
      environment,
      'TAISA_TRANSCRIPTION_PRICE_USD_PER_MINUTE',
    ),
    ceilings: readCostCeilings(environment),
  };
}

function loadMaxUploadBytes(environment: Record<string, string | undefined>): number {
  const maxUploadBytes = requiredNonNegativeNumber(
    environment,
    'TAISA_TRANSCRIPTION_MAX_UPLOAD_BYTES',
  );
  if (!Number.isSafeInteger(maxUploadBytes) || maxUploadBytes === 0) {
    throw new Error('TAISA_TRANSCRIPTION_MAX_UPLOAD_BYTES must be a positive safe integer');
  }
  return maxUploadBytes;
}

function parseDurationSeconds(value: unknown): number | null {
  if (value === undefined) return null;
  if (typeof value !== 'string' || value.trim() === '') return Number.NaN;
  const duration = Number(value);
  return Number.isFinite(duration) && duration > 0 ? duration : Number.NaN;
}

function safeAudioExtension(originalName: string | undefined): string {
  const extension = originalName?.split('.').pop()?.toLowerCase().replace(/[^a-z0-9]/g, '');
  return extension?.slice(0, 10) || 'm4a';
}

/** Removes files left by an interrupted earlier process before accepting fresh audio. */
export async function cleanupStaleTranscriptionUploads(directory = UPLOAD_DIRECTORY): Promise<void> {
  let entries: string[];
  try {
    entries = await fs.promises.readdir(directory);
  } catch (error: any) {
    if (error?.code === 'ENOENT') return;
    throw error;
  }
  await Promise.all(entries.map((entry) =>
    fs.promises.rm(`${directory.replace(/\/$/, '')}/${entry}`, { recursive: true, force: true }),
  ));
}

export function createTranscribeRouter(options: TranscribeRouterOptions = {}) {
  const router = Router();
  const ledger = options.ledger ?? costLedger;
  const environment = options.environment ?? process.env;
  const staleUploadCleanup = cleanupStaleTranscriptionUploads();
  let defaultIdempotencyStore: TranscriptionIdempotencyStore | undefined;

  const receiptStore = () => {
    if (options.idempotencyStore) return options.idempotencyStore;
    if (!defaultIdempotencyStore) {
      defaultIdempotencyStore = new TranscriptionIdempotencyStore({
        databasePath: environment.TAISA_USAGE_LEDGER_PATH?.trim() || 'taisa-usage-ledger.sqlite',
        encryptionKeyBase64: environment.TAISA_TRANSCRIPTION_RECEIPT_ENCRYPTION_KEY?.trim() || '',
      });
    }
    return defaultIdempotencyStore;
  };

  const requestOwner = (req: Request, res: Response): string | null => {
    const authenticated = typeof res.locals.deviceCredentialId === 'string'
      ? res.locals.deviceCredentialId.trim() : '';
    const legacyAllowed = options.allowLegacyOwnerHeader
      ?? environment.NODE_ENV !== 'production';
    const legacy = legacyAllowed ? req.header('X-User-ID')?.trim() ?? '' : '';
    const owner = authenticated || legacy;
    if (!owner || owner.length > 200) {
      res.status(401).json({
        success: false,
        error: { code: 'DEVICE_AUTHENTICATION_REQUIRED', message: 'Device authentication required' },
      });
      return null;
    }
    return owner;
  };

  const authenticateRequest = (req: Request, res: Response, next: NextFunction) => {
    const owner = requestOwner(req, res);
    if (!owner) return;
    res.locals.transcriptionOwnerId = owner;
    return next();
  };

  const uploadAudio = (request: Request, response: Response, next: NextFunction) => {
    let maxUploadBytes: number;
    try {
      maxUploadBytes = loadMaxUploadBytes(environment);
    } catch (error) {
      logRequestError(request, 'TRANSCRIPTION_CONFIG_ERROR', error);
      return response.status(503).json({
        success: false,
        error: { code: 'TRANSCRIPTION_CONFIG_ERROR', message: 'Transcription is not configured' },
      });
    }

    return staleUploadCleanup.then(() => multer({
      dest: UPLOAD_DIRECTORY,
      limits: { fileSize: maxUploadBytes },
    }).single('audio')(request, response, (error: any) => {
      if (error?.code === 'LIMIT_FILE_SIZE') {
        return response.status(413).json({
          success: false,
          error: {
            code: 'AUDIO_UPLOAD_LIMIT_EXCEEDED',
            message: 'Audio upload exceeds the configured byte limit',
          },
        });
      }
      if (error) {
        logRequestError(request, 'AUDIO_UPLOAD_FAILED', error);
        return response.status(400).json({
          success: false,
          error: { code: 'AUDIO_UPLOAD_FAILED', message: 'Unable to accept audio upload' },
        });
      }
      return next();
    })).catch((error) => {
      logRequestError(request, 'TRANSCRIPTION_UPLOAD_CLEANUP_FAILED', error);
      return response.status(503).json({
        success: false,
        error: { code: 'TRANSCRIPTION_UPLOAD_CLEANUP_FAILED', message: 'Transcription is temporarily unavailable' },
      });
    });
  };

  // POST /api/v1/transcribe
  router.post('/', authenticateRequest, uploadAudio, async (req, res) => {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: { code: 'NO_FILE', message: 'Audio file required' },
      });
    }

    let reservation: CostReservation | undefined;
    let result: RouteResult | undefined;
    let streamStarted = false;
    let terminalWritten = false;
    const providerAbort = new AbortController();
    const ownerId = String(res.locals.transcriptionOwnerId);
    const suppliedIdempotencyKey = req.header('Idempotency-Key')?.trim();
    const idempotencyKey = suppliedIdempotencyKey
      || (environment.NODE_ENV !== 'production' ? req.requestId : undefined);
    const abortProvider = () => providerAbort.abort();
    req.once('aborted', abortProvider);
    res.once('close', abortProvider);
    try {
      if (!idempotencyKey || idempotencyKey.length > 200) {
        throw new TranscriptionBoundaryError(
          400, 'INVALID_IDEMPOTENCY_KEY', 'A bounded Idempotency-Key is required',
        );
      }
      let config: TranscriptionConfig;
      try {
        config = loadTranscriptionConfig(environment);
      } catch (error) {
        throw new TranscriptionBoundaryError(
          503,
          'TRANSCRIPTION_CONFIG_ERROR',
          'Transcription is not configured',
          true,
          error,
        );
      }

      const measuredDurationSeconds = await measureAudioDurationSeconds(req.file.path);
      const audioSHA256 = createHash('sha256')
        .update(await fs.promises.readFile(req.file.path)).digest('hex');
      const idempotency = receiptStore().begin({
        key: idempotencyKey,
        requestId: req.requestId ?? 'missing-request-id',
        ownerId,
        audioSHA256,
      });
      if (idempotency.status === 'ambiguous') {
        throw new TranscriptionBoundaryError(
          409, 'AMBIGUOUS_PAID_WORK', 'Paid transcription work requires reconciliation',
        );
      }
      if (idempotency.status === 'completed') {
        res.status(200);
        res.setHeader('Content-Type', 'application/x-ndjson; charset=utf-8');
        res.setHeader('Cache-Control', 'no-store');
        res.flushHeaders();
        streamStarted = true;
        terminalWritten = true;
        res.write(`${JSON.stringify(idempotency.event)}\n`);
        res.end();
        return;
      }
      const callerDurationSeconds = parseDurationSeconds(req.body.durationSeconds);
      if (Number.isNaN(callerDurationSeconds)) {
        throw new TranscriptionBoundaryError(
          400,
          'INVALID_AUDIO_DURATION',
          'Audio duration metadata must be a positive number',
        );
      }
      if (
        callerDurationSeconds !== null &&
        Math.abs(callerDurationSeconds - measuredDurationSeconds) >
          Math.max(2, measuredDurationSeconds * 0.1)
      ) {
        throw new TranscriptionBoundaryError(
          422,
          'AUDIO_DURATION_MISMATCH',
          'Audio duration metadata does not match the uploaded audio',
        );
      }
      if (measuredDurationSeconds > config.maxDurationSeconds) {
        throw new TranscriptionBoundaryError(
          413,
          'AUDIO_DURATION_LIMIT_EXCEEDED',
          'Audio duration exceeds the configured limit',
        );
      }

      const estimatedCostUsd = (measuredDurationSeconds / 60) * config.priceUsdPerMinute;
      const estimatedUsage: UsageReceipt = {
        provider: 'openai',
        model: config.model,
        audioSeconds: measuredDurationSeconds,
        estimatedCostUsd,
      };
      try {
        reservation = ledger.reserveUsage(estimatedUsage, config.ceilings);
      } catch (error) {
        if (error instanceof CostLimitError) {
          throw new TranscriptionBoundaryError(
            429,
            error.code,
            'Configured AI cost limit reached',
          );
        }
        throw error;
      }

      const fileName = `audio.${safeAudioExtension(req.file.originalname)}`;
      const client = options.client ?? new OpenAI({ apiKey: environment.OPENAI_API_KEY });
      reservation.beginProviderInvocation();
      receiptStore().markProviderStarted(idempotencyKey);
      const provider = client.audio.transcriptions.create.bind(
        client.audio.transcriptions,
      ) as unknown as StreamingTranscriptionProvider;

      res.status(200);
      res.setHeader('Content-Type', 'application/x-ndjson; charset=utf-8');
      res.setHeader('Cache-Control', 'no-store');
      res.flushHeaders();
      streamStarted = true;

      for await (const event of streamTranscription({
        requestId: req.requestId ?? 'missing-request-id',
        file: new File([fs.readFileSync(req.file.path)], fileName, { type: req.file.mimetype }),
        model: config.model,
        durationSeconds: measuredDurationSeconds,
        usage: estimatedUsage,
        abortSignal: providerAbort.signal,
      }, provider, (failure) => {
        logRequestError(req, `TRANSCRIPTION_PROVIDER_${failure}`, new Error(failure));
      })) {
        if (res.destroyed) break;
        if (event.type !== 'transcript.delta') {
          terminalWritten = true;
          receiptStore().complete(idempotencyKey, event as unknown as Record<string, unknown>);
          if (event.type === 'transcript.completed' || event.type === 'transcript.no_speech') {
            reservation.commit(estimatedUsage);
          } else {
            logRequestError(req, event.code, new Error(event.code));
          }
        }
        res.write(`${JSON.stringify(event)}\n`);
      }
    } catch (error) {
      if (error instanceof TranscriptionBoundaryError) {
        if (error.shouldLog) logRequestError(req, error.code, error.cause ?? error);
        result = {
          status: error.status,
          body: {
            success: false,
            error: { code: error.code, message: error.message },
          },
        };
      } else if (error instanceof TranscriptionIdempotencyConflictError) {
        result = {
          status: 409,
          body: {
            success: false,
            error: { code: error.code, message: 'Idempotency key conflicts with another request' },
          },
        };
      } else {
        logRequestError(req, 'TRANSCRIPTION_FAILED', error);
        if (streamStarted && !res.destroyed && !terminalWritten) {
          const terminal = {
            type: 'transcript.failed',
            requestId: req.requestId ?? 'missing-request-id',
            sequence: 0,
            code: 'TRANSCRIPTION_FAILED',
          };
          receiptStore().complete(idempotencyKey!, terminal);
          res.write(`${JSON.stringify(terminal)}\n`);
          terminalWritten = true;
        } else if (!streamStarted) {
          result = {
            status: 500,
            body: {
              success: false,
              error: { code: 'TRANSCRIPTION_FAILED', message: 'Unable to transcribe audio' },
            },
          };
        }
      }
    } finally {
      req.off('aborted', abortProvider);
      res.off('close', abortProvider);
      reservation?.release();
      try {
        await fs.promises.rm(req.file.path, { force: true });
      } catch (error) {
        logRequestError(req, 'TRANSCRIPTION_AUDIO_CLEANUP_FAILED', error);
        if (!streamStarted) {
          result = {
            status: 500,
            body: {
              success: false,
              error: {
                code: 'TRANSCRIPTION_AUDIO_CLEANUP_FAILED',
                message: 'Temporary audio cleanup failed',
              },
            },
          };
        }
      }
    }

    if (streamStarted) return res.end();
    const fallback = result ?? {
      status: 500,
      body: {
        success: false,
        error: { code: 'TRANSCRIPTION_FAILED', message: 'Unable to transcribe audio' },
      },
    };
    return res.status(fallback.status).json(fallback.body);
  });

  router.get('/requests/:requestId', (req, res) => {
    const ownerId = requestOwner(req, res);
    if (!ownerId) return;
    const result = receiptStore().reconcile(req.params.requestId, ownerId);
    if (result.status === 'missing') {
      return res.status(404).json({
        success: false,
        error: { code: 'REQUEST_NOT_FOUND', message: 'Transcription request not found' },
      });
    }
    return res.json({ success: true, data: result });
  });

  router.post('/requests/:requestId/resolve', (req, res) => {
    const ownerId = requestOwner(req, res);
    if (!ownerId) return;
    if (req.body?.decision !== 'retry') {
      return res.status(400).json({
        success: false,
        error: { code: 'INVALID_RESOLUTION', message: 'A retry decision is required' },
      });
    }
    try {
      return res.json({
        success: true,
        data: receiptStore().authorizeRetry(req.params.requestId, ownerId),
      });
    } catch (error) {
      if (error instanceof TranscriptionRequestNotFoundError) {
        return res.status(404).json({
          success: false,
          error: { code: error.code, message: 'Transcription request not found' },
        });
      }
      return res.status(409).json({
        success: false,
        error: { code: 'IDEMPOTENCY_STATE_CONFLICT', message: 'Request is not awaiting resolution' },
      });
    }
  });

  return router;
}

export default createTranscribeRouter();
