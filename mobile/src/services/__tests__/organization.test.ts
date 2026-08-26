import type { OrganizationRequest } from '@taisa/shared';

import { admitOrganizationResponse, createOrganizationClient, executeEligibleStrongLinks } from '../organization';
import { createTestDatabase } from '../../repositories/__tests__/testDatabase';
import { createWorkRepository } from '../../repositories/workRepository';
import { createReadinessRepository } from '../../repositories/readinessRepository';
import { insertConversation } from '../../repositories/conversationRepository';

const organizationRequest: OrganizationRequest = {
  requestId: '11111111-1111-4111-8111-111111111111',
  submittedAt: '2026-08-26T08:00:00Z',
  scope: 'week',
  scopeId: null,
  records: [{
    id: 'task-1', kind: 'task', title: 'Send proposal', status: 'open',
    revision: 1, projectId: null,
  }],
  conversations: [{ id: 'conversation-1', summary: 'Planned the proposal', revision: 2 }],
};

test('cancelled preview sends nothing', async () => {
  const http = { post: jest.fn() };
  const submit = createOrganizationClient(http);

  await expect(submit({ request: organizationRequest, approved: false }))
    .resolves.toEqual({ kind: 'cancelled' });
  expect(http.post).not.toHaveBeenCalled();
});

test('approved preview sends exactly the bounded request once', async () => {
  const http = {
    post: jest.fn().mockResolvedValue({
      data: { success: true, data: { requestId: organizationRequest.requestId, proposals: [] } },
    }),
  };
  const submit = createOrganizationClient(http);

  await expect(submit({ request: organizationRequest, approved: true })).resolves.toEqual({
    kind: 'received', response: { requestId: organizationRequest.requestId, proposals: [] },
  });
  expect(http.post).toHaveBeenCalledTimes(1);
  expect(http.post).toHaveBeenCalledWith('/organization/analyze', organizationRequest, {
    headers: { 'x-request-id': organizationRequest.requestId },
  });
});

test('mismatched response request ID is rejected without local mutation', async () => {
  const http = {
    post: jest.fn().mockResolvedValue({
      data: { success: true, data: { requestId: '22222222-2222-4222-8222-222222222222', proposals: [] } },
    }),
  };
  const submit = createOrganizationClient(http);

  await expect(submit({ request: organizationRequest, approved: true }))
    .rejects.toMatchObject({ code: 'INVALID_ORGANIZATION_RESPONSE' });
});

test('local admission owns lifecycle and excludes stale source revisions', async () => {
  const database = createTestDatabase();
  const candidate = {
    id: 'candidate-1', type: 'task_completion' as const, sourceId: 'conversation-1',
    sourceRevision: 2, evidenceIds: ['conversation-1'], reasoning: 'Explicit completion',
    ambiguity: 'strong' as const, effect: { recordId: 'task-1' },
  };

  await expect(admitOrganizationResponse(database, organizationRequest, {
    requestId: organizationRequest.requestId,
    proposals: [candidate, { ...candidate, id: 'candidate-stale', sourceRevision: 1 }],
  })).resolves.toEqual([expect.objectContaining({
    id: 'candidate-1', admission: 'admitted', resolution: 'unapplied', revalidation: 'valid',
  })]);
  await expect(database.getFirstAsync<{ count: number }>(
    'SELECT COUNT(*) AS count FROM proposals',
  )).resolves.toEqual({ count: 1 });
  database.close();
});

test('strong organization link executes only through its exact delegated capability', async () => {
  const database = createTestDatabase();
  await database.withTransaction(async (transaction) => {
    await insertConversation(transaction, {
      id: 'conversation-1', title: 'Plan', lifecycle: 'active', preferredInputMode: 'text',
      createdAt: organizationRequest.submittedAt, updatedAt: organizationRequest.submittedAt,
      archivedAt: null,
    }, 'seed-conversation');
    await createWorkRepository(database).insert(transaction, {
      id: 'task-1', kind: 'task', title: 'Send proposal', projectId: null, status: 'open',
      freshness: 'current', plannedWeek: '2026-08-24', plannedDay: null,
      sourceId: 'conversation-1', revision: 1, createdAt: organizationRequest.submittedAt,
      updatedAt: organizationRequest.submittedAt, lastConfirmedAt: organizationRequest.submittedAt,
    }, 'seed-task');
    await createReadinessRepository(database).put(transaction, {
      operation: 'apply_strong_task_conversation_link', policyVersion: 1, state: 'trusted',
      permissionGrantedAt: organizationRequest.submittedAt, relevantExamples: 8,
      corrections: 0, contradictions: 0, latestEvidenceAt: organizationRequest.submittedAt,
      cleanTrialOutcomes: 5, updatedAt: organizationRequest.submittedAt,
    });
  });
  const candidate = {
    id: 'candidate-link', type: 'task_conversation_link' as const, sourceId: 'conversation-1',
    sourceRevision: 2, evidenceIds: ['conversation-1'], reasoning: 'Strong planning link',
    ambiguity: 'strong' as const,
    effect: { recordId: 'task-1', conversationId: 'conversation-1', contribution: 'planning' as const },
  };
  const admitted = await admitOrganizationResponse(database, organizationRequest, {
    requestId: organizationRequest.requestId, proposals: [candidate],
  });

  await expect(executeEligibleStrongLinks(database, admitted, organizationRequest.submittedAt))
    .resolves.toEqual([]);
  await expect(database.getFirstAsync<{ resolution: string }>(
    'SELECT resolution FROM proposals WHERE id = $id', { $id: candidate.id },
  )).resolves.toEqual({ resolution: 'accepted' });
  await expect(database.getFirstAsync<{ count: number }>(
    'SELECT COUNT(*) AS count FROM work_relationships',
  )).resolves.toEqual({ count: 1 });
  database.close();
});
