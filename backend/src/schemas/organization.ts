import type { OrganizationRequest, OrganizationResponse } from '@taisa/shared';
import { z } from 'zod';

const Id = z.string().trim().min(1).max(128);
const Revision = z.number().int().positive();

const RecordSchema = z.object({
  id: Id,
  kind: z.enum(['task', 'followup', 'blocker', 'decision']),
  title: z.string().trim().min(1).max(500),
  status: z.enum(['open', 'completed', 'removed', 'waiting', 'rescheduled', 'cancelled',
    'active', 'being_resolved', 'resolved', 'no_longer_relevant', 'current', 'reopened',
    'superseded', 'reversed']),
  revision: Revision,
  projectId: Id.nullable(),
  plannedWeek: z.string().date().nullable(),
}).strict();

const ConversationSchema = z.object({
  id: Id,
  summary: z.string().trim().min(1).max(2_000),
  revision: Revision,
}).strict();

function isMondaySunday(period: { startsOn?: string; endsOn?: string } | null) {
  if (period === null || period.startsOn === undefined || period.endsOn === undefined) return false;
  const start = new Date(`${period.startsOn}T00:00:00Z`);
  const end = new Date(`${period.endsOn}T00:00:00Z`);
  return start.getUTCDay() === 1 && end.getTime() - start.getTime() === 6 * 86_400_000;
}

export const OrganizationRequestSchema = z.object({
  requestId: z.string().uuid(),
  submittedAt: z.string().datetime(),
  scope: z.enum(['conversation', 'task', 'week']),
  scopeId: Id.nullable(),
  period: z.object({ startsOn: z.string().date(), endsOn: z.string().date() }).strict().nullable(),
  records: z.array(RecordSchema).max(30),
  conversations: z.array(ConversationSchema).max(30),
}).strict().superRefine((value, context) => {
  if (value.scope === 'conversation' && (
    value.scopeId === null || value.conversations.length !== 1
    || value.conversations[0]?.id !== value.scopeId
    || value.period !== null
    || value.records.some((record) => record.kind !== 'task' || record.status !== 'open')
  )) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['scopeId'], message: 'Conversation scope must contain exactly its selected conversation' });
  }
  if (value.scope === 'task' && (
    value.scopeId === null || value.records.length !== 1 || value.records[0]?.id !== value.scopeId
    || value.records[0]?.kind !== 'task' || value.records[0]?.status !== 'open'
    || !isMondaySunday(value.period) || value.records[0]?.plannedWeek !== value.period?.startsOn
  )) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['scopeId'], message: 'Task scope must contain exactly its selected task' });
  }
  if (value.scope === 'task' && value.conversations.length > 20) {
    context.addIssue({
      code: z.ZodIssueCode.too_big,
      type: 'array',
      maximum: 20,
      inclusive: true,
      path: ['conversations'],
      message: 'Task organization accepts at most 20 conversations',
    });
  }
  if (value.scope === 'week' && (
    value.scopeId !== null || !isMondaySunday(value.period)
    || value.records.some((record) => record.kind !== 'task' || record.status !== 'open'
      || record.plannedWeek !== value.period?.startsOn)
  )) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['scopeId'], message: 'Week scope has no selected entity' });
  }
}) as z.ZodType<OrganizationRequest>;

const ProposalCommon = {
  id: Id,
  sourceId: Id,
  sourceRevision: Revision,
  evidenceIds: z.array(Id).min(1).max(30),
  reasoning: z.string().trim().min(1).max(2_000),
  ambiguity: z.enum(['strong', 'ambiguous']),
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
    recordId: Id, status: z.enum(['waiting', 'completed', 'rescheduled', 'cancelled']),
  }).strict()),
  proposalSchema('blocker_status_update', z.object({
    recordId: Id, status: z.enum(['active', 'being_resolved', 'resolved', 'no_longer_relevant']),
  }).strict()),
  proposalSchema('project_status_update', z.object({
    projectId: Id, status: z.enum(['active', 'archived']),
  }).strict()),
  proposalSchema('work_record', z.object({
    kind: z.enum(['task', 'followup', 'blocker', 'decision']),
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
