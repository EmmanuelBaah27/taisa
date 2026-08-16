import type { LocalConversation, LocalMessage } from '@taisa/shared';

import {
  deleteConversation,
  getConversation,
  getMessage,
  insertConversation,
  insertMessage,
  listChatSummaries,
  listConversations,
  listMessages,
  listRecentConversationMessages,
  listRecentMessages,
  searchMessages,
  setConversationPreferredInputMode,
  updateConversation,
  updateMessage,
} from '../conversationRepository';
import { createTestDatabase, LATER, NOW } from './testDatabase';

const conversation: LocalConversation = {
  id: 'conversation-1',
  title: 'Roadmap reflection',
  lifecycle: 'active',
  preferredInputMode: 'text',
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
  test('defaults new conversations to text and persists an explicit mode switch only once', async () => {
    const db = createTestDatabase();

    try {
      await db.withTransaction((tx) => insertConversation(tx, conversation, 'conversation-create-1'));
      expect(await db.getFirstAsync<{ preferred_input_mode: string; updated_at: string }>(
        'SELECT preferred_input_mode, updated_at FROM conversations WHERE id = $id',
        { $id: conversation.id },
      )).toEqual({ preferred_input_mode: 'text', updated_at: NOW });

      await db.withTransaction((tx) => setConversationPreferredInputMode(
        tx,
        conversation.id,
        'voice',
        LATER,
        'conversation-mode-voice',
      ));
      await db.withTransaction((tx) => setConversationPreferredInputMode(
        tx,
        conversation.id,
        'voice',
        '2026-08-10T11:00:00.000Z',
        'conversation-mode-voice-retry',
      ));

      expect(await getConversation(db, conversation.id)).toEqual({
        ...conversation,
        preferredInputMode: 'voice',
        updatedAt: LATER,
      });
    } finally {
      db.close();
    }
  });

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

  test('lists active chat summaries with the latest visible message from each role', async () => {
    const db = createTestDatabase();

    try {
      await db.withTransaction((tx) => insertConversation(tx, conversation, 'conversation-create-1'));
      await db.withTransaction((tx) => insertMessage(tx, message, 'message-create-1'));
      await db.withTransaction((tx) => insertMessage(tx, {
        ...message,
        id: 'message-2',
        role: 'assistant',
        content: 'Coach reply',
        lifecycle: 'received',
        requestId: null,
        createdAt: LATER,
        updatedAt: LATER,
      }, 'message-create-2'));
      await db.withTransaction((tx) => insertMessage(tx, {
        ...message,
        id: 'message-3',
        content: 'Newest user message',
        requestId: null,
        createdAt: '2026-08-10T11:00:00.000Z',
        updatedAt: '2026-08-10T11:00:00.000Z',
      }, 'message-create-3'));

      const archived = {
        ...conversation,
        id: 'archived-conversation',
        lifecycle: 'archived' as const,
        archivedAt: LATER,
      };
      await db.withTransaction((tx) => insertConversation(tx, archived, 'conversation-create-2'));

      expect(await listChatSummaries(db)).toEqual([{
        id: conversation.id,
        title: conversation.title,
        updatedAt: '2026-08-10T11:00:00.000Z',
        lastUserMessage: 'Newest user message',
        lastAssistantMessage: 'Coach reply',
      }]);
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
        error:
          typeof orphanError === 'object' &&
          orphanError !== null &&
          'message' in orphanError
            ? String(orphanError.message)
            : orphanError,
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

  test('missing conversation update and delete receipts roll back for later retries', async () => {
    const db = createTestDatabase();
    const archived: LocalConversation = {
      ...conversation,
      lifecycle: 'archived',
      archivedAt: LATER,
      updatedAt: LATER,
    };

    try {
      await expect(
        db.withTransaction((tx) =>
          updateConversation(tx, archived, 'conversation-update-retry'),
        ),
      ).rejects.toThrow('Cannot update missing conversation');
      await db.withTransaction((tx) => insertConversation(tx, conversation, 'conversation-create-1'));
      await db.withTransaction((tx) =>
        updateConversation(tx, archived, 'conversation-update-retry'),
      );
      expect(await getConversation(db, conversation.id)).toEqual(archived);

      await expect(
        db.withTransaction((tx) =>
          deleteConversation(tx, 'conversation-missing', 'conversation-delete-retry'),
        ),
      ).rejects.toThrow('Cannot delete missing conversation');
      const second = { ...conversation, id: 'conversation-missing' };
      await db.withTransaction((tx) => insertConversation(tx, second, 'conversation-create-2'));
      await db.withTransaction((tx) =>
        deleteConversation(tx, second.id, 'conversation-delete-retry'),
      );
      expect(await getConversation(db, second.id)).toBeNull();
    } finally {
      db.close();
    }
  });

  test('a missing message update rolls back its receipt so it can be retried', async () => {
    const db = createTestDatabase();
    const updated = { ...message, content: 'Updated thought', updatedAt: LATER };

    try {
      await db.withTransaction((tx) => insertConversation(tx, conversation, 'conversation-create-1'));
      await expect(
        db.withTransaction((tx) => updateMessage(tx, updated, 'message-update-retry')),
      ).rejects.toThrow('Cannot update missing message');
      await db.withTransaction((tx) => insertMessage(tx, message, 'message-create-1'));
      await db.withTransaction((tx) => updateMessage(tx, updated, 'message-update-retry'));
      expect(await getMessage(db, message.id)).toEqual(updated);
    } finally {
      db.close();
    }
  });

  test('recent-message lookup enforces the caller-supplied SQL limit', async () => {
    const db = createTestDatabase();
    try {
      await db.withTransaction((tx) => insertConversation(tx, conversation, 'conversation-create-1'));
      for (let index = 0; index < 3; index += 1) {
        await db.withTransaction((tx) => insertMessage(tx, {
          ...message,
          id: `bounded-message-${index}`,
          requestId: `bounded-request-${index}`,
          createdAt: `2026-08-10T09:00:0${index}.000Z`,
          updatedAt: `2026-08-10T09:00:0${index}.000Z`,
        }, `bounded-message-insert-${index}`));
      }

      expect((await listRecentMessages(db, conversation.id, 2)).map((item) => item.id)).toEqual([
        'bounded-message-2',
        'bounded-message-1',
      ]);
      await expect(listRecentMessages(db, conversation.id, 0)).rejects.toThrow(
        'Message limit must be a positive integer',
      );
    } finally {
      db.close();
    }
  });

  test('recent coaching context filters private and pending rows before applying its SQL limit', async () => {
    const db = createTestDatabase();
    try {
      await db.withTransaction((tx) => insertConversation(tx, conversation, 'context-conversation'));
      for (let index = 0; index < 2; index += 1) {
        await db.withTransaction((tx) => insertMessage(tx, {
          ...message,
          id: `eligible-${index}`,
          requestId: `eligible-request-${index}`,
          createdAt: `2026-08-10T08:00:0${index}.000Z`,
          updatedAt: `2026-08-10T08:00:0${index}.000Z`,
        }, `eligible-insert-${index}`));
      }
      for (let index = 0; index < 4; index += 1) {
        await db.withTransaction((tx) => insertMessage(tx, {
          ...message,
          id: `ineligible-${index}`,
          requestId: null,
          lifecycle: index % 2 === 0 ? 'private' : 'pending',
          createdAt: `2026-08-10T10:00:0${index}.000Z`,
          updatedAt: `2026-08-10T10:00:0${index}.000Z`,
        }, `ineligible-insert-${index}`));
      }

      expect((await listRecentMessages(db, conversation.id, 2)).map((item) => item.id)).toEqual([
        'eligible-1',
        'eligible-0',
      ]);
      expect((await listRecentConversationMessages(db, conversation.id, 2)).map(
        (item) => item.id,
      )).toEqual(['ineligible-3', 'ineligible-2']);
    } finally {
      db.close();
    }
  });
});
