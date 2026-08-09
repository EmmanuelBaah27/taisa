import { z } from 'zod';

export const MemoryItemSchema = z.object({
  id: z.string(),
  type: z.enum([
    'goal',
    'commitment',
    'decision',
    'preference',
    'career_context',
    'development_area',
    'evidence',
    'pattern',
  ]),
  statement: z.string(),
  provenance: z.enum(['user-stated', 'user-confirmed', 'ai-inferred', 'system-observed']),
  lifecycle: z.enum(['proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived']),
  confidence: z.enum(['tentative', 'supported', 'established']),
  createdAt: z.string().datetime(),
  confirmedAt: z.string().datetime().nullable(),
  lastSupportedAt: z.string().datetime(),
  statusChangedAt: z.string().datetime(),
  sourceMessageIds: z.array(z.string()),
  supersedesId: z.string().nullable().optional(),
});

export const EvidenceItemSchema = z.object({
  id: z.string(),
  statement: z.string(),
  occurredAt: z.string().datetime(),
  sourceMessageIds: z.array(z.string()),
  goalIds: z.array(z.string()),
  actionIds: z.array(z.string()),
});

const MemoryCandidateSchema = MemoryItemSchema.omit({
  id: true,
  createdAt: true,
  confirmedAt: true,
  lastSupportedAt: true,
  statusChangedAt: true,
});

export const MemoryDeltaSchema = z.discriminatedUnion('operation', [
  z.object({
    operation: z.literal('propose'),
    candidate: MemoryCandidateSchema,
    reason: z.string(),
    requiresConfirmation: z.boolean(),
  }),
  z.object({
    operation: z.literal('transition'),
    targetId: z.string(),
    to: z.enum(['proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived']),
    reason: z.string(),
    requiresConfirmation: z.boolean(),
  }),
  z.object({
    operation: z.literal('support'),
    targetId: z.string(),
    sourceMessageId: z.string(),
    reason: z.string(),
    requiresConfirmation: z.literal(false),
  }),
]);

export const CoachingRequestSchema = z.object({
  requestId: z.string().uuid(),
  submittedAt: z.string().datetime(),
  input: z.string().trim().min(1).max(4000),
  context: z.object({
    profile: z.record(z.unknown()).nullable(),
    recentMessages: z
      .array(z.object({ role: z.enum(['user', 'assistant']), content: z.string().max(4000) }))
      .max(20),
    memory: z.array(MemoryItemSchema).max(50),
    evidence: z.array(EvidenceItemSchema).max(8),
  }),
});

export const CoachingResponsePayloadSchema = z.object({
  reply: z.string().trim().min(1).max(4000),
  stance: z.enum(['mirror', 'nudge', 'challenge', 'direct']),
  proposals: z.array(MemoryDeltaSchema),
});

export type CoachingResponsePayload = z.infer<typeof CoachingResponsePayloadSchema>;
