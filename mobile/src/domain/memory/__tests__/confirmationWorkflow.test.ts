import type { LocalConversation, LocalMessage } from '@taisa/shared';

import {
  insertConversation,
  insertMessage,
} from '../../../repositories/conversationRepository';
import {
  getMemoryConfirmation,
} from '../../../repositories/memoryConfirmationRepository';
import { createTestDatabase } from '../../../repositories/__tests__/testDatabase';
import {
  ConfirmationPayloadMismatchError,
  MemoryConfirmationStateError,
  confirmMemoryResolution,
  consumeConfirmedMemoryResolution,
  stageMemoryConfirmation,
} from '../confirmationWorkflow';
import type { GovernedProposeDelta } from '../admission';

const NOW = '2026-08-10T09:00:00.000Z';
const LATER = '2026-08-10T10:00:00.000Z';

const conversation: LocalConversation = {
  id: 'conversation-confirmation',
  title: 'Career direction',
  lifecycle: 'active',
  createdAt: NOW,
  updatedAt: NOW,
  archivedAt: null,
};

const message: LocalMessage = {
  id: 'message-confirmation',
  conversationId: conversation.id,
  parentMessageId: null,
  role: 'user',
  content: 'I may want to move into management.',
  lifecycle: 'submitted',
  requestId: 'request-confirmation',
  createdAt: NOW,
  updatedAt: NOW,
};

const proposal: GovernedProposeDelta = {
  operation: 'propose',
  candidate: {
    type: 'goal',
    statement: 'Move into product design management',
    provenance: 'ai-inferred',
    lifecycle: 'proposed',
    confidence: 'tentative',
    sourceMessageIds: [message.id],
    supersedesId: 'memory-staff',
  },
  reason: 'The current thought may signal a direction change.',
  requiresConfirmation: true,
  changeKind: 'replace',
  sensitivity: 'unclassified',
  materialToFutureCoaching: true,
  conflictsWithIds: ['memory-staff'],
};

const resolution = {
  kind: 'resolve-conflict',
  proposal,
  successorId: 'memory-management',
  predecessorIds: ['memory-staff'],
  sourceMessageId: message.id,
  effectiveAt: LATER,
};

async function seedSource(db: ReturnType<typeof createTestDatabase>): Promise<void> {
  await db.withTransaction((tx) =>
    insertConversation(tx, conversation, 'seed-confirmation-conversation'),
  );
  await db.withTransaction((tx) =>
    insertMessage(tx, message, 'seed-confirmation-message'),
  );
}

describe('durable memory confirmation workflow', () => {
  test('AI output can create only a pending local confirmation record', async () => {
    const db = createTestDatabase();
    try {
      await seedSource(db);
      await db.withTransaction((tx) =>
        stageMemoryConfirmation(tx, {
          confirmationId: 'confirmation-management',
          proposal,
          conversationId: conversation.id,
          sourceMessageId: message.id,
          stagedAt: NOW,
          idempotencyId: 'stage-confirmation-management',
        }),
      );

      expect(await getMemoryConfirmation(db, 'confirmation-management')).toMatchObject({
        id: 'confirmation-management',
        status: 'pending',
        conversationId: conversation.id,
        sourceMessageId: message.id,
        resolutionJson: null,
        resolutionDigest: null,
        localUserActionId: null,
        confirmedAt: null,
        consumedAt: null,
      });
      expect((await getMemoryConfirmation(db, 'confirmation-management'))?.proposalJson).toContain(
        'Move into product design management',
      );
    } finally {
      db.close();
    }
  });

  test('pending, mismatched, and consumed confirmations cannot authorize application', async () => {
    const db = createTestDatabase();
    try {
      await seedSource(db);
      await expect(
        db.withTransaction((tx) =>
          consumeConfirmedMemoryResolution(tx, {
            confirmationId: 'confirmation-missing',
            resolution,
            consumedAt: LATER,
            consumedByIdempotencyId: 'apply-management-missing',
          }),
        ),
      ).rejects.toBeInstanceOf(MemoryConfirmationStateError);
      await db.withTransaction((tx) =>
        stageMemoryConfirmation(tx, {
          confirmationId: 'confirmation-management',
          proposal,
          conversationId: conversation.id,
          sourceMessageId: message.id,
          stagedAt: NOW,
          idempotencyId: 'stage-confirmation-management',
        }),
      );

      await expect(
        db.withTransaction((tx) =>
          confirmMemoryResolution(tx, {
            confirmationId: 'confirmation-management',
            resolution: {
              ...resolution,
              proposal: {
                ...proposal,
                candidate: { ...proposal.candidate, statement: 'An unrelated proposal' },
              },
            },
            localUserAction: {
              id: 'user-action-confirm-unrelated',
              kind: 'explicit-confirm',
              actedAt: LATER,
            },
            idempotencyId: 'confirm-management-unrelated',
          }),
        ),
      ).rejects.toBeInstanceOf(ConfirmationPayloadMismatchError);
      expect((await getMemoryConfirmation(db, 'confirmation-management'))?.status).toBe(
        'pending',
      );

      await expect(
        db.withTransaction((tx) =>
          consumeConfirmedMemoryResolution(tx, {
            confirmationId: 'confirmation-management',
            resolution,
            consumedAt: LATER,
            consumedByIdempotencyId: 'apply-management-pending',
          }),
        ),
      ).rejects.toBeInstanceOf(MemoryConfirmationStateError);

      await db.withTransaction((tx) =>
        confirmMemoryResolution(tx, {
          confirmationId: 'confirmation-management',
          resolution,
          localUserAction: {
            id: 'user-action-confirm-management',
            kind: 'explicit-confirm',
            actedAt: LATER,
          },
          idempotencyId: 'confirm-management',
        }),
      );
      await db.withTransaction((tx) =>
        confirmMemoryResolution(tx, {
          confirmationId: 'confirmation-management',
          resolution,
          localUserAction: {
            id: 'user-action-confirm-management',
            kind: 'explicit-confirm',
            actedAt: LATER,
          },
          idempotencyId: 'confirm-management',
        }),
      );

      const confirmed = await getMemoryConfirmation(db, 'confirmation-management');
      expect(confirmed).toMatchObject({
        status: 'confirmed',
        localUserActionId: 'user-action-confirm-management',
        localUserActionKind: 'explicit-confirm',
        localUserActionAt: LATER,
        confirmedAt: LATER,
      });
      expect(confirmed?.resolutionJson).toContain('memory-management');

      await expect(
        db.withTransaction((tx) =>
          consumeConfirmedMemoryResolution(tx, {
            confirmationId: 'confirmation-management',
            resolution: { ...resolution, predecessorIds: ['memory-other'] },
            consumedAt: LATER,
            consumedByIdempotencyId: 'apply-management-mismatch',
          }),
        ),
      ).rejects.toBeInstanceOf(ConfirmationPayloadMismatchError);
      expect((await getMemoryConfirmation(db, 'confirmation-management'))?.status).toBe(
        'confirmed',
      );

      await db.withTransaction((tx) =>
        consumeConfirmedMemoryResolution(tx, {
          confirmationId: 'confirmation-management',
          resolution,
          consumedAt: LATER,
          consumedByIdempotencyId: 'apply-management',
        }),
      );
      expect(await getMemoryConfirmation(db, 'confirmation-management')).toMatchObject({
        status: 'consumed',
        consumedAt: LATER,
        consumedByIdempotencyId: 'apply-management',
      });

      await expect(
        db.withTransaction((tx) =>
          consumeConfirmedMemoryResolution(tx, {
            confirmationId: 'confirmation-management',
            resolution,
            consumedAt: LATER,
            consumedByIdempotencyId: 'apply-management-again',
          }),
        ),
      ).rejects.toBeInstanceOf(MemoryConfirmationStateError);
    } finally {
      db.close();
    }
  });
});
