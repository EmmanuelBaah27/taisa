import type {
  LocalAction,
  LocalConversation,
  LocalEvidenceItem,
  LocalMemoryItem,
  LocalMessage,
} from '@taisa/shared';

import { getAction, insertAction } from '../../../repositories/actionRepository';
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
import { createTestDatabase } from '../../../repositories/__tests__/testDatabase';
import {
  applyConfirmedDelta,
  UnsafeAutomaticDeltaError,
} from '../applyDelta';

const NOW = '2026-08-10T09:00:00.000Z';
const LATER = '2026-08-10T10:00:00.000Z';

const conversation: LocalConversation = {
  id: 'conversation-memory-engine',
  title: 'Career direction',
  lifecycle: 'active',
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

  test('applies a confirmed replacement without erasing history and is idempotent', async () => {
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
      reason: 'The user confirmed a change in direction.',
      requiresConfirmation: true,
      changeKind: 'replace' as const,
      sensitivity: 'none' as const,
      materialToFutureCoaching: true,
      conflictsWithIds: [staffGoal.id],
    };
    const sourceLink = {
      id: 'source-management',
      memoryItemId: 'memory-management',
      messageId: currentMessage.id,
      evidenceId: null,
      linkedAt: LATER,
    };
    const application = {
      delta: proposal,
      authorization: {
        kind: 'user-confirmation' as const,
        confirmationId: 'confirmation-management',
      },
      idempotencyId: 'management-proposal',
      effectiveAt: LATER,
      newMemoryId: 'memory-management',
      sourceLinks: [sourceLink],
    };

    try {
      await seedConversationAndStaffGoal(db);
      await db.withTransaction((tx) => applyConfirmedDelta(tx, application));
      await db.withTransaction((tx) =>
        applyConfirmedDelta(tx, {
          delta: {
            operation: 'transition',
            targetId: staffGoal.id,
            to: 'superseded',
            reason: 'The user confirmed management replaces the Staff direction.',
            requiresConfirmation: true,
          },
          authorization: {
            kind: 'user-confirmation',
            confirmationId: 'confirmation-management',
          },
          idempotencyId: 'management-transition',
          effectiveAt: LATER,
          sourceLinks: [
            {
              id: 'source-management-transition',
              memoryItemId: staffGoal.id,
              messageId: currentMessage.id,
              evidenceId: null,
              linkedAt: LATER,
            },
          ],
        }),
      );
      await db.withTransaction((tx) => applyConfirmedDelta(tx, application));

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
      expect(await listMemorySources(db, 'memory-management')).toEqual([sourceLink]);
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
      sourceMessageId: currentMessage.id,
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
        updatedAt: LATER,
        statusChangedAt: LATER,
      });
      expect(await getConversation(db, conversation.id)).toMatchObject({
        lifecycle: 'archived',
        archivedAt: LATER,
        updatedAt: LATER,
      });
    } finally {
      db.close();
    }
  });
});
