import type { LocalEvidenceItem } from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';
import { parseStringArray } from './mapping';
import { toDatabaseMutationPayload } from './mutationPayload';
import { claimMutation, requireExactlyOneAffectedRow } from './mutationReceipt';

interface EvidenceRow {
  id: string;
  statement: string;
  occurred_at: string;
  source_message_ids_json: string;
  goal_ids_json: string;
  action_ids_json: string;
  created_at: string;
  updated_at: string;
}

const EVIDENCE_COLUMNS = `id, statement, occurred_at, source_message_ids_json, goal_ids_json,
  action_ids_json, created_at, updated_at`;

function mapEvidence(row: EvidenceRow): LocalEvidenceItem {
  return {
    id: row.id,
    statement: row.statement,
    occurredAt: row.occurred_at,
    sourceMessageIds: parseStringArray(
      row.source_message_ids_json,
      'evidence.source_message_ids_json',
    ),
    goalIds: parseStringArray(row.goal_ids_json, 'evidence.goal_ids_json'),
    actionIds: parseStringArray(row.action_ids_json, 'evidence.action_ids_json'),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function evidenceParams(evidence: LocalEvidenceItem, idempotencyId?: string) {
  return {
    $id: evidence.id,
    $statement: evidence.statement,
    $occurredAt: evidence.occurredAt,
    $sourceMessageIdsJson: JSON.stringify(evidence.sourceMessageIds),
    $goalIdsJson: JSON.stringify(evidence.goalIds),
    $actionIdsJson: JSON.stringify(evidence.actionIds),
    $createdAt: evidence.createdAt,
    $updatedAt: evidence.updatedAt,
    $idempotencyId: idempotencyId ?? null,
  };
}

export async function insertEvidence(
  transaction: RepositoryTransaction,
  evidence: LocalEvidenceItem,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(
    transaction,
    idempotencyId,
    'evidence',
    evidence.id,
    'insert',
    toDatabaseMutationPayload(evidenceParams(evidence)),
  ))) {
    return;
  }
  await transaction.runAsync(
    `INSERT INTO evidence
       (id, statement, occurred_at, source_message_ids_json, goal_ids_json, action_ids_json,
        created_at, updated_at, idempotency_key)
     VALUES ($id, $statement, $occurredAt, $sourceMessageIdsJson, $goalIdsJson, $actionIdsJson,
       $createdAt, $updatedAt, $idempotencyId)`,
    evidenceParams(evidence, idempotencyId),
  );
}

export async function getEvidence(
  database: RepositoryConnection,
  id: string,
): Promise<LocalEvidenceItem | null> {
  const row = await database.getFirstAsync<EvidenceRow>(
    `SELECT ${EVIDENCE_COLUMNS} FROM evidence WHERE id = $id`,
    { $id: id },
  );
  return row === null ? null : mapEvidence(row);
}

export async function updateEvidence(
  transaction: RepositoryTransaction,
  evidence: LocalEvidenceItem,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(
    transaction,
    idempotencyId,
    'evidence',
    evidence.id,
    'update',
    toDatabaseMutationPayload(evidenceParams(evidence)),
  ))) {
    return;
  }
  const result = await transaction.runAsync(
    `UPDATE evidence SET statement = $statement, occurred_at = $occurredAt,
       source_message_ids_json = $sourceMessageIdsJson, goal_ids_json = $goalIdsJson,
       action_ids_json = $actionIdsJson, created_at = $createdAt, updated_at = $updatedAt
     WHERE id = $id`,
    evidenceParams(evidence),
  );
  requireExactlyOneAffectedRow(result, 'Cannot update missing evidence');
}

export async function listEvidence(database: RepositoryConnection): Promise<LocalEvidenceItem[]> {
  const rows = await database.getAllAsync<EvidenceRow>(
    `SELECT ${EVIDENCE_COLUMNS} FROM evidence ORDER BY occurred_at DESC, id`,
  );
  return rows.map(mapEvidence);
}

export async function searchEvidence(
  database: RepositoryConnection,
  query: string,
  limit = 50,
): Promise<LocalEvidenceItem[]> {
  const rows = await database.getAllAsync<EvidenceRow>(
    `SELECT e.id, e.statement, e.occurred_at, e.source_message_ids_json, e.goal_ids_json,
            e.action_ids_json, e.created_at, e.updated_at
       FROM evidence_search
       JOIN evidence e ON e.rowid = evidence_search.rowid
      WHERE evidence_search MATCH $query
      ORDER BY bm25(evidence_search), e.occurred_at DESC, e.id
      LIMIT $limit`,
    { $query: query, $limit: limit },
  );
  return rows.map(mapEvidence);
}
