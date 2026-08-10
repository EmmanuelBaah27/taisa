import type { RepositoryConnection, RepositoryTransaction } from '../db/types';
import { claimMutation, requireExactlyOneAffectedRow } from './mutationReceipt';

export type MemoryConfirmationStatus = 'pending' | 'confirmed' | 'consumed';

export interface LocalMemoryConfirmation {
  id: string;
  conversationId: string;
  sourceMessageId: string;
  proposalJson: string;
  proposalDigest: string;
  presentationKind: 'proposal' | 'clarification';
  clarificationQuestion: string | null;
  resolutionJson: string | null;
  resolutionDigest: string | null;
  status: MemoryConfirmationStatus;
  stagedAt: string;
  confirmedAt: string | null;
  consumedAt: string | null;
  localUserActionId: string | null;
  localUserActionKind: 'explicit-confirm' | null;
  localUserActionAt: string | null;
  consumedByIdempotencyId: string | null;
}

interface ConfirmationRow {
  id: string;
  conversation_id: string;
  source_message_id: string;
  proposal_json: string;
  proposal_digest: string;
  presentation_kind: 'proposal' | 'clarification';
  clarification_question: string | null;
  resolution_json: string | null;
  resolution_digest: string | null;
  status: MemoryConfirmationStatus;
  staged_at: string;
  confirmed_at: string | null;
  consumed_at: string | null;
  local_user_action_id: string | null;
  local_user_action_kind: 'explicit-confirm' | null;
  local_user_action_at: string | null;
  consumed_by_idempotency_id: string | null;
}

const CONFIRMATION_COLUMNS = `id, conversation_id, source_message_id, proposal_json,
  proposal_digest, presentation_kind, clarification_question, resolution_json,
  resolution_digest, status, staged_at, confirmed_at,
  consumed_at, local_user_action_id, local_user_action_kind, local_user_action_at,
  consumed_by_idempotency_id`;

function mapConfirmation(row: ConfirmationRow): LocalMemoryConfirmation {
  return {
    id: row.id,
    conversationId: row.conversation_id,
    sourceMessageId: row.source_message_id,
    proposalJson: row.proposal_json,
    proposalDigest: row.proposal_digest,
    presentationKind: row.presentation_kind,
    clarificationQuestion: row.clarification_question,
    resolutionJson: row.resolution_json,
    resolutionDigest: row.resolution_digest,
    status: row.status,
    stagedAt: row.staged_at,
    confirmedAt: row.confirmed_at,
    consumedAt: row.consumed_at,
    localUserActionId: row.local_user_action_id,
    localUserActionKind: row.local_user_action_kind,
    localUserActionAt: row.local_user_action_at,
    consumedByIdempotencyId: row.consumed_by_idempotency_id,
  };
}

export async function getMemoryConfirmation(
  database: RepositoryConnection,
  id: string,
): Promise<LocalMemoryConfirmation | null> {
  const row = await database.getFirstAsync<ConfirmationRow>(
    `SELECT ${CONFIRMATION_COLUMNS} FROM memory_confirmations WHERE id = $id`,
    { $id: id },
  );
  return row === null ? null : mapConfirmation(row);
}

export async function listMemoryConfirmationsByConversation(
  database: RepositoryConnection,
  conversationId: string,
  statuses: readonly MemoryConfirmationStatus[] = ['pending', 'confirmed'],
  limit = 20,
): Promise<LocalMemoryConfirmation[]> {
  if (statuses.length === 0) return [];
  if (!Number.isInteger(limit) || limit <= 0 || limit > 20) {
    throw new TypeError('Memory confirmation limit must be between 1 and 20');
  }
  const statusBindings = Object.fromEntries(
    statuses.map((status, index) => [`$status${index}`, status]),
  );
  const rows = await database.getAllAsync<ConfirmationRow>(
    `SELECT ${CONFIRMATION_COLUMNS} FROM memory_confirmations
     WHERE conversation_id = $conversationId
       AND status IN (${statuses.map((_, index) => `$status${index}`).join(', ')})
     ORDER BY staged_at DESC, id DESC
     LIMIT $limit`,
    { $conversationId: conversationId, $limit: limit, ...statusBindings },
  );
  return rows.map(mapConfirmation);
}

export async function insertPendingMemoryConfirmation(
  transaction: RepositoryTransaction,
  record: Pick<
    LocalMemoryConfirmation,
    | 'id'
    | 'conversationId'
    | 'sourceMessageId'
    | 'proposalJson'
    | 'proposalDigest'
    | 'presentationKind'
    | 'clarificationQuestion'
    | 'stagedAt'
  >,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(
    transaction,
    idempotencyId,
    'memory-confirmation',
    record.id,
    'stage',
    record,
  ))) {
    return;
  }
  await transaction.runAsync(
    `INSERT INTO memory_confirmations
       (id, conversation_id, source_message_id, proposal_json, proposal_digest,
        presentation_kind, clarification_question, status, staged_at)
     VALUES ($id, $conversationId, $sourceMessageId, $proposalJson, $proposalDigest,
       $presentationKind, $clarificationQuestion, 'pending', $stagedAt)`,
    {
      $id: record.id,
      $conversationId: record.conversationId,
      $sourceMessageId: record.sourceMessageId,
      $proposalJson: record.proposalJson,
      $proposalDigest: record.proposalDigest,
      $presentationKind: record.presentationKind,
      $clarificationQuestion: record.clarificationQuestion,
      $stagedAt: record.stagedAt,
    },
  );
}

export async function confirmPendingMemoryConfirmation(
  transaction: RepositoryTransaction,
  input: {
    id: string;
    resolutionJson: string;
    resolutionDigest: string;
    confirmedAt: string;
    localUserActionId: string;
    localUserActionKind: 'explicit-confirm';
    localUserActionAt: string;
  },
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(
    transaction,
    idempotencyId,
    'memory-confirmation',
    input.id,
    'confirm',
    input,
  ))) {
    return;
  }
  const result = await transaction.runAsync(
    `UPDATE memory_confirmations SET status = 'confirmed', resolution_json = $resolutionJson,
       resolution_digest = $resolutionDigest, confirmed_at = $confirmedAt,
       local_user_action_id = $localUserActionId,
       local_user_action_kind = $localUserActionKind,
       local_user_action_at = $localUserActionAt
     WHERE id = $id AND status = 'pending'`,
    {
      $id: input.id,
      $resolutionJson: input.resolutionJson,
      $resolutionDigest: input.resolutionDigest,
      $confirmedAt: input.confirmedAt,
      $localUserActionId: input.localUserActionId,
      $localUserActionKind: input.localUserActionKind,
      $localUserActionAt: input.localUserActionAt,
    },
  );
  requireExactlyOneAffectedRow(result, 'Cannot confirm missing or resolved memory confirmation');
}

export async function consumeMemoryConfirmation(
  transaction: RepositoryTransaction,
  input: {
    id: string;
    consumedAt: string;
    consumedByIdempotencyId: string;
  },
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(
    transaction,
    idempotencyId,
    'memory-confirmation',
    input.id,
    'consume',
    input,
  ))) {
    return;
  }
  const result = await transaction.runAsync(
    `UPDATE memory_confirmations SET status = 'consumed', consumed_at = $consumedAt,
       consumed_by_idempotency_id = $consumedByIdempotencyId
     WHERE id = $id AND status = 'confirmed'`,
    {
      $id: input.id,
      $consumedAt: input.consumedAt,
      $consumedByIdempotencyId: input.consumedByIdempotencyId,
    },
  );
  requireExactlyOneAffectedRow(result, 'Cannot consume missing or unresolved memory confirmation');
}
