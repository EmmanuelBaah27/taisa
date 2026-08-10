import type { LocalAction, LocalActionLifecycle } from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';
import { lifecycleFilter } from './mapping';
import { toDatabaseMutationPayload } from './mutationPayload';
import { claimMutation, requireExactlyOneAffectedRow } from './mutationReceipt';

interface ActionRow {
  id: string;
  goal_id: string | null;
  source_message_id: string | null;
  title: string;
  description: string | null;
  lifecycle: LocalActionLifecycle;
  priority: LocalAction['priority'];
  due_at: string | null;
  supersedes_id: string | null;
  created_at: string;
  updated_at: string;
  status_changed_at: string;
}

const ACTION_COLUMNS = `id, goal_id, source_message_id, title, description, lifecycle, priority,
  due_at, supersedes_id, created_at, updated_at, status_changed_at`;

function mapAction(row: ActionRow): LocalAction {
  return {
    id: row.id,
    goalId: row.goal_id,
    sourceMessageId: row.source_message_id,
    title: row.title,
    description: row.description,
    lifecycle: row.lifecycle,
    priority: row.priority,
    dueAt: row.due_at,
    supersedesId: row.supersedes_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    statusChangedAt: row.status_changed_at,
  };
}

function actionParams(action: LocalAction, idempotencyId?: string) {
  return {
    $id: action.id,
    $goalId: action.goalId,
    $sourceMessageId: action.sourceMessageId,
    $title: action.title,
    $description: action.description,
    $lifecycle: action.lifecycle,
    $priority: action.priority,
    $dueAt: action.dueAt,
    $supersedesId: action.supersedesId,
    $createdAt: action.createdAt,
    $updatedAt: action.updatedAt,
    $statusChangedAt: action.statusChangedAt,
    $idempotencyId: idempotencyId ?? null,
  };
}

export async function insertAction(
  transaction: RepositoryTransaction,
  action: LocalAction,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(
    transaction,
    idempotencyId,
    'action',
    action.id,
    'insert',
    toDatabaseMutationPayload(actionParams(action)),
  ))) {
    return;
  }
  await transaction.runAsync(
    `INSERT INTO actions
       (id, goal_id, source_message_id, title, description, lifecycle, priority, due_at,
        supersedes_id, created_at, updated_at, status_changed_at, idempotency_key)
     VALUES ($id, $goalId, $sourceMessageId, $title, $description, $lifecycle, $priority,
       $dueAt, $supersedesId, $createdAt, $updatedAt, $statusChangedAt, $idempotencyId)`,
    actionParams(action, idempotencyId),
  );
}

export async function getAction(
  database: RepositoryConnection,
  id: string,
): Promise<LocalAction | null> {
  const row = await database.getFirstAsync<ActionRow>(
    `SELECT ${ACTION_COLUMNS} FROM actions WHERE id = $id`,
    { $id: id },
  );
  return row === null ? null : mapAction(row);
}

export async function updateAction(
  transaction: RepositoryTransaction,
  action: LocalAction,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(
    transaction,
    idempotencyId,
    'action',
    action.id,
    'update',
    toDatabaseMutationPayload(actionParams(action)),
  ))) {
    return;
  }
  const result = await transaction.runAsync(
    `UPDATE actions SET goal_id = $goalId, source_message_id = $sourceMessageId,
       title = $title, description = $description, lifecycle = $lifecycle,
       priority = $priority, due_at = $dueAt, supersedes_id = $supersedesId,
       created_at = $createdAt, updated_at = $updatedAt, status_changed_at = $statusChangedAt
     WHERE id = $id`,
    actionParams(action),
  );
  requireExactlyOneAffectedRow(result, 'Cannot update missing action');
}

export async function listActions(
  database: RepositoryConnection,
  lifecycles?: readonly LocalActionLifecycle[],
): Promise<LocalAction[]> {
  const filter = lifecycleFilter('lifecycle', lifecycles);
  const rows = await database.getAllAsync<ActionRow>(
    `SELECT ${ACTION_COLUMNS} FROM actions${filter.clause}
     ORDER BY updated_at DESC, id`,
    filter.params,
  );
  return rows.map(mapAction);
}
