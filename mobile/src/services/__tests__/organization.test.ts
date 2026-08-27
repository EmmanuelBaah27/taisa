import type { OrganizationRequest } from '@taisa/shared';

import {
  admitOrganizationResponse, assembleOrganizationRequest, createOrganizationClient,
  executeEligibleStrongLinks,
} from '../organization';
import { createTestDatabase } from '../../repositories/__tests__/testDatabase';
import { createWorkRepository } from '../../repositories/workRepository';
import { createReadinessRepository } from '../../repositories/readinessRepository';
import { insertConversation } from '../../repositories/conversationRepository';
import { createHomeOperationService } from '../homeOperations';

const organizationRequest: OrganizationRequest = {
  requestId: '11111111-1111-4111-8111-111111111111',
  submittedAt: '2026-08-26T08:00:00Z',
  scope: 'week',
  scopeId: null,
  records: [{
    id: 'task-1', kind: 'task', title: 'Send proposal', status: 'open',
    revision: 1, projectId: null, plannedWeek: '2026-08-24',
  }],
  conversations: [{ id: 'conversation-1', summary: 'Planned the proposal', revision: 1 }],
  period: { startsOn: '2026-08-24', endsOn: '2026-08-30' },
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
  await database.withTransaction(async (transaction) => {
    await insertConversation(transaction, {
      id: 'conversation-1', title: 'Plan', lifecycle: 'active', preferredInputMode: 'text',
      createdAt: organizationRequest.submittedAt, updatedAt: organizationRequest.submittedAt,
      archivedAt: null,
    }, 'seed-admission-conversation');
    await createWorkRepository(database).insert(transaction, {
      id: 'task-1', kind: 'task', title: 'Send proposal', projectId: null, status: 'open',
      freshness: 'current', plannedWeek: '2026-08-24', plannedDay: null,
      sourceId: 'conversation-1', revision: 1, createdAt: organizationRequest.submittedAt,
      updatedAt: organizationRequest.submittedAt, lastConfirmedAt: organizationRequest.submittedAt,
    }, 'seed-admission-task');
  });
  const candidate = {
    id: 'candidate-1', type: 'task_completion' as const, sourceId: 'conversation-1',
    sourceRevision: 1, evidenceIds: ['conversation-1'], reasoning: 'Explicit completion',
    ambiguity: 'strong' as const, effect: { recordId: 'task-1' },
  };

  await expect(admitOrganizationResponse(database, organizationRequest, {
    requestId: organizationRequest.requestId,
    proposals: [candidate, { ...candidate, id: 'candidate-stale', sourceRevision: 2 }],
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
    sourceRevision: 1, evidenceIds: ['conversation-1'], reasoning: 'Strong planning link',
    ambiguity: 'strong' as const,
    effect: { recordId: 'task-1', conversationId: 'conversation-1', contribution: 'planning' as const },
  };
  const admitted = await admitOrganizationResponse(database, organizationRequest, {
    requestId: organizationRequest.requestId, proposals: [candidate],
  });

  await expect(executeEligibleStrongLinks(
    database, admitted, organizationRequest.submittedAt, organizationRequest,
  ))
    .resolves.toEqual([]);
  await expect(database.getFirstAsync<{ resolution: string }>(
    'SELECT resolution FROM proposals WHERE id = $id', { $id: candidate.id },
  )).resolves.toEqual({ resolution: 'accepted' });
  await expect(database.getFirstAsync<{ count: number }>(
    'SELECT COUNT(*) AS count FROM work_relationships',
  )).resolves.toEqual({ count: 1 });
  database.close();
});

test('admission rejects a candidate when its affected task changed after preview', async () => {
  const database = createTestDatabase();
  await database.withTransaction(async (transaction) => {
    await insertConversation(transaction, {
      id: 'conversation-1', title: 'Plan', lifecycle: 'active', preferredInputMode: 'text',
      createdAt: organizationRequest.submittedAt, updatedAt: organizationRequest.submittedAt,
      archivedAt: null,
    }, 'seed-stale-conversation');
    await createWorkRepository(database).insert(transaction, {
      id: 'task-1', kind: 'task', title: 'Changed after preview', projectId: null, status: 'open',
      freshness: 'current', plannedWeek: '2026-08-24', plannedDay: null,
      sourceId: 'conversation-1', revision: 2, createdAt: organizationRequest.submittedAt,
      updatedAt: organizationRequest.submittedAt, lastConfirmedAt: organizationRequest.submittedAt,
    }, 'seed-stale-task');
  });
  const candidate = {
    id: 'candidate-stale-task', type: 'task_conversation_link' as const,
    sourceId: 'conversation-1', sourceRevision: 1,
    evidenceIds: ['conversation-1', 'task-1'], reasoning: 'Planning link',
    ambiguity: 'strong' as const,
    effect: { recordId: 'task-1', conversationId: 'conversation-1', contribution: 'planning' as const },
  };

  await expect(admitOrganizationResponse(database, organizationRequest, {
    requestId: organizationRequest.requestId, proposals: [candidate],
  })).resolves.toEqual([]);
  database.close();
});

test('week scope is assembled only from open tasks and submitted conversations in its period', async () => {
  const database = createTestDatabase();
  await database.withTransaction(async (transaction) => {
    for (const [id, week, status] of [
      ['in-week', '2026-08-24', 'open'], ['completed', '2026-08-24', 'completed'],
      ['other-week', '2026-08-17', 'open'],
    ] as const) {
      await createWorkRepository(database).insert(transaction, {
        id, kind: 'task', title: id, projectId: null, status,
        freshness: 'current', plannedWeek: week, plannedDay: null, sourceId: 'manual', revision: 1,
        createdAt: organizationRequest.submittedAt, updatedAt: organizationRequest.submittedAt,
        lastConfirmedAt: organizationRequest.submittedAt,
      }, `seed-${id}`);
    }
    for (const id of ['in-period', 'outside-period']) {
      await insertConversation(transaction, {
        id, title: id, lifecycle: 'active', preferredInputMode: 'text',
        createdAt: organizationRequest.submittedAt, updatedAt: organizationRequest.submittedAt,
        archivedAt: null,
      }, `seed-${id}`);
      await transaction.runAsync(
        `INSERT INTO messages
          (id, conversation_id, role, content, lifecycle, created_at, updated_at)
         VALUES ($messageId, $conversationId, 'user', $content, 'submitted', $createdAt, $createdAt)`,
        { $messageId: `message-${id}`, $conversationId: id, $content: id,
          $createdAt: id === 'in-period' ? '2026-08-26T08:00:00Z' : '2026-08-20T08:00:00Z' },
      );
    }
  });

  await expect(assembleOrganizationRequest(database, {
    requestId: organizationRequest.requestId, submittedAt: organizationRequest.submittedAt,
    scope: 'week', scopeId: null, period: { startsOn: '2026-08-24', endsOn: '2026-08-30' },
  })).resolves.toMatchObject({
    records: [{ id: 'in-week' }], conversations: [{ id: 'in-period' }],
  });
  database.close();
});

test('strong link is not applied when its conversation changes after admission', async () => {
  const database = createTestDatabase();
  await database.withTransaction(async (transaction) => {
    await insertConversation(transaction, {
      id: 'conversation-1', title: 'Plan', lifecycle: 'active', preferredInputMode: 'text',
      createdAt: organizationRequest.submittedAt, updatedAt: organizationRequest.submittedAt,
      archivedAt: null,
    }, 'seed-racing-conversation');
    await createWorkRepository(database).insert(transaction, {
      id: 'task-1', kind: 'task', title: 'Send proposal', projectId: null, status: 'open',
      freshness: 'current', plannedWeek: '2026-08-24', plannedDay: null,
      sourceId: 'conversation-1', revision: 1, createdAt: organizationRequest.submittedAt,
      updatedAt: organizationRequest.submittedAt, lastConfirmedAt: organizationRequest.submittedAt,
    }, 'seed-racing-task');
    await createReadinessRepository(database).put(transaction, {
      operation: 'apply_strong_task_conversation_link', policyVersion: 1, state: 'trusted',
      permissionGrantedAt: organizationRequest.submittedAt, relevantExamples: 8,
      corrections: 0, contradictions: 0, latestEvidenceAt: organizationRequest.submittedAt,
      cleanTrialOutcomes: 5, updatedAt: organizationRequest.submittedAt,
    });
  });
  const candidate = {
    id: 'candidate-race', type: 'task_conversation_link' as const, sourceId: 'conversation-1',
    sourceRevision: 1, evidenceIds: ['conversation-1', 'task-1'], reasoning: 'Planning link',
    ambiguity: 'strong' as const,
    effect: { recordId: 'task-1', conversationId: 'conversation-1', contribution: 'planning' as const },
  };
  const admitted = await admitOrganizationResponse(database, organizationRequest, {
    requestId: organizationRequest.requestId, proposals: [candidate],
  });
  await database.runAsync(
    `INSERT INTO messages
      (id, conversation_id, role, content, lifecycle, created_at, updated_at)
     VALUES ('late-message', 'conversation-1', 'user', 'Changed', 'submitted',
       '2026-08-26T08:01:00Z', '2026-08-26T08:01:00Z')`,
  );

  await expect(executeEligibleStrongLinks(
    database, admitted, organizationRequest.submittedAt, organizationRequest,
  )).resolves.toEqual(admitted);
  await expect(database.getFirstAsync<{ count: number }>(
    'SELECT COUNT(*) AS count FROM work_relationships',
  )).resolves.toEqual({ count: 0 });
  database.close();
});

test('operation transaction rejects a stale conversation revision', async () => {
  const database = createTestDatabase();
  await database.withTransaction(async (transaction) => {
    await insertConversation(transaction, {
      id: 'conversation-1', title: 'Plan', lifecycle: 'active', preferredInputMode: 'text',
      createdAt: organizationRequest.submittedAt, updatedAt: organizationRequest.submittedAt,
      archivedAt: null,
    }, 'seed-operation-conversation');
    await createWorkRepository(database).insert(transaction, {
      id: 'task-1', kind: 'task', title: 'Send proposal', projectId: null, status: 'open',
      freshness: 'current', plannedWeek: '2026-08-24', plannedDay: null,
      sourceId: 'conversation-1', revision: 1, createdAt: organizationRequest.submittedAt,
      updatedAt: organizationRequest.submittedAt, lastConfirmedAt: organizationRequest.submittedAt,
    }, 'seed-operation-task');
    await createReadinessRepository(database).put(transaction, {
      operation: 'apply_strong_task_conversation_link', policyVersion: 1, state: 'trusted',
      permissionGrantedAt: organizationRequest.submittedAt, relevantExamples: 8,
      corrections: 0, contradictions: 0, latestEvidenceAt: organizationRequest.submittedAt,
      cleanTrialOutcomes: 5, updatedAt: organizationRequest.submittedAt,
    });
    await transaction.runAsync(
      `INSERT INTO messages
        (id, conversation_id, role, content, lifecycle, created_at, updated_at)
       VALUES ('changed-message', 'conversation-1', 'user', 'Changed', 'submitted',
         '2026-08-26T08:01:00Z', '2026-08-26T08:01:00Z')`,
    );
  });

  await expect(createHomeOperationService(database).execute({
    id: 'stale-conversation-operation', operation: 'apply_strong_task_conversation_link',
    targetId: 'task-1', sourceId: 'conversation-1', expectedRevision: 1,
    ambiguity: 'strong', requestedAt: organizationRequest.submittedAt,
    payload: { conversationId: 'conversation-1', contribution: 'planning', expectedConversationRevision: 1 },
  })).rejects.toMatchObject({ code: 'REVISION_CONFLICT' });
  database.close();
});
