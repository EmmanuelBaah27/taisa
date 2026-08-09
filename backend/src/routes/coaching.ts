import { Router } from 'express';
import { CoachingRequestSchema } from '../schemas/coaching';
import { requestCoaching } from '../services/coaching/coachingGateway';
import {
  CostConfigurationError,
  CostLimitError,
  readCostCeilings,
  recordUsage,
  reserveCost,
} from '../services/usage/costLedger';

const router = Router();

router.post('/respond', async (req, res) => {
  const parsed = CoachingRequestSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({
      success: false,
      error: { code: 'VALIDATION_ERROR', message: parsed.error.message },
    });
  }

  let reservation: ReturnType<typeof reserveCost> | undefined;
  try {
    const ceilings = readCostCeilings();
    reservation = reserveCost(ceilings.perRequestUsd, ceilings);
    const response = await requestCoaching(parsed.data);
    reservation.release();
    recordUsage(response.usage);
    return res.json({ success: true, data: response });
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
      error: { code: 'COACHING_FAILED', message: 'Unable to complete the coaching request' },
    });
  } finally {
    reservation?.release();
  }
});

export default router;
