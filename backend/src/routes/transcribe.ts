import { Router } from 'express';
import type { NextFunction, Request, Response } from 'express';
import multer from 'multer';
import OpenAI from 'openai';
import fs from 'fs';
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

type TranscriptionClient = Pick<OpenAI, 'audio'>;

interface TranscribeRouterOptions {
  client?: TranscriptionClient;
  ledger?: UsageLedger;
  environment?: Record<string, string | undefined>;
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
  const maxDurationSeconds = requiredNonNegativeNumber(
    environment,
    'TAISA_TRANSCRIPTION_MAX_DURATION_SECONDS',
  );
  if (maxDurationSeconds === 0) {
    throw new Error('TAISA_TRANSCRIPTION_MAX_DURATION_SECONDS must be greater than zero');
  }

  return {
    model: requiredString(environment, 'TAISA_TRANSCRIPTION_MODEL'),
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

export function createTranscribeRouter(options: TranscribeRouterOptions = {}) {
  const router = Router();
  const ledger = options.ledger ?? costLedger;
  const environment = options.environment ?? process.env;

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

    return multer({
      dest: '/tmp/beats-audio/',
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
    });
  };

  // POST /api/v1/transcribe
  router.post('/', uploadAudio, async (req, res) => {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: { code: 'NO_FILE', message: 'Audio file required' },
      });
    }

    let reservation: CostReservation | undefined;
    let result: RouteResult;
    try {
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
      const transcription = await client.audio.transcriptions.create(
        {
          file: new File([fs.readFileSync(req.file.path)], fileName, { type: req.file.mimetype }),
          model: config.model,
          language: 'en',
        },
        { maxRetries: 0 },
      );

      const usage = estimatedUsage;
      reservation.commit(usage);
      result = {
        status: 200,
        body: {
          success: true,
          data: {
            transcript: transcription.text,
            durationSeconds: measuredDurationSeconds,
            usage,
          },
        },
      };
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
      } else {
        logRequestError(req, 'TRANSCRIPTION_FAILED', error);
        result = {
          status: 500,
          body: {
            success: false,
            error: { code: 'TRANSCRIPTION_FAILED', message: 'Unable to transcribe audio' },
          },
        };
      }
    } finally {
      reservation?.release();
      await fs.promises.rm(req.file.path, { force: true });
    }

    return res.status(result.status).json(result.body);
  });

  return router;
}

export default createTranscribeRouter();
