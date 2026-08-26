import type { OrganizationRequest, OrganizationResponse } from '@taisa/shared';
import { z } from 'zod';

const Id = z.string().trim().min(1).max(128);
const Revision = z.number().int().positive();

const RecordSchema = z.object({
  id: Id,
  kind: z.enum(['task', 'followup', 'blocker', 'decision', 'outcome']),
  title: z.string().trim().min(1).max(500),
  status: z.enum(['open', 'in_progress', 'blocked', 'resolved', 'completed', 'cancelled']),
  revision: Revision,
  projectId: Id.nullable(),
}).strict();

const ConversationSchema = z.object({
  id: Id,
  summary: z.string().trim().min(1).max(2_000),
  revision: Revision,
}).strict();

export const OrganizationRequestSchema = z.object({
  requestId: z.string().uuid(),
  submittedAt: z.string().datetime(),
  scope: z.enum(['conversation_task', 'week']),
  records: z.array(RecordSchema).max(30),
  conversations: z.array(ConversationSchema).max(30),
}).strict().superRefine((value, context) => {
  if (value.scope === 'conversation_task' && value.conversations.length > 20) {
    context.addIssue({
      code: z.ZodIssueCode.too_big,
      type: 'array',
      maximum: 20,
      inclusive: true,
      path: ['conversations'],
      message: 'Task organization accepts at most 20 conversations',
    });
  }
}) as z.ZodType<OrganizationRequest>;

const ProposalCommon = {
  id: Id,
  sourceId: Id,
  sourceRevision: Revision,
  evidenceIds: z.array(Id).min(1).max(30),
  evidenceFingerprint: Id,
  reasoning: z.string().trim().min(1).max(2_000),
  ambiguity: z.enum(['strong', 'ambiguous']),
  admission: z.enum(['pending', 'admitted', 'suppressed']),
  resolution: z.enum(['unapplied', 'accepted', 'rejected', 'expired']),
  revalidation: z.enum(['valid', 'stale', 'conflicted']),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
} as const;

function proposalSchema<T extends string, E extends z.ZodTypeAny>(type: T, effect: E) {
  return z.object({ ...ProposalCommon, type: z.literal(type), effect }).strict();
}

const ProposalSchema = z.discriminatedUnion('type', [
  proposalSchema('project_association', z.object({ recordId: Id, projectId: Id }).strict()),
  proposalSchema('task_conversation_link', z.object({
    recordId: Id,
    conversationId: Id,
    contribution: z.enum(['planning', 'status', 'blocker', 'decision', 'outcome', 'evidence']),
  }).strict()),
  proposalSchema('task_completion', z.object({ recordId: Id }).strict()),
  proposalSchema('followup_status_update', z.object({
    recordId: Id, status: z.enum(['open', 'completed', 'cancelled']),
  }).strict()),
  proposalSchema('blocker_status_update', z.object({
    recordId: Id, status: z.enum(['open', 'resolved']),
  }).strict()),
  proposalSchema('project_status_update', z.object({
    projectId: Id, status: z.enum(['active', 'paused', 'completed', 'archived']),
  }).strict()),
  proposalSchema('work_record', z.object({
    kind: z.enum(['task', 'followup', 'blocker', 'decision', 'outcome']),
    title: z.string().trim().min(1).max(500),
    projectId: Id.nullable(),
  }).strict()),
  proposalSchema('insight', z.object({
    title: z.string().trim().min(1).max(500), body: z.string().trim().min(1).max(2_000),
  }).strict()),
  proposalSchema('growth_reflection', z.object({
    title: z.string().trim().min(1).max(500), body: z.string().trim().min(1).max(2_000),
  }).strict()),
  proposalSchema('experiment', z.object({
    title: z.string().trim().min(1).max(500), hypothesis: z.string().trim().min(1).max(2_000),
  }).strict()),
]);

export const OrganizationResponseSchema = z.object({
  requestId: z.string().uuid(),
  proposals: z.array(ProposalSchema).max(30),
}).strict() as unknown as z.ZodType<OrganizationResponse>;
