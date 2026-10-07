import { Router } from 'express';
import { CoachingRequestSchema } from '../schemas/coaching';
import {
  estimateConfiguredCoachingAttempts,
  requestCoaching,
  requestStreamingCoaching,
} from '../services/coaching/coachingGateway';
import { getConfiguredFallbackProvider } from '../services/coaching/fallbackProvider';
import type { CoachingRequest, CoachingStreamFailureCode } from '@taisa/shared';
import { CoachingIdempotencyStore, IdempotencyConflictError } from '../services/coaching/coachingIdempotencyStore';
import {
  AmbiguousPaidWorkError,
  executeCoachingStream,
  type PaidCoachingStreamItem,
} from '../services/coaching/streamingCoaching';
import { ContentFreeFallbackError } from '../services/coaching/fallbackProvider';
import {
  CostConfigurationError,
  CostLimitError,
  readCostCeilings,
  reserveAttempts,
} from '../services/usage/costLedger';

let defaultIdempotencyStore: CoachingIdempotencyStore | undefined;

function getDefaultIdempotencyStore(): CoachingIdempotencyStore {
  if (!defaultIdempotencyStore) {
    defaultIdempotencyStore = new CoachingIdempotencyStore({
      databasePath: process.env.TAISA_USAGE_LEDGER_PATH?.trim() || 'taisa-usage-ledger.sqlite',
      encryptionKeyBase64: process.env.TAISA_COACHING_RECEIPT_ENCRYPTION_KEY?.trim() || '',
    });
  }
  return defaultIdempotencyStore;
}

async function* defaultPaidExecution(
  request: CoachingRequest,
  context: { idempotencyKey: string },
): AsyncIterable<PaidCoachingStreamItem> {
  const ceilings = readCostCeilings();
  const reservation = reserveAttempts(
    estimateConfiguredCoachingAttempts(request),
    ceilings,
    context.idempotencyKey,
  );
  try {
    for await (const item of requestStreamingCoaching(
      request,
      getConfiguredFallbackProvider(),
      reservation,
    )) {
      if (item.kind === 'delta') yield item;
      else yield { kind: 'completed', response: item.response };
    }
  } finally {
    reservation.release();
  }
}

export function createCoachingRouter(options: {
  idempotencyStore?: CoachingIdempotencyStore;
  paidExecution?: (
    request: CoachingRequest,
    context: { idempotencyKey: string },
  ) => AsyncIterable<PaidCoachingStreamItem>;
} = {}) {
const router = Router();

function operationalFailureCode(error: unknown): string {
  if (error instanceof ContentFreeFallbackError) {
    return 'COACHING_FALLBACK_EXHAUSTED';
  }
  const value = error as {
    status?: unknown;
    type?: unknown;
  } | null;
  const status = typeof value?.status === 'number' && Number.isInteger(value.status)
    ? `_HTTP_${value.status}`
    : '';
  const type = value?.type === 'invalid_request_error'
    ? 'INVALID_REQUEST_ERROR'
    : value?.type === 'authentication_error'
      ? 'AUTHENTICATION_ERROR'
      : value?.type === 'rate_limit_error'
        ? 'RATE_LIMIT_ERROR'
        : value?.type === 'provider_error'
          ? 'PROVIDER_ERROR'
          : 'UNKNOWN_ERROR';
  return `COACHING_FAILED${status}_${type}`;
}

function streamFailureCode(error: unknown): CoachingStreamFailureCode {
  if (error instanceof CostLimitError) return 'COST_LIMIT_REACHED';
  const value = error as { code?: unknown; status?: unknown; type?: unknown } | null;
  if (value?.code === 'INVALID_COACHING_OUTPUT') return 'INVALID_COACHING_OUTPUT';
  if (value?.status === 401 || value?.type === 'authentication_error') return 'AUTHENTICATION_FAILED';
  if (value?.status === 429 || value?.type === 'rate_limit_error') return 'RATE_LIMITED';
  return 'COACHING_UNAVAILABLE';
}

router.post('/respond', async (req, res) => {
  const parsed = CoachingRequestSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({
      success: false,
      error: { code: 'VALIDATION_ERROR', message: parsed.error.message },
    });
  }

  let reservation: ReturnType<typeof reserveAttempts> | undefined;
  try {
    const ceilings = readCostCeilings();
    const estimatedAttempts = estimateConfiguredCoachingAttempts(parsed.data);
    reservation = reserveAttempts(estimatedAttempts, ceilings);
    const execution = await requestCoaching(parsed.data, undefined, reservation);
    return res.json({ success: true, data: execution.response });
  } catch (error: any) {
    if (error instanceof CostLimitError) {
      return res.status(429).json({
        success: false,
        error: { code: error.code, message: 'Configured AI cost limit reached' },
      });
    }
    if (error instanceof CostConfigurationError) {
      return res.status(503).json({
        success: false,
        error: { code: error.code, message: 'AI cost limits are not configured' },
      });
    }
    if (error?.code === 'INVALID_COACHING_OUTPUT' && error?.recoverable === true) {
      return res.status(502).json({
        success: false,
        error: {
          code: 'INVALID_COACHING_OUTPUT',
          message: 'The coaching provider returned an invalid structured response',
          recoverable: true,
        },
      });
    }

    return res.status(500).json({
      success: false,
      error: {
        code: operationalFailureCode(error),
        message: 'Unable to complete the coaching request',
      },
    });
  } finally {
    reservation?.release();
  }
});

router.post('/respond/stream', async (req, res) => {
  const parsed = CoachingRequestSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({
      success: false,
      error: { code: 'VALIDATION_ERROR', message: parsed.error.message },
    });
  }
  const idempotencyKey = req.header('Idempotency-Key')?.trim();
  if (!idempotencyKey || idempotencyKey.length > 200) {
    return res.status(400).json({
      success: false,
      error: { code: 'INVALID_IDEMPOTENCY_KEY', message: 'A bounded Idempotency-Key is required' },
    });
  }

  const store = options.idempotencyStore ?? getDefaultIdempotencyStore();
  let lastSequence = -1;
  try {
    const events = executeCoachingStream({
      request: parsed.data,
      idempotencyKey,
      store,
      paidExecution: options.paidExecution ?? defaultPaidExecution,
    });
    for await (const event of events) {
      if (!res.headersSent) {
        res.status(200);
        res.setHeader('Content-Type', 'application/x-ndjson; charset=utf-8');
        res.setHeader('Cache-Control', 'no-store');
      }
      lastSequence = event.sequence;
      res.write(`${JSON.stringify(event)}\n`);
    }
    return res.end();
  } catch (error) {
    if (res.headersSent) {
      const code = streamFailureCode(error);
      try { store.fail(idempotencyKey, code, false); } catch { /* Preserve the original failure. */ }
      res.write(`${JSON.stringify({
        type: 'coaching.failed',
        requestId: parsed.data.requestId,
        sequence: lastSequence + 1,
        code,
        retryable: false,
      })}\n`);
      return res.end();
    }
    if (error instanceof IdempotencyConflictError) {
      return res.status(409).json({ success: false, error: { code: error.code, message: 'Idempotency key conflicts with another request' } });
    }
    if (error instanceof AmbiguousPaidWorkError) {
      return res.status(409).json({ success: false, error: { code: error.code, message: 'Paid work requires explicit reconciliation' } });
    }
    return res.status(503).json({ success: false, error: { code: 'COACHING_STREAM_FAILED', message: 'Unable to stream coaching' } });
  }
});

router.get('/requests/:requestId', (req, res) => {
  const result = (options.idempotencyStore ?? getDefaultIdempotencyStore())
    .reconcile(req.params.requestId);
  if (result.status === 'missing') {
    return res.status(404).json({ success: false, error: { code: 'REQUEST_NOT_FOUND', message: 'Coaching request not found' } });
  }
  return res.json({ success: true, data: result });
});

return router;
}

export default createCoachingRouter();
