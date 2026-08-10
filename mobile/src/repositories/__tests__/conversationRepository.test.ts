import type { LocalConversation, LocalMessage } from '@taisa/shared';

import {
  deleteConversation,
  getConversation,
  getMessage,
  insertConversation,
  insertMessage,
  listConversations,
  listMessages,
  searchMessages,
  updateConversation,
  updateMessage,
} from '../conversationRepository';
import { createTestDatabase, LATER, NOW } from './testDatabase';

const conversation: LocalConversation = {
  id: 'conversation-1',
  title: 'Roadmap reflection',
  lifecycle: 'active',
  createdAt: NOW,
  updatedAt: NOW,
  archivedAt: null,
};

const message: LocalMessage = {
  id: 'message-1',
  conversationId: conversation.id,
  parentMessageId: null,
  role: 'user',
  content: 'I handled the stakeholder roadmap conversation well.',
  lifecycle: 'submitted',
  requestId: 'request-1',
  createdAt: NOW,
  updatedAt: NOW,
};

describe('conversationRepository', () => {
  test('creates, reads, updates, lists, filters, and searches conversations and messages', async () => {
    const db = createTestDatabase();

    try {
      await db.withTransaction((tx) => insertConversation(tx, conversation, 'conversation-create-1'));
      await db.withTransaction((tx) => insertMessage(tx, message, 'message-create-1'));

      expect(await getConversation(db, conversation.id)).toEqual(conversation);
      expect(await getMessage(db, message.id)).toEqual(message);
      expect(await listMessages(db, conversation.id)).toEqual([message]);
      expect(await searchMessages(db, 'stakeholder')).toEqual([message]);

      const received: LocalMessage = {
        ...message,
        id: 'message-2',
        parentMessageId: message.id,
        role: 'assistant',
        content: 'What evidence shows that your influence improved?',
        lifecycle: 'received',
        requestId: null,
        createdAt: LATER,
        updatedAt: LATER,
      };
      await db.withTransaction((tx) => insertMessage(tx, received, 'message-create-2'));
      await db.withTransaction((tx) =>
        updateMessage(tx, { ...received, content: 'What evidence supports that change?' }, 'message-update-2'),
      );

      const archived: LocalConversation = {
        ...conversation,
        lifecycle: 'archived',
        updatedAt: LATER,
        archivedAt: LATER,
      };
      await db.withTransaction((tx) =>
        updateConversation(tx, archived, 'conversation-update-1'),
      );
      expect(await listConversations(db, ['active'])).toEqual([]);
      expect(await listConversations(db, ['archived'])).toEqual([archived]);
      expect(await listMessages(db, conversation.id, ['received'])).toEqual([
        { ...received, content: 'What evidence supports that change?' },
      ]);
    } finally {
      db.close();
    }
  });

  test('rolls back a mutation receipt when its entity write fails', async () => {
    const db = createTestDatabase();
    const orphan = { ...message, conversationId: 'missing-conversation' };

    try {
      expect(
        await db.getFirstAsync<{ foreign_keys: number }>('PRAGMA foreign_keys'),
      ).toEqual({ foreign_keys: 1 });
      expect(
        await db.getFirstAsync(
          'SELECT idempotency_id FROM mutation_receipts WHERE idempotency_id = $id',
          { $id: 'retry-after-rollback' },
        ),
      ).toBeNull();

      let orphanError: unknown = null;
      try {
        await db.withTransaction((tx) => insertMessage(tx, orphan, 'retry-after-rollback'));
      } catch (error) {
        orphanError = error;
      }
      expect({
        error: orphanError instanceof Error ? orphanError.message : orphanError,
        stored: await getMessage(db, orphan.id),
        violations: await db.getAllAsync('PRAGMA foreign_key_check'),
      }).toEqual({
        error: 'FOREIGN KEY constraint failed',
        stored: null,
        violations: [],
      });

      await db.withTransaction((tx) => insertConversation(tx, conversation, 'conversation-create-1'));
      await db.withTransaction((tx) => insertMessage(tx, message, 'retry-after-rollback'));
      expect(await getMessage(db, message.id)).toEqual(message);
    } finally {
      db.close();
    }
  });

  test('deleting a conversation cascades to its messages', async () => {
    const db = createTestDatabase();

    try {
      await db.withTransaction((tx) => insertConversation(tx, conversation, 'conversation-create-1'));
      await db.withTransaction((tx) => insertMessage(tx, message, 'message-create-1'));
      await db.withTransaction((tx) => deleteConversation(tx, conversation.id, 'conversation-delete-1'));

      expect(await getConversation(db, conversation.id)).toBeNull();
      expect(await getMessage(db, message.id)).toBeNull();
    } finally {
      db.close();
    }
  });
});
