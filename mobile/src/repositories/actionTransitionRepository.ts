import type { LocalActionLifecycle } from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';
import { claimMutation } from './mutationReceipt';

export interface LocalActionTransition {
  id: string;
  actionId: string;
  fromLifecycle: LocalActionLifecycle;
  toLifecycle: LocalActionLifecycle;
  sourceMessageId: string;
  conversationId: string;
  requestId: string;
  kind: 'explicit-user-completion';
  occurredAt: string;
}

interface ActionTransitionRow {
  id: string;
  action_id: string;
  from_lifecycle: LocalActionLifecycle;
  to_lifecycle: LocalActionLifecycle;
  source_message_id: string;
  conversation_id: string;
  request_id: string;
  kind: 'explicit-user-completion';
  occurred_at: string;
}

const TRANSITION_COLUMNS = `id, action_id, from_lifecycle, to_lifecycle, source_message_id,
  conversation_id, request_id, kind, occurred_at`;

function mapTransition(row: ActionTransitionRow): LocalActionTransition {
  return {
    id: row.id,
    actionId: row.action_id,
    fromLifecycle: row.from_lifecycle,
    toLifecycle: row.to_lifecycle,
    sourceMessageId: row.source_message_id,
    conversationId: row.conversation_id,
    requestId: row.request_id,
    kind: row.kind,
    occurredAt: row.occurred_at,
  };
}

export async function insertActionTransition(
  transaction: RepositoryTransaction,
  transition: LocalActionTransition,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(
    transaction,
    idempotencyId,
    'action-transition',
    transition.id,
    'insert',
    transition,
  ))) {
    return;
  }
  await transaction.runAsync(
    `INSERT INTO action_transitions
       (id, action_id, from_lifecycle, to_lifecycle, source_message_id, conversation_id,
        request_id, kind, occurred_at, idempotency_key)
     VALUES ($id, $actionId, $fromLifecycle, $toLifecycle, $sourceMessageId, $conversationId,
       $requestId, $kind, $occurredAt, $idempotencyId)`,
    {
      $id: transition.id,
      $actionId: transition.actionId,
      $fromLifecycle: transition.fromLifecycle,
      $toLifecycle: transition.toLifecycle,
      $sourceMessageId: transition.sourceMessageId,
      $conversationId: transition.conversationId,
      $requestId: transition.requestId,
      $kind: transition.kind,
      $occurredAt: transition.occurredAt,
      $idempotencyId: idempotencyId,
    },
  );
}

export async function listActionTransitions(
  database: RepositoryConnection,
  actionId: string,
): Promise<LocalActionTransition[]> {
  const rows = await database.getAllAsync<ActionTransitionRow>(
    `SELECT ${TRANSITION_COLUMNS} FROM action_transitions
     WHERE action_id = $actionId ORDER BY occurred_at, id`,
    { $actionId: actionId },
  );
  return rows.map(mapTransition);
}
