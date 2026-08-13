import type {
  LocalAction,
  LocalConversation,
  LocalEvidenceItem,
  LocalMemoryItem,
  LocalMessage,
} from '@taisa/shared';

import { getAction, insertAction } from '../../../repositories/actionRepository';
import { listActionTransitions } from '../../../repositories/actionTransitionRepository';
import {
  getConversation,
  insertConversation,
  insertMessage,
} from '../../../repositories/conversationRepository';
import { insertEvidence } from '../../../repositories/evidenceRepository';
import {
  getMemory,
  insertMemory,
  linkMemorySource,
  listMemorySources,
} from '../../../repositories/memoryRepository';
import { getMemoryConfirmation } from '../../../repositories/memoryConfirmationRepository';
import { createTestDatabase } from '../../../repositories/__tests__/testDatabase';
import {
  applyConfirmedDelta,
  applyConfirmedConflictResolution,
  confirmedDeltaResolutionPayload,
  confirmedConflictResolutionPayload,
  UnsafeAutomaticDeltaError,
} from '../applyDelta';
import {
  ConfirmationPayloadMismatchError,
  MemoryConfirmationStateError,
  confirmMemoryResolution,
  stageMemoryConfirmation,
} from '../confirmationWorkflow';

const NOW = '2026-08-10T09:00:00.000Z';
const LATER = '2026-08-10T10:00:00.000Z';

const conversation: LocalConversation = {
  id: 'conversation-memory-engine',
  title: 'Career direction',
  lifecycle: 'active',
  preferredInputMode: 'text',
  createdAt: NOW,
  updatedAt: NOW,
  archivedAt: null,
};

const originalMessage: LocalMessage = {
  id: 'message-original-goal',
  conversationId: conversation.id,
  parentMessageId: null,
  role: 'user',
  content: 'I want to become a Staff Product Designer.',
  lifecycle: 'submitted',
  requestId: 'request-original',
  createdAt: NOW,
  updatedAt: NOW,
};

const currentMessage: LocalMessage = {
  ...originalMessage,
  id: 'message-management',
  parentMessageId: originalMessage.id,
  content: 'I may want to move into management.',
  requestId: 'request-management',
  createdAt: LATER,
  updatedAt: LATER,
};

const staffGoal: LocalMemoryItem = {
  id: 'memory-staff',
  type: 'goal',
  statement: 'Become a Staff Product Designer',
  provenance: 'user-confirmed',
  lifecycle: 'active',
  confidence: 'established',
  createdAt: NOW,
  confirmedAt: NOW,
  lastSupportedAt: NOW,
  statusChangedAt: NOW,
  updatedAt: NOW,
  sourceMessageIds: [originalMessage.id],
  sourceEvidenceIds: [],
  supersedesId: null,
};

async function seedConversationAndStaffGoal(
  db: ReturnType<typeof createTestDatabase>,
): Promise<void> {
  await db.withTransaction((tx) => insertConversation(tx, conversation, 'seed-conversation'));
  await db.withTransaction((tx) => insertMessage(tx, originalMessage, 'seed-message-original'));
  await db.withTransaction((tx) => insertMessage(tx, currentMessage, 'seed-message-current'));
  await db.withTransaction((tx) => insertMemory(tx, staffGoal, 'seed-memory-staff'));
  await db.withTransaction((tx) =>
    linkMemorySource(
      tx,
      {
        id: 'source-original-goal',
        memoryItemId: staffGoal.id,
        messageId: originalMessage.id,
        evidenceId: null,
        linkedAt: NOW,
      },
      'seed-source-original-goal',
    ),
  );
}

describe('applyConfirmedDelta', () => {
  test('does not let an AI proposal persist through the safe-automatic path', async () => {
    const db = createTestDatabase();
    const proposal = {
      operation: 'propose' as const,
      candidate: {
        type: 'goal' as const,
        statement: 'Move into product design management',
        provenance: 'ai-inferred' as const,
        lifecycle: 'active' as const,
        confidence: 'tentative' as const,
        sourceMessageIds: [currentMessage.id],
        supersedesId: staffGoal.id,
      },
      reason: 'The current thought may signal a change in direction.',
      requiresConfirmation: false,
      changeKind: 'replace' as const,
      sensitivity: 'none' as const,
      materialToFutureCoaching: true,
      conflictsWithIds: [staffGoal.id],
    };

    try {
      await seedConversationAndStaffGoal(db);
      await expect(
        db.withTransaction((tx) =>
          applyConfirmedDelta(tx, {
            delta: proposal,
            authorization: { kind: 'safe-automatic' },
            idempotencyId: 'management-proposal',
            effectiveAt: LATER,
            newMemoryId: 'memory-management',
            sourceLinks: [
              {
                id: 'source-management',
                memoryItemId: 'memory-management',
                messageId: currentMessage.id,
                evidenceId: null,
                linkedAt: LATER,
              },
            ],
          }),
        ),
      ).rejects.toBeInstanceOf(UnsafeAutomaticDeltaError);
      expect(await getMemory(db, 'memory-management')).toBeNull();
      expect((await getMemory(db, staffGoal.id))?.lifecycle).toBe('active');
    } finally {
      db.close();
    }
  });

  test('requires the exact durable confirmed payload and consumes it once', async () => {
    const db = createTestDatabase();
    const proposal = {
      operation: 'propose' as const,
      candidate: {
        type: 'preference' as const,
        statement: 'Prefer roles with strategic ownership',
        provenance: 'ai-inferred' as const,
        lifecycle: 'proposed' as const,
        confidence: 'tentative' as const,
        sourceMessageIds: [currentMessage.id],
        supersedesId: null,
      },
      reason: 'The submitted thought may indicate a durable preference.',
      requiresConfirmation: true,
      changeKind: 'create' as const,
      sensitivity: 'unclassified' as const,
      materialToFutureCoaching: true,
      conflictsWithIds: [],
    };
    const application = {
      delta: proposal,
      authorization: {
        kind: 'confirmed-record' as const,
        confirmationId: 'confirmation-strategic-ownership',
      },
      idempotencyId: 'apply-strategic-ownership',
      effectiveAt: LATER,
      newMemoryId: 'memory-strategic-ownership',
      sourceLinks: [
        {
          id: 'source-strategic-ownership',
          memoryItemId: 'memory-strategic-ownership',
          messageId: currentMessage.id,
          evidenceId: null,
          linkedAt: LATER,
        },
      ],
    };

    try {
      await seedConversationAndStaffGoal(db);
      await db.withTransaction((tx) =>
        stageMemoryConfirmation(tx, {
          confirmationId: application.authorization.confirmationId,
          proposal,
          conversationId: conversation.id,
          sourceMessageId: currentMessage.id,
          stagedAt: NOW,
          idempotencyId: 'stage-strategic-ownership',
        }),
      );

      await expect(
        db.withTransaction((tx) => applyConfirmedDelta(tx, application)),
      ).rejects.toBeInstanceOf(MemoryConfirmationStateError);
      await db.withTransaction((tx) =>
        confirmMemoryResolution(tx, {
          confirmationId: application.authorization.confirmationId,
          resolution: confirmedDeltaResolutionPayload(application),
          localUserAction: {
            id: 'user-action-strategic-ownership',
            kind: 'explicit-confirm',
            actedAt: LATER,
          },
          idempotencyId: 'confirm-strategic-ownership',
        }),
      );
      await expect(
        db.withTransaction((tx) =>
          applyConfirmedDelta(tx, { ...application, effectiveAt: NOW }),
        ),
      ).rejects.toBeInstanceOf(ConfirmationPayloadMismatchError);
      await db.withTransaction((tx) => applyConfirmedDelta(tx, application));
      await db.withTransaction((tx) => applyConfirmedDelta(tx, application));

      expect(await getMemory(db, application.newMemoryId)).toMatchObject({
        id: application.newMemoryId,
        statement: proposal.candidate.statement,
        lifecycle: 'active',
      });
      expect(
        await getMemoryConfirmation(db, application.authorization.confirmationId),
      ).toMatchObject({
        status: 'consumed',
        consumedByIdempotencyId: application.idempotencyId,
      });
    } finally {
      db.close();
    }
  });

  test('applies one confirmed replacement bundle without erasing history and is idempotent', async () => {
    const db = createTestDatabase();
    const proposal = {
      operation: 'propose' as const,
      candidate: {
        type: 'goal' as const,
        statement: 'Move into product design management',
        provenance: 'ai-inferred' as const,
        lifecycle: 'proposed' as const,
        confidence: 'tentative' as const,
        sourceMessageIds: [currentMessage.id],
        supersedesId: staffGoal.id,
      },
      reason: 'The user confirmed a change in direction.',
      requiresConfirmation: true,
      changeKind: 'replace' as const,
      sensitivity: 'unclassified' as const,
      materialToFutureCoaching: true,
      conflictsWithIds: [staffGoal.id],
    };
    const application = {
      confirmationId: 'confirmation-management',
      idempotencyId: 'management-conflict-resolution',
      effectiveAt: LATER,
      successorId: 'memory-management',
      candidate: proposal,
      predecessorIds: [staffGoal.id],
      sourceLinks: [
        {
          id: 'source-management',
          memoryItemId: 'memory-management',
          messageId: currentMessage.id,
          evidenceId: null,
          linkedAt: LATER,
        },
        {
          id: 'source-management-transition',
          memoryItemId: staffGoal.id,
          messageId: currentMessage.id,
          evidenceId: null,
          linkedAt: LATER,
        },
      ],
    };

    try {
      await seedConversationAndStaffGoal(db);
      await db.withTransaction((tx) =>
        stageMemoryConfirmation(tx, {
          confirmationId: application.confirmationId,
          proposal: {
            ...proposal,
          },
          conversationId: conversation.id,
          sourceMessageId: currentMessage.id,
          stagedAt: NOW,
          idempotencyId: 'stage-management-conflict',
        }),
      );
      await db.withTransaction((tx) =>
        confirmMemoryResolution(tx, {
          confirmationId: application.confirmationId,
          resolution: confirmedConflictResolutionPayload(application),
          localUserAction: {
            id: 'user-action-management-conflict',
            kind: 'explicit-confirm',
            actedAt: LATER,
          },
          idempotencyId: 'confirm-management-conflict',
        }),
      );
      await db.withTransaction((tx) => applyConfirmedConflictResolution(tx, application));
      await db.withTransaction((tx) => applyConfirmedConflictResolution(tx, application));

      expect(await getMemory(db, 'memory-management')).toEqual({
        id: 'memory-management',
        type: 'goal',
        statement: 'Move into product design management',
        provenance: 'ai-inferred',
        lifecycle: 'active',
        confidence: 'tentative',
        createdAt: LATER,
        confirmedAt: LATER,
        lastSupportedAt: LATER,
        statusChangedAt: LATER,
        updatedAt: LATER,
        sourceMessageIds: [currentMessage.id],
        sourceEvidenceIds: [],
        supersedesId: staffGoal.id,
      });
      expect(await getMemory(db, staffGoal.id)).toMatchObject({
        id: staffGoal.id,
        statement: staffGoal.statement,
        lifecycle: 'superseded',
        sourceMessageIds: [originalMessage.id, currentMessage.id],
      });
      expect(await listMemorySources(db, 'memory-management')).toEqual([
        application.sourceLinks[0],
      ]);
      expect(await getMemoryConfirmation(db, application.confirmationId)).toMatchObject({
        status: 'consumed',
        consumedByIdempotencyId: application.idempotencyId,
      });
    } finally {
      db.close();
    }
  });

  test('rolls back the entire confirmed replacement when a source write fails midway', async () => {
    const db = createTestDatabase();
    const candidate = {
      operation: 'propose' as const,
      candidate: {
        type: 'goal' as const,
        statement: 'Move into product design management',
        provenance: 'ai-inferred' as const,
        lifecycle: 'proposed' as const,
        confidence: 'tentative' as const,
        sourceMessageIds: [currentMessage.id],
        supersedesId: staffGoal.id,
      },
      reason: 'Replace the Staff direction.',
      requiresConfirmation: true,
      changeKind: 'replace' as const,
      sensitivity: 'unclassified' as const,
      materialToFutureCoaching: true,
      conflictsWithIds: [staffGoal.id],
    };
    const application = {
      confirmationId: 'confirmation-rollback',
      idempotencyId: 'conflict-resolution-rollback',
      effectiveAt: LATER,
      successorId: 'memory-management-rollback',
      candidate,
      predecessorIds: [staffGoal.id],
      sourceLinks: [
        {
          id: 'source-management-rollback',
          memoryItemId: 'memory-management-rollback',
          messageId: currentMessage.id,
          evidenceId: null,
          linkedAt: LATER,
        },
        {
          id: 'source-original-goal',
          memoryItemId: staffGoal.id,
          messageId: currentMessage.id,
          evidenceId: null,
          linkedAt: LATER,
        },
      ],
    };

    try {
      await seedConversationAndStaffGoal(db);
      await db.withTransaction((tx) =>
        stageMemoryConfirmation(tx, {
          confirmationId: application.confirmationId,
          proposal: {
            ...candidate,
          },
          conversationId: conversation.id,
          sourceMessageId: currentMessage.id,
          stagedAt: NOW,
          idempotencyId: 'stage-conflict-rollback',
        }),
      );
      await db.withTransaction((tx) =>
        confirmMemoryResolution(tx, {
          confirmationId: application.confirmationId,
          resolution: confirmedConflictResolutionPayload(application),
          localUserAction: {
            id: 'user-action-conflict-rollback',
            kind: 'explicit-confirm',
            actedAt: LATER,
          },
          idempotencyId: 'confirm-conflict-rollback',
        }),
      );

      let failure: unknown = null;
      try {
        await db.withTransaction((tx) => applyConfirmedConflictResolution(tx, application));
      } catch (error) {
        failure = error;
      }
      expect(failure).not.toBeNull();
      expect(String((failure as { message?: unknown }).message)).toContain('UNIQUE constraint failed');
      expect(await getMemory(db, application.successorId)).toBeNull();
      expect(await getMemory(db, staffGoal.id)).toMatchObject({ lifecycle: 'active' });
      expect(await getMemoryConfirmation(db, application.confirmationId)).toMatchObject({
        status: 'confirmed',
        consumedAt: null,
      });
    } finally {
      db.close();
    }
  });

  test('applies only state-proven automatic support, evidence link, action completion, and archival', async () => {
    const db = createTestDatabase();
    const developmentArea: LocalMemoryItem = {
      ...staffGoal,
      id: 'memory-influence',
      type: 'development_area',
      statement: 'Strengthen stakeholder influence',
      provenance: 'system-observed',
      confidence: 'tentative',
      sourceMessageIds: [],
    };
    const evidenceItem: LocalEvidenceItem = {
      id: 'evidence-roadmap',
      statement: 'Led the roadmap workshop',
      occurredAt: LATER,
      sourceMessageIds: [currentMessage.id],
      goalIds: [],
      actionIds: ['action-roadmap'],
      createdAt: LATER,
      updatedAt: LATER,
    };
    const action: LocalAction = {
      id: 'action-roadmap',
      goalId: null,
      sourceMessageId: originalMessage.id,
      title: 'Lead the roadmap workshop',
      description: null,
      lifecycle: 'open',
      priority: 'high',
      dueAt: null,
      supersedesId: null,
      createdAt: NOW,
      updatedAt: NOW,
      statusChangedAt: NOW,
    };
    const actionCompletion = {
      delta: {
        operation: 'complete-action' as const,
        targetId: action.id,
        explicitlyCompleted: true,
        sourceMessageId: currentMessage.id,
        reason: 'The user said the workshop is complete.',
        requiresConfirmation: false,
      },
      authorization: { kind: 'safe-automatic' as const },
      idempotencyId: 'complete-roadmap-action',
      effectiveAt: LATER,
      transitionId: 'transition-roadmap-completion',
      trustedContext: {
        conversationId: conversation.id,
        sourceMessageId: currentMessage.id,
        requestId: currentMessage.requestId!,
      },
      sourceLinks: [],
    };
    const conversationArchival = {
      delta: {
        operation: 'archive-conversation' as const,
        targetId: conversation.id,
        reason: 'The conversation is complete.',
        requiresConfirmation: false,
      },
      authorization: { kind: 'safe-automatic' as const },
      idempotencyId: 'archive-direction-conversation',
      effectiveAt: LATER,
      sourceLinks: [],
    };

    try {
      await seedConversationAndStaffGoal(db);
      await db.withTransaction((tx) => insertMemory(tx, developmentArea, 'seed-memory-influence'));
      await db.withTransaction((tx) => insertEvidence(tx, evidenceItem, 'seed-evidence-roadmap'));
      await db.withTransaction((tx) => insertAction(tx, action, 'seed-action-roadmap'));

      await db.withTransaction(async (tx) => {
        await applyConfirmedDelta(tx, {
          delta: {
            operation: 'support',
            targetId: developmentArea.id,
            sourceMessageId: currentMessage.id,
            reason: 'The workshop supports the observation.',
            requiresConfirmation: false,
          },
          authorization: { kind: 'safe-automatic' },
          idempotencyId: 'support-influence',
          effectiveAt: LATER,
          sourceLinks: [
            {
              id: 'source-support-influence',
              memoryItemId: developmentArea.id,
              messageId: currentMessage.id,
              evidenceId: null,
              linkedAt: LATER,
            },
          ],
        });
        await applyConfirmedDelta(tx, {
          delta: {
            operation: 'link-evidence',
            targetMemoryId: developmentArea.id,
            evidenceId: evidenceItem.id,
            reason: 'The evidence supports the development area.',
            requiresConfirmation: false,
          },
          authorization: { kind: 'safe-automatic' },
          idempotencyId: 'link-influence-evidence',
          effectiveAt: LATER,
          sourceLinks: [
            {
              id: 'source-evidence-influence',
              memoryItemId: developmentArea.id,
              messageId: null,
              evidenceId: evidenceItem.id,
              linkedAt: LATER,
            },
          ],
        });
        await applyConfirmedDelta(tx, actionCompletion);
        await applyConfirmedDelta(tx, conversationArchival);
      });
      await db.withTransaction(async (tx) => {
        await applyConfirmedDelta(tx, actionCompletion);
        await applyConfirmedDelta(tx, conversationArchival);
      });

      expect(await getMemory(db, developmentArea.id)).toMatchObject({
        confidence: 'supported',
        lastSupportedAt: LATER,
        sourceMessageIds: [currentMessage.id],
        sourceEvidenceIds: [evidenceItem.id],
      });
      expect(await getAction(db, action.id)).toMatchObject({
        lifecycle: 'completed',
        sourceMessageId: originalMessage.id,
        updatedAt: LATER,
        statusChangedAt: LATER,
      });
      expect(await listActionTransitions(db, action.id)).toEqual([
        {
          id: 'transition-roadmap-completion',
          actionId: action.id,
          fromLifecycle: 'open',
          toLifecycle: 'completed',
          sourceMessageId: currentMessage.id,
          conversationId: conversation.id,
          requestId: currentMessage.requestId,
          kind: 'explicit-user-completion',
          occurredAt: LATER,
        },
      ]);
      expect(await getConversation(db, conversation.id)).toMatchObject({
        lifecycle: 'archived',
        archivedAt: LATER,
        updatedAt: LATER,
      });
    } finally {
      db.close();
    }
  });

  test.each([
    [
      'private user message',
      { role: 'user' as const, lifecycle: 'private' as const, conversationId: conversation.id },
      { conversationId: conversation.id, requestId: 'request-spoof' },
    ],
    [
      'assistant message',
      { role: 'assistant' as const, lifecycle: 'received' as const, conversationId: conversation.id },
      { conversationId: conversation.id, requestId: 'request-spoof' },
    ],
    [
      'message from another conversation',
      { role: 'user' as const, lifecycle: 'submitted' as const, conversationId: 'conversation-other' },
      { conversationId: conversation.id, requestId: 'request-spoof' },
    ],
    [
      'stale request context',
      { role: 'user' as const, lifecycle: 'submitted' as const, conversationId: conversation.id },
      { conversationId: conversation.id, requestId: 'request-current-different' },
    ],
  ])('rejects automatic completion from a %s', async (_label, messageOverrides, contextOverrides) => {
    const db = createTestDatabase();
    const otherConversation: LocalConversation = {
      ...conversation,
      id: 'conversation-other',
    };
    const spoofMessage: LocalMessage = {
      ...currentMessage,
      id: 'message-spoof',
      requestId: 'request-spoof',
      ...messageOverrides,
    };
    const openAction: LocalAction = {
      id: 'action-spoof-check',
      goalId: null,
      sourceMessageId: originalMessage.id,
      title: 'Complete only from trusted evidence',
      description: null,
      lifecycle: 'open',
      priority: null,
      dueAt: null,
      supersedesId: null,
      createdAt: NOW,
      updatedAt: NOW,
      statusChangedAt: NOW,
    };

    try {
      await seedConversationAndStaffGoal(db);
      await db.withTransaction((tx) =>
        insertConversation(tx, otherConversation, 'seed-other-conversation'),
      );
      await db.withTransaction((tx) =>
        insertMessage(tx, spoofMessage, `seed-${spoofMessage.id}`),
      );
      await db.withTransaction((tx) => insertAction(tx, openAction, 'seed-spoof-action'));

      await expect(
        db.withTransaction((tx) =>
          applyConfirmedDelta(tx, {
            delta: {
              operation: 'complete-action',
              targetId: openAction.id,
              explicitlyCompleted: true,
              sourceMessageId: spoofMessage.id,
              reason: 'Untrusted completion attempt.',
              requiresConfirmation: false,
            },
            authorization: { kind: 'safe-automatic' },
            idempotencyId: `complete-spoof-${_label}`,
            effectiveAt: LATER,
            transitionId: `transition-spoof-${_label}`,
            trustedContext: {
              conversationId: contextOverrides.conversationId,
              sourceMessageId: spoofMessage.id,
              requestId: contextOverrides.requestId,
            },
            sourceLinks: [],
          }),
        ),
      ).rejects.toBeInstanceOf(UnsafeAutomaticDeltaError);
      expect(await getAction(db, openAction.id)).toMatchObject({ lifecycle: 'open' });
      expect(await listActionTransitions(db, openAction.id)).toEqual([]);
    } finally {
      db.close();
    }
  });
});
