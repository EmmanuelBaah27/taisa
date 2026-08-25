import type { Project, WorkRecord, WorkRelationship } from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';
import { requireExactlyOneAffectedRow } from './mutationReceipt';

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

interface RecordEventRow {
  id: string;
  record_id: string;
  operation: string;
  prior_value_json: string | null;
  resulting_value_json: string;
  source_id: string;
  occurred_at: string;
  idempotency_key: string;
}

export interface RecordEvent {
  id: string;
  recordId: string;
  operation: string;
  priorValue: unknown;
  resultingValue: unknown;
  sourceId: string;
  occurredAt: string;
  idempotencyId: string;
}

export interface WorkRepository {
  get(id: string): Promise<WorkRecord | null>;
  insert(transaction: RepositoryTransaction, record: WorkRecord, idempotencyId: string): Promise<void>;
  insertProject(transaction: RepositoryTransaction, project: Project, idempotencyId: string): Promise<void>;
  linkConversation(transaction: RepositoryTransaction, relationship: WorkRelationship, idempotencyId: string): Promise<void>;
  listEvents(recordId: string): Promise<RecordEvent[]>;
  moveToWeek(
    transaction: RepositoryTransaction,
    id: string,
    plannedWeek: string | null,
    event: { id: string; sourceId: string; occurredAt: string; idempotencyId: string },
  ): Promise<void>;
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

    async insertProject(transaction, project, idempotencyId) {
      await transaction.runAsync(
        `INSERT INTO projects
          (id, name, status, source_id, revision, created_at, updated_at, idempotency_key)
         VALUES ($id, $name, $status, $sourceId, $revision, $createdAt, $updatedAt, $idempotencyId)`,
        {
          $id: project.id, $name: project.name, $status: project.status,
          $sourceId: project.sourceId, $revision: project.revision,
          $createdAt: project.createdAt, $updatedAt: project.updatedAt,
          $idempotencyId: idempotencyId,
        },
      );
    },

    async linkConversation(transaction, relationship, idempotencyId) {
      await transaction.runAsync(
        `INSERT INTO work_relationships
          (id, record_id, conversation_id, role, contribution, source_revision,
           created_at, idempotency_key)
         VALUES ($id, $recordId, $conversationId, $role, $contribution,
           $sourceRevision, $createdAt, $idempotencyId)`,
        {
          $id: relationship.id, $recordId: relationship.recordId,
          $conversationId: relationship.conversationId, $role: relationship.role,
          $contribution: relationship.contribution, $sourceRevision: relationship.sourceRevision,
          $createdAt: relationship.createdAt, $idempotencyId: idempotencyId,
        },
      );
    },

    async listEvents(recordId) {
      const rows = await database.getAllAsync<RecordEventRow>(
        `SELECT id, record_id, operation, prior_value_json, resulting_value_json,
           source_id, occurred_at, idempotency_key
         FROM record_events WHERE record_id = $recordId ORDER BY occurred_at, id`,
        { $recordId: recordId },
      );
      return rows.map((row) => ({
        id: row.id,
        recordId: row.record_id,
        operation: row.operation,
        priorValue: row.prior_value_json === null ? null : JSON.parse(row.prior_value_json),
        resultingValue: JSON.parse(row.resulting_value_json),
        sourceId: row.source_id,
        occurredAt: row.occurred_at,
        idempotencyId: row.idempotency_key,
      }));
    },

    async moveToWeek(transaction, id, plannedWeek, event) {
      const currentRow = await transaction.getFirstAsync<WorkRecordRow>(
        `SELECT ${COLUMNS} FROM work_records WHERE id = $id`,
        { $id: id },
      );
      if (currentRow === null) {
        throw new Error('Cannot move missing work record');
      }

      const update = await transaction.runAsync(
        `UPDATE work_records
         SET planned_week = $plannedWeek, revision = revision + 1, updated_at = $occurredAt
         WHERE id = $id AND revision = $expectedRevision`,
        {
          $id: id,
          $plannedWeek: plannedWeek,
          $occurredAt: event.occurredAt,
          $expectedRevision: currentRow.revision,
        },
      );
      requireExactlyOneAffectedRow(update, 'Work record revision conflict');

      await transaction.runAsync(
        `INSERT INTO record_events
          (id, record_id, operation, prior_value_json, resulting_value_json,
           source_id, occurred_at, idempotency_key)
         VALUES ($eventId, $recordId, 'move_week', $priorValueJson,
           $resultingValueJson, $sourceId, $occurredAt, $idempotencyId)`,
        {
          $eventId: event.id,
          $recordId: id,
          $priorValueJson: JSON.stringify(currentRow.planned_week),
          $resultingValueJson: JSON.stringify(plannedWeek),
          $sourceId: event.sourceId,
          $occurredAt: event.occurredAt,
          $idempotencyId: event.idempotencyId,
        },
      );
    },
  };
}
