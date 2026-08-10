import type {
  LocalConversation,
  LocalEvidenceItem,
  LocalMemoryItem,
  LocalMessage,
} from '@taisa/shared';

import { insertConversation, insertMessage } from '../conversationRepository';
import { insertEvidence } from '../evidenceRepository';
import {
  getMemory,
  insertMemory,
  linkMemorySource,
  listMemories,
  listMemorySources,
  updateMemory,
} from '../memoryRepository';
import { createTestDatabase, LATER, NOW } from './testDatabase';

const conversation: LocalConversation = {
  id: 'conversation-source',
  title: null,
  lifecycle: 'active',
  createdAt: NOW,
  updatedAt: NOW,
  archivedAt: null,
};

const message: LocalMessage = {
  id: 'message-source',
  conversationId: conversation.id,
  parentMessageId: null,
  role: 'user',
  content: 'I want to become a Staff Designer.',
  lifecycle: 'submitted',
  requestId: 'request-source',
  createdAt: NOW,
  updatedAt: NOW,
};

const evidence: LocalEvidenceItem = {
  id: 'evidence-source',
  statement: 'Led a cross-functional roadmap workshop.',
  occurredAt: NOW,
  sourceMessageIds: [message.id],
  goalIds: [],
  actionIds: [],
  createdAt: NOW,
  updatedAt: NOW,
};

const memory: LocalMemoryItem = {
  id: 'memory-1',
  type: 'goal',
  statement: 'Become a Staff Designer',
  provenance: 'user-confirmed',
  lifecycle: 'active',
  confidence: 'established',
  createdAt: NOW,
  confirmedAt: NOW,
  lastSupportedAt: NOW,
  statusChangedAt: NOW,
  updatedAt: NOW,
  sourceMessageIds: [],
  sourceEvidenceIds: [],
  supersedesId: null,
};

describe('memoryRepository', () => {
  test('creates, reads, updates, lists, filters, and traces message and evidence sources', async () => {
    const db = createTestDatabase();

    try {
      await db.withTransaction((tx) => insertConversation(tx, conversation, 'conversation-create-1'));
      await db.withTransaction((tx) => insertMessage(tx, message, 'message-create-1'));
      await db.withTransaction((tx) => insertEvidence(tx, evidence, 'evidence-create-1'));
      await db.withTransaction((tx) => insertMemory(tx, memory, 'memory-create-1'));
      await db.withTransaction((tx) =>
        linkMemorySource(
          tx,
          { id: 'source-message', memoryItemId: memory.id, messageId: message.id, evidenceId: null, linkedAt: NOW },
          'memory-link-1',
        ),
      );
      await db.withTransaction((tx) =>
        linkMemorySource(
          tx,
          { id: 'source-evidence', memoryItemId: memory.id, messageId: null, evidenceId: evidence.id, linkedAt: NOW },
          'memory-link-2',
        ),
      );

      expect(await getMemory(db, memory.id)).toEqual({
        ...memory,
        sourceMessageIds: [message.id],
        sourceEvidenceIds: [evidence.id],
      });
      expect(await listMemorySources(db, memory.id)).toEqual([
        { id: 'source-message', memoryItemId: memory.id, messageId: message.id, evidenceId: null, linkedAt: NOW },
        { id: 'source-evidence', memoryItemId: memory.id, messageId: null, evidenceId: evidence.id, linkedAt: NOW },
      ]);

      const completed: LocalMemoryItem = {
        ...memory,
        lifecycle: 'completed',
        updatedAt: LATER,
        statusChangedAt: LATER,
      };
      await db.withTransaction((tx) => updateMemory(tx, completed, 'memory-update-1'));
      expect(await listMemories(db, ['active'])).toEqual([]);
      expect((await listMemories(db, ['completed']))[0]).toMatchObject({
        id: memory.id,
        sourceMessageIds: [message.id],
        sourceEvidenceIds: [evidence.id],
      });
    } finally {
      db.close();
    }
  });

  test('a missing memory update rolls back its receipt so the same mutation can be retried', async () => {
    const db = createTestDatabase();
    const completed: LocalMemoryItem = {
      ...memory,
      lifecycle: 'completed',
      updatedAt: LATER,
      statusChangedAt: LATER,
    };

    try {
      await expect(
        db.withTransaction((tx) => updateMemory(tx, completed, 'memory-update-retry')),
      ).rejects.toThrow('Cannot update missing memory');
      await db.withTransaction((tx) => insertMemory(tx, memory, 'memory-create-1'));
      await db.withTransaction((tx) => updateMemory(tx, completed, 'memory-update-retry'));
      expect(await getMemory(db, memory.id)).toEqual(completed);
    } finally {
      db.close();
    }
  });

  test.each(['insert', 'update'] as const)(
    '%s retry treats omitted and database-normalized null supersedesId as the same mutation',
    async (operation) => {
      const db = createTestDatabase();
      const withoutSupersedesId: LocalMemoryItem = {
        id: `memory-nullable-${operation}`,
        type: 'goal',
        statement: 'Become a Staff Designer',
        provenance: 'user-confirmed',
        lifecycle: operation === 'insert' ? 'active' : 'completed',
        confidence: 'established',
        createdAt: NOW,
        confirmedAt: NOW,
        lastSupportedAt: NOW,
        statusChangedAt: operation === 'insert' ? NOW : LATER,
        updatedAt: operation === 'insert' ? NOW : LATER,
        sourceMessageIds: [],
        sourceEvidenceIds: [],
      };
      const idempotencyId = `memory-nullable-${operation}-retry`;

      try {
        if (operation === 'update') {
          await db.withTransaction((tx) =>
            insertMemory(
              tx,
              { ...withoutSupersedesId, lifecycle: 'active', updatedAt: NOW, statusChangedAt: NOW },
              'memory-nullable-update-create',
            ),
          );
          await db.withTransaction((tx) =>
            updateMemory(tx, withoutSupersedesId, idempotencyId),
          );
        } else {
          await db.withTransaction((tx) =>
            insertMemory(tx, withoutSupersedesId, idempotencyId),
          );
        }

        const databaseNormalized = await getMemory(db, withoutSupersedesId.id);
        expect(databaseNormalized?.supersedesId).toBeNull();

        await db.withTransaction((tx) =>
          operation === 'insert'
            ? insertMemory(tx, databaseNormalized!, idempotencyId)
            : updateMemory(tx, databaseNormalized!, idempotencyId),
        );
        expect(await getMemory(db, withoutSupersedesId.id)).toEqual(databaseNormalized);
      } finally {
        db.close();
      }
    },
  );

  test('memory candidate lookup enforces the caller-supplied SQL limit', async () => {
    const db = createTestDatabase();
    try {
      for (let index = 0; index < 3; index += 1) {
        await db.withTransaction((tx) => insertMemory(tx, {
          ...memory,
          id: `bounded-memory-${index}`,
          updatedAt: `2026-08-10T09:00:0${index}.000Z`,
        }, `bounded-memory-insert-${index}`));
      }

      expect((await listMemories(db, ['active'], 2)).map((item) => item.id)).toEqual([
        'bounded-memory-2',
        'bounded-memory-1',
      ]);
      await expect(listMemories(db, ['active'], 0)).rejects.toThrow(
        'Memory limit must be a positive integer',
      );
    } finally {
      db.close();
    }
  });
});
