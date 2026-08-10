import type {
  LocalMemoryItem,
  LocalMemorySource,
  MemoryLifecycle,
} from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';
import { lifecycleFilter } from './mapping';
import { claimMutation, requireExactlyOneAffectedRow } from './mutationReceipt';

interface MemoryRow {
  id: string;
  type: LocalMemoryItem['type'];
  statement: string;
  provenance: LocalMemoryItem['provenance'];
  lifecycle: MemoryLifecycle;
  confidence: LocalMemoryItem['confidence'];
  supersedes_id: string | null;
  created_at: string;
  confirmed_at: string | null;
  last_supported_at: string;
  status_changed_at: string;
  updated_at: string;
}

interface MemorySourceRow {
  id: string;
  memory_item_id: string;
  message_id: string | null;
  evidence_id: string | null;
  linked_at: string;
}

const MEMORY_COLUMNS = `id, type, statement, provenance, lifecycle, confidence, supersedes_id,
  created_at, confirmed_at, last_supported_at, status_changed_at, updated_at`;
const MEMORY_SOURCE_COLUMNS = 'id, memory_item_id, message_id, evidence_id, linked_at';

function mapSource(row: MemorySourceRow): LocalMemorySource {
  return {
    id: row.id,
    memoryItemId: row.memory_item_id,
    messageId: row.message_id,
    evidenceId: row.evidence_id,
    linkedAt: row.linked_at,
  };
}

function mapMemory(row: MemoryRow, sources: readonly LocalMemorySource[]): LocalMemoryItem {
  return {
    id: row.id,
    type: row.type,
    statement: row.statement,
    provenance: row.provenance,
    lifecycle: row.lifecycle,
    confidence: row.confidence,
    supersedesId: row.supersedes_id,
    createdAt: row.created_at,
    confirmedAt: row.confirmed_at,
    lastSupportedAt: row.last_supported_at,
    statusChangedAt: row.status_changed_at,
    updatedAt: row.updated_at,
    sourceMessageIds: sources.flatMap((source) =>
      source.messageId === null ? [] : [source.messageId],
    ),
    sourceEvidenceIds: sources.flatMap((source) =>
      source.evidenceId === null ? [] : [source.evidenceId],
    ),
  };
}

function memoryParams(memory: LocalMemoryItem, idempotencyId?: string) {
  return {
    $id: memory.id,
    $type: memory.type,
    $statement: memory.statement,
    $provenance: memory.provenance,
    $lifecycle: memory.lifecycle,
    $confidence: memory.confidence,
    $supersedesId: memory.supersedesId ?? null,
    $createdAt: memory.createdAt,
    $confirmedAt: memory.confirmedAt,
    $lastSupportedAt: memory.lastSupportedAt,
    $statusChangedAt: memory.statusChangedAt,
    $updatedAt: memory.updatedAt,
    $idempotencyId: idempotencyId ?? null,
  };
}

export async function insertMemory(
  transaction: RepositoryTransaction,
  memory: LocalMemoryItem,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(transaction, idempotencyId, 'memory', memory.id, 'insert', memory))) {
    return;
  }
  await transaction.runAsync(
    `INSERT INTO memory_items
       (id, type, statement, provenance, lifecycle, confidence, supersedes_id, created_at,
        confirmed_at, last_supported_at, status_changed_at, updated_at, idempotency_key)
     VALUES ($id, $type, $statement, $provenance, $lifecycle, $confidence, $supersedesId,
       $createdAt, $confirmedAt, $lastSupportedAt, $statusChangedAt, $updatedAt, $idempotencyId)`,
    memoryParams(memory, idempotencyId),
  );
}

export async function listMemorySources(
  database: RepositoryConnection,
  memoryItemId: string,
): Promise<LocalMemorySource[]> {
  const rows = await database.getAllAsync<MemorySourceRow>(
    `SELECT ${MEMORY_SOURCE_COLUMNS} FROM memory_sources
     WHERE memory_item_id = $memoryItemId
     ORDER BY CASE WHEN message_id IS NOT NULL THEN 0 ELSE 1 END, linked_at, id`,
    { $memoryItemId: memoryItemId },
  );
  return rows.map(mapSource);
}

export async function getMemory(
  database: RepositoryConnection,
  id: string,
): Promise<LocalMemoryItem | null> {
  const row = await database.getFirstAsync<MemoryRow>(
    `SELECT ${MEMORY_COLUMNS} FROM memory_items WHERE id = $id`,
    { $id: id },
  );
  if (row === null) {
    return null;
  }
  return mapMemory(row, await listMemorySources(database, id));
}

export async function updateMemory(
  transaction: RepositoryTransaction,
  memory: LocalMemoryItem,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(transaction, idempotencyId, 'memory', memory.id, 'update', memory))) {
    return;
  }
  const result = await transaction.runAsync(
    `UPDATE memory_items SET type = $type, statement = $statement, provenance = $provenance,
       lifecycle = $lifecycle, confidence = $confidence, supersedes_id = $supersedesId,
       created_at = $createdAt, confirmed_at = $confirmedAt,
       last_supported_at = $lastSupportedAt, status_changed_at = $statusChangedAt,
       updated_at = $updatedAt
     WHERE id = $id`,
    memoryParams(memory),
  );
  requireExactlyOneAffectedRow(result, 'Cannot update missing memory');
}

export async function listMemories(
  database: RepositoryConnection,
  lifecycles?: readonly MemoryLifecycle[],
): Promise<LocalMemoryItem[]> {
  const filter = lifecycleFilter('lifecycle', lifecycles);
  const rows = await database.getAllAsync<MemoryRow>(
    `SELECT ${MEMORY_COLUMNS} FROM memory_items${filter.clause}
     ORDER BY updated_at DESC, id`,
    filter.params,
  );
  return Promise.all(
    rows.map(async (row) => mapMemory(row, await listMemorySources(database, row.id))),
  );
}

export async function linkMemorySource(
  transaction: RepositoryTransaction,
  source: LocalMemorySource,
  idempotencyId: string,
): Promise<void> {
  if (!(await claimMutation(transaction, idempotencyId, 'memory-source', source.id, 'insert', source))) {
    return;
  }
  await transaction.runAsync(
    `INSERT INTO memory_sources (id, memory_item_id, message_id, evidence_id, linked_at)
     VALUES ($id, $memoryItemId, $messageId, $evidenceId, $linkedAt)`,
    {
      $id: source.id,
      $memoryItemId: source.memoryItemId,
      $messageId: source.messageId,
      $evidenceId: source.evidenceId,
      $linkedAt: source.linkedAt,
    },
  );
}
