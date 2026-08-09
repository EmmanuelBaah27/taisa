import { Router } from 'express';
import type { CoachingRequest } from '@taisa/shared';
import { CoachingRequestSchema } from '../schemas/coaching';
import { requestCoaching } from '../services/coaching/coachingGateway';

const router = Router();

router.post('/respond', async (req, res) => {
  const parsed = CoachingRequestSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({
      success: false,
      error: { code: 'VALIDATION_ERROR', message: parsed.error.message },
    });
  }

  try {
    const response = await requestCoaching(parsed.data as CoachingRequest);
    return res.json({ success: true, data: response });
  } catch (error: any) {
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
  }
});

export default router;
