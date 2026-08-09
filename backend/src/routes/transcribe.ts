import { Router } from 'express';
import multer from 'multer';
import OpenAI from 'openai';
import fs from 'fs';
import type { UsageReceipt } from '@taisa/shared';
import { logRequestError } from '../middleware/requestContext';
import {
  CostLedger,
  CostLimitError,
  costLedger,
  readCostCeilings,
  type CostCeilings,
  type CostReservation,
} from '../services/usage/costLedger';

const upload = multer({ dest: '/tmp/beats-audio/' });

type TranscriptionClient = Pick<OpenAI, 'audio'>;

interface TranscribeRouterOptions {
  client?: TranscriptionClient;
  ledger?: CostLedger;
  environment?: Record<string, string | undefined>;
}

interface TranscriptionConfig {
  model: string;
  maxDurationSeconds: number;
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
    priceUsdPerMinute: requiredNonNegativeNumber(
      environment,
      'TAISA_TRANSCRIPTION_PRICE_USD_PER_MINUTE',
    ),
    ceilings: readCostCeilings(environment),
  };
}

function parseDurationSeconds(value: unknown): number | null {
  if (typeof value !== 'string' || value.trim() === '') return null;
  const duration = Number(value);
  return Number.isFinite(duration) && duration > 0 ? duration : null;
}

function safeAudioExtension(originalName: string | undefined): string {
  const extension = originalName?.split('.').pop()?.toLowerCase().replace(/[^a-z0-9]/g, '');
  return extension?.slice(0, 10) || 'm4a';
}

export function createTranscribeRouter(options: TranscribeRouterOptions = {}) {
  const router = Router();
  const ledger = options.ledger ?? costLedger;
  const environment = options.environment ?? process.env;

  // POST /api/v1/transcribe
  router.post('/', upload.single('audio'), async (req, res) => {
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

      const durationSeconds = parseDurationSeconds(req.body.durationSeconds);
      if (durationSeconds === null) {
        throw new TranscriptionBoundaryError(
          400,
          'INVALID_AUDIO_DURATION',
          'A valid audio duration is required',
        );
      }
      if (durationSeconds > config.maxDurationSeconds) {
        throw new TranscriptionBoundaryError(
          413,
          'AUDIO_DURATION_LIMIT_EXCEEDED',
          'Audio duration exceeds the configured limit',
        );
      }

      const estimatedCostUsd = (durationSeconds / 60) * config.priceUsdPerMinute;
      try {
        reservation = ledger.reserveCost(estimatedCostUsd, config.ceilings);
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
      const transcription = await client.audio.transcriptions.create({
        file: new File([fs.readFileSync(req.file.path)], fileName, { type: req.file.mimetype }),
        model: config.model,
        language: 'en',
      });

      const usage: UsageReceipt = {
        provider: 'openai',
        model: config.model,
        audioSeconds: durationSeconds,
        estimatedCostUsd,
      };
      reservation.commit(usage);
      result = {
        status: 200,
        body: {
          success: true,
          data: { transcript: transcription.text, durationSeconds, usage },
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
