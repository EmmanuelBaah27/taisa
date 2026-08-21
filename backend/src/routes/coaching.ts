import { Router } from 'express';
import { CoachingRequestSchema } from '../schemas/coaching';
import {
  estimateConfiguredCoachingAttempts,
  requestCoaching,
} from '../services/coaching/coachingGateway';
import { ContentFreeFallbackError } from '../services/coaching/fallbackProvider';
import {
  CostConfigurationError,
  CostLimitError,
  readCostCeilings,
  reserveAttempts,
} from '../services/usage/costLedger';

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

export default router;
