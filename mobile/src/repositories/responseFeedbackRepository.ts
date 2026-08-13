import type { RepositoryConnection, RepositoryTransaction } from '../db/types';

export type ResponseReaction = 'helpful' | 'unhelpful';
export type FeedbackShareStatus = 'local-only' | 'previewed' | 'shared';

export interface ResponseFeedback {
  readonly responseMessageId: string;
  readonly reaction: ResponseReaction;
  readonly note: string | null;
  readonly shareStatus: FeedbackShareStatus;
  readonly shareConsentAt: string | null;
  readonly shareReceiptId: string | null;
  readonly createdAt: string;
  readonly updatedAt: string;
}

export interface SaveResponseReaction {
  readonly responseMessageId: string;
  readonly reaction: ResponseReaction;
  readonly note: string | null;
  readonly updatedAt: string;
}

interface FeedbackRow {
  response_message_id: string;
  reaction: ResponseReaction;
  note: string | null;
  share_status: FeedbackShareStatus;
  share_consent_at: string | null;
  share_receipt_id: string | null;
  created_at: string;
  updated_at: string;
}

function mapFeedback(row: FeedbackRow): ResponseFeedback {
  return {
    responseMessageId: row.response_message_id,
    reaction: row.reaction,
    note: row.note,
    shareStatus: row.share_status,
    shareConsentAt: row.share_consent_at,
    shareReceiptId: row.share_receipt_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export async function saveResponseReaction(
  transaction: RepositoryTransaction,
  feedback: SaveResponseReaction,
): Promise<void> {
  const note = feedback.note?.trim() || null;
  if (note !== null && note.length > 1000) throw new Error('Feedback note is too long');
  await transaction.runAsync(
    `INSERT INTO response_feedback
      (response_message_id, reaction, note, share_status, share_consent_at,
        share_receipt_id, created_at, updated_at)
     VALUES ($responseMessageId, $reaction, $note, 'local-only', NULL, NULL, $updatedAt, $updatedAt)
     ON CONFLICT(response_message_id) DO UPDATE SET
       reaction = excluded.reaction,
       note = excluded.note,
       updated_at = excluded.updated_at`,
    {
      $responseMessageId: feedback.responseMessageId,
      $reaction: feedback.reaction,
      $note: note,
      $updatedAt: feedback.updatedAt,
    },
  );
}

export async function getResponseFeedback(
  database: RepositoryConnection,
  responseMessageId: string,
): Promise<ResponseFeedback | null> {
  const row = await database.getFirstAsync<FeedbackRow>(
    `SELECT response_message_id, reaction, note, share_status, share_consent_at,
      share_receipt_id, created_at, updated_at
     FROM response_feedback WHERE response_message_id = $responseMessageId`,
    { $responseMessageId: responseMessageId },
  );
  return row === null ? null : mapFeedback(row);
}

export async function markFeedbackPreviewed(
  transaction: RepositoryTransaction,
  responseMessageId: string,
  updatedAt: string,
): Promise<void> {
  const result = await transaction.runAsync(
    `UPDATE response_feedback SET share_status = 'previewed', updated_at = $updatedAt
     WHERE response_message_id = $responseMessageId AND share_status <> 'shared'`,
    { $responseMessageId: responseMessageId, $updatedAt: updatedAt },
  );
  if (result.changes !== 1) throw new Error('Response feedback is unavailable');
}
