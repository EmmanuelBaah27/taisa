import type { OrganizationRequest, OrganizationResponse } from '@taisa/shared';
import { Router } from 'express';
import { z } from 'zod';

import { OrganizationRequestSchema, OrganizationResponseSchema } from '../schemas/organization';

export interface OrganizationAnalyzer {
  analyze(request: OrganizationRequest): Promise<OrganizationResponse>;
}

export function createOrganizationRouter(analyzer: OrganizationAnalyzer): Router {
  const router = Router();
  router.post('/analyze', async (request, response) => {
    const parsed = OrganizationRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return response.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: parsed.error.message },
      });
    }
    try {
      const result = OrganizationResponseSchema.parse(await analyzer.analyze(parsed.data));
      return response.json({ success: true, data: result });
    } catch (error) {
      if (
        error instanceof z.ZodError
        || (error as { code?: unknown } | null)?.code === 'INVALID_ORGANIZATION_OUTPUT'
      ) {
        return response.status(502).json({
          success: false,
          error: { code: 'INVALID_ORGANIZATION_OUTPUT', message: 'Invalid organization response' },
        });
      }
      return response.status(500).json({
        success: false,
        error: { code: 'ORGANIZATION_FAILED', message: 'Unable to analyze organization scope' },
      });
    }
  });
  return router;
}
