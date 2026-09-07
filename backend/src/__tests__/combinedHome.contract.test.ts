import type {
  CapabilityState,
  PermittedOperation,
  ProposalEnvelope,
  WorkRecord,
} from '@taisa/shared';

test('combined Home contracts keep lifecycle dimensions independent', () => {
  const record: WorkRecord = {
    id: 'task-1',
    kind: 'task',
    title: 'Send proposal',
    projectId: null,
    status: 'open',
    freshness: 'current',
    plannedWeek: '2026-08-24',
    plannedDay: null,
    sourceId: 'conversation-1',
    revision: 1,
    createdAt: '2026-08-25T08:00:00Z',
    updatedAt: '2026-08-25T08:00:00Z',
    lastConfirmedAt: '2026-08-25T08:00:00Z',
  };
  const operation: PermittedOperation = 'complete_explicit_task';
  const state: CapabilityState = 'learning';

  expect({ record, operation, state }).toBeDefined();
});

test('proposal envelope carries review, evidence, and revision state', () => {
  const proposal: ProposalEnvelope<'project_association'> = {
    id: 'proposal-1',
    type: 'project_association',
    sourceId: 'conversation-1',
    sourceRevision: 3,
    evidenceIds: ['evidence-1'],
    evidenceFingerprint: 'fp-1',
    reasoning: 'The user named the existing Website Launch project.',
    effect: { recordId: 'task-1', projectId: 'project-1' },
    ambiguity: 'strong',
    admission: 'pending',
    resolution: 'unapplied',
    revalidation: 'valid',
    createdAt: '2026-08-25T08:00:00Z',
    updatedAt: '2026-08-25T08:00:00Z',
  };

  expect(proposal.resolution).toBe('unapplied');
});
