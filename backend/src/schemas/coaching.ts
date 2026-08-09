import { z } from 'zod';
import type { CoachingRequest } from '@taisa/shared';

const MAX_ID_LENGTH = 128;
const MAX_TEXT_LENGTH = 4000;
const MAX_PROFILE_FIELD_LENGTH = 200;
const MAX_ID_LIST_LENGTH = 50;

const IdSchema = z.string().trim().min(1).max(MAX_ID_LENGTH);
const TimestampSchema = z.string().max(40).datetime();
const StatementSchema = z.string().trim().min(1).max(MAX_TEXT_LENGTH);
const IdListSchema = z.array(IdSchema).max(MAX_ID_LIST_LENGTH);

export const MemoryItemSchema = z.object({
  id: IdSchema,
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
  statement: StatementSchema,
  provenance: z.enum(['user-stated', 'user-confirmed', 'ai-inferred', 'system-observed']),
  lifecycle: z.enum(['proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived']),
  confidence: z.enum(['tentative', 'supported', 'established']),
  createdAt: TimestampSchema,
  confirmedAt: TimestampSchema.nullable(),
  lastSupportedAt: TimestampSchema,
  statusChangedAt: TimestampSchema,
  sourceMessageIds: IdListSchema,
  supersedesId: IdSchema.nullable().optional(),
}).strict();

export const EvidenceItemSchema = z.object({
  id: IdSchema,
  statement: StatementSchema,
  occurredAt: TimestampSchema,
  sourceMessageIds: IdListSchema,
  goalIds: IdListSchema,
  actionIds: IdListSchema,
}).strict();

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
    reason: StatementSchema,
    requiresConfirmation: z.boolean(),
  }),
  z.object({
    operation: z.literal('transition'),
    targetId: IdSchema,
    to: z.enum(['proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived']),
    reason: StatementSchema,
    requiresConfirmation: z.boolean(),
  }),
  z.object({
    operation: z.literal('support'),
    targetId: IdSchema,
    sourceMessageId: IdSchema,
    reason: StatementSchema,
    requiresConfirmation: z.literal(false),
  }),
]);

const CoachingRequestRuntimeSchema = z.object({
  requestId: z.string().uuid(),
  submittedAt: TimestampSchema,
  input: z.string().trim().min(1).max(MAX_TEXT_LENGTH),
  context: z.object({
    profile: z
      .object({
        currentRole: z.string().trim().min(1).max(MAX_PROFILE_FIELD_LENGTH),
        currentCompany: z.string().trim().min(1).max(MAX_PROFILE_FIELD_LENGTH).nullable(),
        careerStage: z.enum(['early', 'mid', 'senior', 'executive', 'founder']),
        coachingStyle: z.enum(['direct', 'supportive', 'socratic', 'structured']),
        accountabilityLevel: z.enum(['gentle', 'moderate', 'intense']),
      })
      .strict()
      .nullable(),
    recentMessages: z
      .array(
        z
          .object({
            role: z.enum(['user', 'assistant']),
            content: z.string().max(MAX_TEXT_LENGTH),
          })
          .strict(),
      )
      .max(20),
    memory: z.array(MemoryItemSchema).max(50),
    evidence: z.array(EvidenceItemSchema).max(8),
  }).strict(),
}).strict();

// Zod's inferred keys become optional while this backend compiles without strictNullChecks.
// The explicit output type reflects the runtime-required, strict schema above.
export const CoachingRequestSchema = CoachingRequestRuntimeSchema as z.ZodType<CoachingRequest>;

export const CoachingResponsePayloadSchema = z.object({
  reply: z.string().trim().min(1).max(4000),
  stance: z.enum(['mirror', 'nudge', 'challenge', 'direct']),
  proposals: z.array(MemoryDeltaSchema),
});

export type CoachingResponsePayload = z.infer<typeof CoachingResponsePayloadSchema>;
