import type {
  CapabilitySnapshot,
  OperationReceipt,
  PermittedOperation,
  Project,
  WorkRecord,
} from '@taisa/shared';

import type { ExclusiveTransactionConnection, RepositoryTransaction } from '../db/types';
import { withRepositoryTransaction } from '../db/types';
import {
  executePermittedOperation,
  type OperationDependencies,
  type OperationRequest,
  type OperationTransaction,
  type UndoDependencies,
  type UndoTransaction,
  undoOperation,
} from '../domain/operations/operationGate';
import { READINESS_POLICIES_V1 } from '../domain/readiness/policies';
import { recordOperationOutcome, reconcileCapability } from '../domain/readiness/readinessPolicy';
import { createReadinessRepository } from '../repositories/readinessRepository';
import { createWorkRepository } from '../repositories/workRepository';

type ProjectRow = {
  id: string; name: string; status: Project['status']; source_id: string; revision: number;
  created_at: string; updated_at: string;
};
type CapabilityRow = {
  operation: PermittedOperation; policy_version: number; state: CapabilitySnapshot['state'];
  permission_granted_at: string | null; relevant_examples: number; corrections: number;
  contradictions: number; latest_evidence_at: string | null; clean_trial_outcomes: number;
  updated_at: string;
};
type ReceiptRow = {
  id: string; operation: PermittedOperation; target_id: string; source_id: string;
  prior_revision: number; resulting_revision: number; visibility: OperationReceipt['visibility'];
  undoable: number; undone_at: string | null; created_at: string;
};

function capability(row: CapabilityRow | null): CapabilitySnapshot | null {
  return row === null ? null : {
    operation: row.operation, policyVersion: row.policy_version, state: row.state,
    permissionGrantedAt: row.permission_granted_at, relevantExamples: row.relevant_examples,
    corrections: row.corrections, contradictions: row.contradictions,
    latestEvidenceAt: row.latest_evidence_at, cleanTrialOutcomes: row.clean_trial_outcomes,
    updatedAt: row.updated_at,
  };
}

function receipt(row: ReceiptRow | null): OperationReceipt | null {
  return row === null ? null : {
    id: row.id, operation: row.operation, targetId: row.target_id, sourceId: row.source_id,
    priorRevision: row.prior_revision, resultingRevision: row.resulting_revision,
    visibility: row.visibility, undoable: row.undoable === 1, undoneAt: row.undone_at,
    createdAt: row.created_at,
  };
}

async function getCapability(database: ExclusiveTransactionConnection, operation: PermittedOperation) {
  return capability(await database.getFirstAsync<CapabilityRow>(
    `SELECT operation, policy_version, state, permission_granted_at, relevant_examples,
       corrections, contradictions, latest_evidence_at, clean_trial_outcomes, updated_at
     FROM capability_states WHERE operation = $operation`, { $operation: operation },
  ));
}

async function getProject(database: ExclusiveTransactionConnection, id: string): Promise<Project | null> {
  const row = await database.getFirstAsync<ProjectRow>(
    `SELECT id, name, status, source_id, revision, created_at, updated_at
     FROM projects WHERE id = $id`, { $id: id },
  );
  return row === null ? null : {
    id: row.id, name: row.name, status: row.status, sourceId: row.source_id,
    revision: row.revision, createdAt: row.created_at, updatedAt: row.updated_at,
  };
}

async function updateCapabilityOutcome(
  transaction: RepositoryTransaction,
  operation: PermittedOperation,
  outcome: 'success' | 'correction',
  now: string,
) {
  const current = await getCapability(transaction as unknown as ExclusiveTransactionConnection, operation);
  if (current === null) throw new Error('Missing capability state');
  const observed = recordOperationOutcome(current, outcome, now);
  const next = reconcileCapability(READINESS_POLICIES_V1[operation], observed, now);
  await createReadinessRepository(transaction).put(transaction, next);
}

function operationTransaction(transaction: RepositoryTransaction, occurredAt: string): OperationTransaction {
  return {
    async updateRecord(record) {
      await transaction.runAsync(
        `UPDATE work_records SET title = $title, project_id = $projectId, status = $status,
           freshness = $freshness, planned_week = $plannedWeek, planned_day = $plannedDay,
           revision = $revision, updated_at = $updatedAt, last_confirmed_at = $lastConfirmedAt
         WHERE id = $id AND revision = $priorRevision`,
        { $id: record.id, $title: record.title, $projectId: record.projectId, $status: record.status,
          $freshness: record.freshness, $plannedWeek: record.plannedWeek, $plannedDay: record.plannedDay,
          $revision: record.revision, $updatedAt: record.updatedAt,
          $lastConfirmedAt: record.lastConfirmedAt, $priorRevision: record.revision - 1 },
      );
    },
    async updateProject(project) {
      await transaction.runAsync(
        `UPDATE projects SET status = $status, revision = $revision, updated_at = $updatedAt
         WHERE id = $id AND revision = $priorRevision`,
        { $id: project.id, $status: project.status, $revision: project.revision,
          $updatedAt: project.updatedAt, $priorRevision: project.revision - 1 },
      );
    },
    async linkConversation(request) {
      await transaction.runAsync(
        `INSERT INTO work_relationships
          (id, record_id, conversation_id, role, contribution, source_revision, created_at, idempotency_key)
         VALUES ($id, $recordId, $conversationId, 'supporting', $contribution,
           $sourceRevision, $createdAt, $idempotencyId)`,
        { $id: `${request.id}:link`, $recordId: request.targetId,
          $conversationId: request.payload?.conversationId as string,
          $contribution: request.payload?.contribution as string,
          $sourceRevision: request.expectedRevision, $createdAt: request.requestedAt,
          $idempotencyId: `${request.id}:link` },
      );
    },
    async appendRecordEvent(request, before, after) {
      await transaction.runAsync(
        `INSERT INTO record_events
          (id, record_id, operation, prior_value_json, resulting_value_json, source_id,
           occurred_at, idempotency_key)
         VALUES ($id, $recordId, $operation, $prior, $result, $sourceId, $occurredAt, $key)`,
        { $id: `${request.id}:record`, $recordId: request.targetId, $operation: request.operation,
          $prior: JSON.stringify(before), $result: JSON.stringify(after), $sourceId: request.sourceId,
          $occurredAt: request.requestedAt, $key: request.id },
      );
    },
    async appendProjectEvent() {
      // Project changes are audited by the operation_events receipt appended in this transaction.
      // record_events is intentionally FK-scoped to work_records and cannot hold project IDs.
    },
    async appendReceipt(value) {
      await transaction.runAsync(
        `INSERT INTO operation_events
          (id, operation, target_id, source_id, prior_revision, resulting_revision,
           visibility, undoable, undone_at, created_at, idempotency_key)
         VALUES ($id, $operation, $targetId, $sourceId, $priorRevision, $resultingRevision,
           $visibility, $undoable, $undoneAt, $createdAt, $key)`,
        { $id: value.id, $operation: value.operation, $targetId: value.targetId,
          $sourceId: value.sourceId, $priorRevision: value.priorRevision,
          $resultingRevision: value.resultingRevision, $visibility: value.visibility,
          $undoable: value.undoable ? 1 : 0, $undoneAt: value.undoneAt,
          $createdAt: value.createdAt, $key: value.id },
      );
    },
    recordOutcome: (operation) => updateCapabilityOutcome(transaction, operation, 'success', occurredAt),
  };
}

export function createHomeOperationService(database: ExclusiveTransactionConnection) {
  const work = createWorkRepository(database);
  const undoDependencies = (undoneAt: string): UndoDependencies => ({
    getReceipt: async (id) => receipt(await database.getFirstAsync<ReceiptRow>(
      `SELECT id, operation, target_id, source_id, prior_revision, resulting_revision,
         visibility, undoable, undone_at, created_at FROM operation_events WHERE id = $id`, { $id: id },
    )),
    getRecord: (id) => work.get(id),
    getPriorRecord: async (id) => {
      const row = await database.getFirstAsync<{ prior_value_json: string | null }>(
        `SELECT prior_value_json FROM record_events WHERE idempotency_key = $id`, { $id: id },
      );
      return row?.prior_value_json ? JSON.parse(row.prior_value_json) as WorkRecord : null;
    },
    transaction: (run) => withRepositoryTransaction(database, async (tx) => run({
      async restoreRecord(record) { await operationTransaction(tx, undoneAt).updateRecord(record); },
      async appendUndoEvent(original, restored) {
        await tx.runAsync(
          `INSERT INTO record_events
            (id, record_id, operation, prior_value_json, resulting_value_json, source_id,
             occurred_at, idempotency_key)
           VALUES ($id, $recordId, 'undo', NULL, $result, $sourceId, $occurredAt, $key)`,
          { $id: `${original.id}:undo`, $recordId: original.targetId, $result: JSON.stringify(restored),
            $sourceId: original.sourceId, $occurredAt: restored.updatedAt, $key: `${original.id}:undo` },
        );
      },
      async markReceiptUndone(id, undoneAt) {
        await tx.runAsync(`UPDATE operation_events SET undone_at = $undoneAt WHERE id = $id`, { $id: id, $undoneAt: undoneAt });
      },
      recordCorrection: (operation) => updateCapabilityOutcome(tx, operation, 'correction', undoneAt),
    } as UndoTransaction)),
  });
  return {
    execute: (request: OperationRequest) => executePermittedOperation(request, {
      getCapability: (operation) => getCapability(database, operation),
      getRecord: (id) => work.get(id),
      getProject: (id) => getProject(database, id),
      transaction: (run) => withRepositoryTransaction(
        database,
        (tx) => run(operationTransaction(tx, request.requestedAt)),
      ),
    }),
    undo: (receiptId: string, now: string) => undoOperation(receiptId, now, undoDependencies(now)),
  };
}
