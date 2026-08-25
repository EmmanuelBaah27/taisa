import type { WorkRecord } from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';

interface WorkRecordRow {
  id: string;
  kind: WorkRecord['kind'];
  title: string;
  project_id: string | null;
  status: WorkRecord['status'];
  freshness: WorkRecord['freshness'];
  planned_week: string | null;
  planned_day: string | null;
  source_id: string;
  revision: number;
  created_at: string;
  updated_at: string;
  last_confirmed_at: string | null;
}

const COLUMNS = `id, kind, title, project_id, status, freshness, planned_week,
  planned_day, source_id, revision, created_at, updated_at, last_confirmed_at`;

function mapWorkRecord(row: WorkRecordRow): WorkRecord {
  return {
    id: row.id,
    kind: row.kind,
    title: row.title,
    projectId: row.project_id,
    status: row.status,
    freshness: row.freshness,
    plannedWeek: row.planned_week,
    plannedDay: row.planned_day,
    sourceId: row.source_id,
    revision: row.revision,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    lastConfirmedAt: row.last_confirmed_at,
  };
}

function workRecordParams(record: WorkRecord, idempotencyId: string) {
  return {
    $id: record.id,
    $kind: record.kind,
    $title: record.title,
    $projectId: record.projectId,
    $status: record.status,
    $freshness: record.freshness,
    $plannedWeek: record.plannedWeek,
    $plannedDay: record.plannedDay,
    $sourceId: record.sourceId,
    $revision: record.revision,
    $createdAt: record.createdAt,
    $updatedAt: record.updatedAt,
    $lastConfirmedAt: record.lastConfirmedAt,
    $idempotencyId: idempotencyId,
  };
}

export interface WorkRepository {
  get(id: string): Promise<WorkRecord | null>;
  insert(transaction: RepositoryTransaction, record: WorkRecord, idempotencyId: string): Promise<void>;
}

export function createWorkRepository(database: RepositoryConnection): WorkRepository {
  return {
    async get(id) {
      const row = await database.getFirstAsync<WorkRecordRow>(
        `SELECT ${COLUMNS} FROM work_records WHERE id = $id`,
        { $id: id },
      );
      return row === null ? null : mapWorkRecord(row);
    },

    async insert(transaction, record, idempotencyId) {
      await transaction.runAsync(
        `INSERT INTO work_records
          (id, kind, title, project_id, status, freshness, planned_week, planned_day,
           source_id, revision, created_at, updated_at, last_confirmed_at, idempotency_key)
         VALUES ($id, $kind, $title, $projectId, $status, $freshness, $plannedWeek,
           $plannedDay, $sourceId, $revision, $createdAt, $updatedAt,
           $lastConfirmedAt, $idempotencyId)`,
        workRecordParams(record, idempotencyId),
      );
    },
  };
}
