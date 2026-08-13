import { Router } from 'express';
import { z } from 'zod';
import type { FeedbackRepository } from '../feedback/feedbackRepository';

const FeedbackSchema = z.object({
  idempotencyId: z.string().min(1).max(128),
  consentedAt: z.string().datetime(),
  example: z.object({
    requestId: z.string().min(1).max(128),
    kind: z.enum(['text', 'voice']),
    stance: z.enum(['mirror', 'nudge', 'challenge', 'direct']).nullable(),
    reaction: z.enum(['helpful', 'unhelpful']),
    note: z.string().max(1000).nullable(),
    userTurn: z.string().min(1).max(20_000),
    assistantReply: z.string().min(1).max(20_000),
    contextManifest: z.record(z.unknown()),
    usedContext: z.array(z.string().min(1).max(2000)).max(50),
  }).strict(),
}).strict();

const SAFE_RECEIPT = /^[0-9a-f-]{36}$/i;

export function createFeedbackRouter(repository: FeedbackRepository) {
  const router = Router();
  router.post('/', (request, response) => {
    const ownerCredentialId = response.locals.deviceCredentialId;
    if (typeof ownerCredentialId !== 'string') return response.status(401).json({
      success: false,
      error: { code: 'DEVICE_AUTHENTICATION_REQUIRED', message: 'Device authentication required' },
    });
    let serializedLength = Number.POSITIVE_INFINITY;
    try {
      serializedLength = JSON.stringify(request.body).length;
    } catch {
      // Invalid payloads are handled by the same content-free boundary below.
    }
    const parsed = serializedLength <= 50_000
      ? FeedbackSchema.safeParse(request.body)
      : { success: false as const };
    if (!parsed.success) return response.status(400).json({
      success: false,
      error: { code: 'INVALID_FEEDBACK_EXAMPLE', message: 'Feedback example is invalid' },
    });
    try {
      const receiptId = repository.store({
        ownerCredentialId,
        idempotencyId: parsed.data.idempotencyId!,
        consentedAt: parsed.data.consentedAt!,
        example: parsed.data.example!,
      });
      return response.status(201).json({ success: true, data: { receiptId } });
    } catch {
      return response.status(409).json({
        success: false,
        error: { code: 'FEEDBACK_CONFLICT', message: 'Feedback example conflicts with an earlier attempt' },
      });
    }
  });
  router.delete('/:receiptId', (request, response) => {
    const ownerCredentialId = response.locals.deviceCredentialId;
    if (typeof ownerCredentialId !== 'string') return response.status(401).end();
    if (!SAFE_RECEIPT.test(request.params.receiptId)) return response.status(404).end();
    repository.delete(ownerCredentialId, request.params.receiptId);
    return response.status(204).end();
  });
  return router;
}
