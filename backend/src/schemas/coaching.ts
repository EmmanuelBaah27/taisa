import { z } from 'zod';
import { COACHING_GATEWAY_LIMITS, type CoachingRequest } from '@taisa/shared';

const IdSchema = z.string().trim().min(1).max(COACHING_GATEWAY_LIMITS.maxIdLength);
const UuidSchema = z.string().regex(
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
);
const TimestampSchema = z
  .string()
  .max(COACHING_GATEWAY_LIMITS.maxTimestampLength)
  .datetime();
const StatementSchema = z
  .string()
  .trim()
  .min(1)
  .max(COACHING_GATEWAY_LIMITS.maxTextLength);
const IdListSchema = z.array(IdSchema).max(COACHING_GATEWAY_LIMITS.maxIdListLength);

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
  }).strict(),
  z.object({
    operation: z.literal('transition'),
    targetId: IdSchema,
    to: z.enum(['proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived']),
    reason: StatementSchema,
    requiresConfirmation: z.boolean(),
  }).strict(),
  z.object({
    operation: z.literal('support'),
    targetId: IdSchema,
    sourceMessageId: IdSchema,
    reason: StatementSchema,
    requiresConfirmation: z.literal(false),
  }).strict(),
]);

const NullableTextSchema = StatementSchema.nullable();
const PrioritySchema = z.enum(['low', 'medium', 'high']).nullable();
const OutcomeDeltaSchema = z.object({
  operation: z.literal('propose-outcome'),
  candidate: z.discriminatedUnion('kind', [
    z.object({ kind: z.literal('goal'), title: StatementSchema, description: NullableTextSchema,
      priority: PrioritySchema, targetDate: TimestampSchema.nullable(), supersedesId: IdSchema.nullable() }).strict(),
    z.object({ kind: z.literal('action'), title: StatementSchema, description: NullableTextSchema,
      priority: PrioritySchema, dueAt: TimestampSchema.nullable(), goalId: IdSchema.nullable(),
      supersedesId: IdSchema.nullable() }).strict(),
    z.object({ kind: z.literal('evidence'), statement: StatementSchema, occurredAt: TimestampSchema,
      goalIds: IdListSchema, actionIds: IdListSchema }).strict(),
  ]),
  reason: StatementSchema,
  requiresConfirmation: z.literal(true),
}).strict();

const CoachingRequestRuntimeSchema = z.object({
  requestId: UuidSchema,
  submittedAt: TimestampSchema,
  input: z.string().trim().min(1).max(COACHING_GATEWAY_LIMITS.maxTextLength),
  context: z.object({
    profile: z
      .object({
        currentRole: z
          .string()
          .trim()
          .min(1)
          .max(COACHING_GATEWAY_LIMITS.maxProfileFieldLength),
        currentCompany: z
          .string()
          .trim()
          .min(1)
          .max(COACHING_GATEWAY_LIMITS.maxProfileFieldLength)
          .nullable(),
        careerStage: z.enum(['early', 'mid', 'senior', 'executive', 'founder']),
        coachingStyle: z.enum(['direct', 'supportive', 'socratic', 'structured']),
        accountabilityLevel: z.enum(['gentle', 'moderate', 'intense']),
        currentFocusArea: z.string().trim().max(COACHING_GATEWAY_LIMITS.maxProfileFieldLength),
        shortTermGoal: z.string().trim().max(COACHING_GATEWAY_LIMITS.maxProfileFieldLength),
        longTermGoal: z.string().trim().max(COACHING_GATEWAY_LIMITS.maxProfileFieldLength),
      })
      .strict()
      .nullable(),
    recentMessages: z
      .array(
        z
          .object({
            role: z.enum(['user', 'assistant']),
            content: z.string().max(COACHING_GATEWAY_LIMITS.maxTextLength),
          })
          .strict(),
      )
      .max(COACHING_GATEWAY_LIMITS.maxRecentMessages),
    memory: z.array(MemoryItemSchema).max(COACHING_GATEWAY_LIMITS.maxMemoryItems),
    evidence: z.array(EvidenceItemSchema).max(COACHING_GATEWAY_LIMITS.maxEvidenceItems),
  }).strict(),
}).strict();

// Zod's inferred keys become optional while this backend compiles without strictNullChecks.
// The explicit output type reflects the runtime-required, strict schema above.
export const CoachingRequestSchema = CoachingRequestRuntimeSchema as z.ZodType<CoachingRequest>;

export const CoachingResponsePayloadSchema = z.object({
  reply: StatementSchema,
  stance: z.enum(['mirror', 'nudge', 'challenge', 'direct']),
  proposals: z.array(z.union([MemoryDeltaSchema, OutcomeDeltaSchema])).max(COACHING_GATEWAY_LIMITS.maxProposals),
}).strict();

export type CoachingResponsePayload = z.infer<typeof CoachingResponsePayloadSchema>;
