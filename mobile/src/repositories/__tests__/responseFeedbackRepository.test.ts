import { withRepositoryTransaction } from '../../db/types';
import {
  getResponseFeedback,
  markFeedbackLocalOnly,
  markFeedbackShared,
  saveResponseReaction,
} from '../responseFeedbackRepository';
import { createTestDatabase, LATER, NOW } from './testDatabase';

async function seedResponse(db: ReturnType<typeof createTestDatabase>) {
  await db.runAsync(`INSERT INTO conversations
    (id, title, lifecycle, preferred_input_mode, created_at, updated_at)
    VALUES ('conversation-1', NULL, 'active', 'text', $now, $now)`, { $now: NOW });
  await db.runAsync(`INSERT INTO messages
    (id, conversation_id, role, content, lifecycle, request_id, created_at, updated_at)
    VALUES ('user-1', 'conversation-1', 'user', 'A private work thought', 'submitted', 'request-1', $now, $now)`, { $now: NOW });
  await db.runAsync(`INSERT INTO messages
    (id, conversation_id, parent_message_id, role, content, lifecycle, created_at, updated_at)
    VALUES ('assistant-1', 'conversation-1', 'user-1', 'assistant', 'A useful reply', 'received', $now, $now)`, { $now: NOW });
  await db.runAsync(`INSERT INTO coaching_requests
    (id, intent_id, conversation_id, user_message_id, kind, status, assistant_message_id,
      stance, context_manifest_json, attempt_count, submitted_at, created_at, updated_at)
    VALUES ('request-1', 'intent-1', 'conversation-1', 'user-1', 'text', 'completed',
      'assistant-1', 'nudge', '{"includedMemoryIds":["memory-1"]}', 1, $now, $now, $now)`,
  { $now: NOW });
}

describe('responseFeedbackRepository', () => {
  test('stores reactions locally with no sharing by default and supports idempotent edits', async () => {
    const db = createTestDatabase();
    try {
      await seedResponse(db);
      await withRepositoryTransaction(db, (transaction) => saveResponseReaction(transaction, {
        responseMessageId: 'assistant-1',
        reaction: 'helpful',
        note: null,
        updatedAt: NOW,
      }));
      await withRepositoryTransaction(db, (transaction) => saveResponseReaction(transaction, {
        responseMessageId: 'assistant-1',
        reaction: 'helpful',
        note: null,
        updatedAt: NOW,
      }));
      expect(await getResponseFeedback(db, 'assistant-1')).toEqual({
        responseMessageId: 'assistant-1',
        reaction: 'helpful',
        note: null,
        shareStatus: 'local-only',
        shareConsentAt: null,
        shareReceiptId: null,
        createdAt: NOW,
        updatedAt: NOW,
      });

      await withRepositoryTransaction(db, (transaction) => saveResponseReaction(transaction, {
        responseMessageId: 'assistant-1',
        reaction: 'unhelpful',
        note: 'It assumed context that was not supplied.',
        updatedAt: LATER,
      }));
      expect(await getResponseFeedback(db, 'assistant-1')).toMatchObject({
        reaction: 'unhelpful',
        note: 'It assumed context that was not supplied.',
        shareStatus: 'local-only',
        createdAt: NOW,
        updatedAt: LATER,
      });

      await withRepositoryTransaction(db, (transaction) => markFeedbackShared(
        transaction,
        'assistant-1',
        LATER,
        'receipt-1',
        LATER,
      ));
      expect(await getResponseFeedback(db, 'assistant-1')).toMatchObject({
        shareStatus: 'shared',
        shareConsentAt: LATER,
        shareReceiptId: 'receipt-1',
      });
      await withRepositoryTransaction(db, (transaction) => markFeedbackLocalOnly(
        transaction,
        'assistant-1',
        LATER,
      ));
      expect(await getResponseFeedback(db, 'assistant-1')).toMatchObject({
        shareStatus: 'local-only',
        shareConsentAt: null,
        shareReceiptId: null,
      });
    } finally {
      db.close();
    }
  });
});
