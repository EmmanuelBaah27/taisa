import type {
  LocalGoal,
  LocalGoalLifecycle,
  LocalMilestone,
  LocalMilestoneLifecycle,
} from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';
import { lifecycleFilter } from './mapping';
import { claimMutation, requireExactlyOneAffectedRow } from './mutationReceipt';

interface GoalRow {
  id: string;
  title: string;
  description: string | null;
  lifecycle: LocalGoalLifecycle;
  priority: LocalGoal['priority'];
  progress_percent: number;
  target_date: string | null;
  source_message_id: string | null;
  supersedes_id: string | null;
  created_at: string;
  updated_at: string;
  status_changed_at: string;
}

interface MilestoneRow {
  id: string;
  goal_id: string;
  title: string;
  lifecycle: LocalMilestoneLifecycle;
  created_at: string;
  updated_at: string;
  completed_at: string | null;
}

const GOAL_COLUMNS = `id, title, description, lifecycle, priority, progress_percent, target_date,
  source_message_id, supersedes_id, created_at, updated_at, status_changed_at`;
const MILESTONE_COLUMNS = 'id, goal_id, title, lifecycle, created_at, updated_at, completed_at';

function mapGoal(row: GoalRow): LocalGoal {
  return {
    id: row.id,
    title: row.title,
    description: row.description,
    lifecycle: row.lifecycle,
    priority: row.priority,
    progressPercent: row.progress_percent,
    targetDate: row.target_date,
    sourceMessageId: row.source_message_id,
    supersedesId: row.supersedes_id,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    statusChangedAt: row.status_changed_at,
  };
}

function mapMilestone(row: MilestoneRow): LocalMilestone {
  return {
    id: row.id,
    goalId: row.goal_id,
    title: row.title,
    lifecycle: row.lifecycle,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    completedAt: row.completed_at,
  };
}

function goalParams(goal: LocalGoal, idempotencyId?: string) {
  return {
    $id: goal.id,
    $title: goal.title,
    $description: goal.description,
    $lifecycle: goal.lifecycle,
    $priority: goal.priority,
    $progressPercent: goal.progressPercent,
    $targetDate: goal.targetDate,
    $sourceMessageId: goal.sourceMessageId,
    $supersedesId: goal.supersedesId,
    $createdAt: goal.createdAt,
    $updatedAt: goal.updatedAt,
    $statusChangedAt: goal.statusChangedAt,
    $idempotencyId: idempotencyId ?? null,
  };
}

async function insertGoalRow(
  transaction: RepositoryTransaction,
  goal: LocalGoal,
  idempotencyId: string,
): Promise<void> {
  await transaction.runAsync(
    `INSERT INTO goals
       (id, title, description, lifecycle, priority, progress_percent, target_date,
        source_message_id, supersedes_id, created_at, updated_at, status_changed_at, idempotency_key)
     VALUES ($id, $title, $description, $lifecycle, $priority, $progressPercent, $targetDate,
       $sourceMessageId, $supersedesId, $createdAt, $updatedAt, $statusChangedAt, $idempotencyId)`,
    goalParams(goal, idempotencyId),
  );
}

export async function insertGoal(
  transaction: RepositoryTransaction,
  goal: LocalGoal,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(transaction, idempotencyId, 'goal', goal.id, 'insert', goal))) {
    return;
  }
  await insertGoalRow(transaction, goal, idempotencyId);
}

export async function getGoal(
  database: RepositoryConnection,
  id: string,
): Promise<LocalGoal | null> {
  const row = await database.getFirstAsync<GoalRow>(
    `SELECT ${GOAL_COLUMNS} FROM goals WHERE id = $id`,
    { $id: id },
  );
  return row === null ? null : mapGoal(row);
}

export async function updateGoal(
  transaction: RepositoryTransaction,
  goal: LocalGoal,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(transaction, idempotencyId, 'goal', goal.id, 'update', goal))) {
    return;
  }
  const result = await transaction.runAsync(
    `UPDATE goals SET title = $title, description = $description, lifecycle = $lifecycle,
       priority = $priority, progress_percent = $progressPercent, target_date = $targetDate,
       source_message_id = $sourceMessageId, supersedes_id = $supersedesId,
       created_at = $createdAt, updated_at = $updatedAt, status_changed_at = $statusChangedAt
     WHERE id = $id`,
    goalParams(goal),
  );
  requireExactlyOneAffectedRow(result, 'Cannot update missing goal');
}

export async function listGoals(
  database: RepositoryConnection,
  lifecycles?: readonly LocalGoalLifecycle[],
): Promise<LocalGoal[]> {
  const filter = lifecycleFilter('lifecycle', lifecycles);
  const rows = await database.getAllAsync<GoalRow>(
    `SELECT ${GOAL_COLUMNS} FROM goals${filter.clause}
     ORDER BY updated_at DESC, id`,
    filter.params,
  );
  return rows.map(mapGoal);
}

export async function supersedeGoal(
  transaction: RepositoryTransaction,
  previousGoalId: string,
  successor: LocalGoal,
  idempotencyId: string,
): Promise<void> {
  if (successor.supersedesId !== previousGoalId) {
    throw new TypeError('Successor must reference the superseded goal');
  }
  if (!(await claimMutation(
    transaction,
    idempotencyId,
    'goal',
    successor.id,
    'supersede',
    { previousGoalId, successor },
  ))) {
    return;
  }
  const result = await transaction.runAsync(
    `UPDATE goals SET lifecycle = 'superseded', updated_at = $updatedAt,
       status_changed_at = $statusChangedAt
     WHERE id = $previousGoalId`,
    {
      $previousGoalId: previousGoalId,
      $updatedAt: successor.updatedAt,
      $statusChangedAt: successor.statusChangedAt,
    },
  );
  requireExactlyOneAffectedRow(result, 'Cannot supersede a missing goal');
  await insertGoalRow(transaction, successor, idempotencyId);
}

export async function deleteGoal(
  transaction: RepositoryTransaction,
  id: string,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(transaction, idempotencyId, 'goal', id, 'delete', { id }))) {
    return;
  }
  const result = await transaction.runAsync('DELETE FROM goals WHERE id = $id', { $id: id });
  requireExactlyOneAffectedRow(result, 'Cannot delete missing goal');
}

function milestoneParams(milestone: LocalMilestone, idempotencyId?: string) {
  return {
    $id: milestone.id,
    $goalId: milestone.goalId,
    $title: milestone.title,
    $lifecycle: milestone.lifecycle,
    $createdAt: milestone.createdAt,
    $updatedAt: milestone.updatedAt,
    $completedAt: milestone.completedAt,
    $idempotencyId: idempotencyId ?? null,
  };
}

export async function insertMilestone(
  transaction: RepositoryTransaction,
  milestone: LocalMilestone,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(transaction, idempotencyId, 'milestone', milestone.id, 'insert', milestone))) {
    return;
  }
  await transaction.runAsync(
    `INSERT INTO milestones
       (id, goal_id, title, lifecycle, created_at, updated_at, completed_at, idempotency_key)
     VALUES ($id, $goalId, $title, $lifecycle, $createdAt, $updatedAt, $completedAt, $idempotencyId)`,
    milestoneParams(milestone, idempotencyId),
  );
}

export async function getMilestone(
  database: RepositoryConnection,
  id: string,
): Promise<LocalMilestone | null> {
  const row = await database.getFirstAsync<MilestoneRow>(
    `SELECT ${MILESTONE_COLUMNS} FROM milestones WHERE id = $id`,
    { $id: id },
  );
  return row === null ? null : mapMilestone(row);
}

export async function updateMilestone(
  transaction: RepositoryTransaction,
  milestone: LocalMilestone,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(transaction, idempotencyId, 'milestone', milestone.id, 'update', milestone))) {
    return;
  }
  const result = await transaction.runAsync(
    `UPDATE milestones SET goal_id = $goalId, title = $title, lifecycle = $lifecycle,
       created_at = $createdAt, updated_at = $updatedAt, completed_at = $completedAt
     WHERE id = $id`,
    milestoneParams(milestone),
  );
  requireExactlyOneAffectedRow(result, 'Cannot update missing milestone');
}

export async function listMilestones(
  database: RepositoryConnection,
  goalId: string,
  lifecycles?: readonly LocalMilestoneLifecycle[],
): Promise<LocalMilestone[]> {
  const filter = lifecycleFilter('lifecycle', lifecycles);
  const lifecycleClause = filter.clause.replace(/^ WHERE /, ' AND ');
  const params = Array.isArray(filter.params)
    ? { $goalId: goalId }
    : { ...filter.params, $goalId: goalId };
  const rows = await database.getAllAsync<MilestoneRow>(
    `SELECT ${MILESTONE_COLUMNS} FROM milestones
     WHERE goal_id = $goalId${lifecycleClause}
     ORDER BY created_at, id`,
    params,
  );
  return rows.map(mapMilestone);
}
