import type {
  CapabilitySnapshot,
  OperationReceipt,
  PermittedOperation,
  WorkRecord,
} from '@taisa/shared';

export interface OperationRequest {
  id: string;
  operation: PermittedOperation;
  targetId: string;
  sourceId: string;
  expectedRevision: number;
  ambiguity: 'strong' | 'ambiguous';
  requestedAt: string;
  payload?: Readonly<Record<string, unknown>>;
}

export interface OperationTransaction {
  updateRecord(record: WorkRecord): Promise<void>;
  appendRecordEvent(request: OperationRequest, before: WorkRecord, after: WorkRecord): Promise<void>;
  appendReceipt(receipt: OperationReceipt): Promise<void>;
  recordOutcome(operation: PermittedOperation, outcome: 'success'): Promise<void>;
}

export interface OperationDependencies {
  getCapability(operation: PermittedOperation): Promise<CapabilitySnapshot | null>;
  getRecord(id: string): Promise<WorkRecord | null>;
  transaction<T>(work: (transaction: OperationTransaction) => Promise<T>): Promise<T>;
}

export type OperationGateErrorCode =
  | 'OPERATION_NOT_PERMITTED'
  | 'CONFIRMATION_REQUIRED'
  | 'TARGET_NOT_FOUND'
  | 'REVISION_CONFLICT'
  | 'INVALID_TARGET'
  | 'INVALID_PAYLOAD'
  | 'UNDO_NOT_AVAILABLE'
  | 'UNDO_CONFLICT';

export class OperationGateError extends Error {
  constructor(readonly code: OperationGateErrorCode) {
    super(code);
    this.name = 'OperationGateError';
  }
}

function payloadObject(request: OperationRequest): Readonly<Record<string, unknown>> {
  const payload = request.payload ?? {};
  if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) {
    throw new OperationGateError('INVALID_PAYLOAD');
  }
  return payload;
}

function hasExactKeys(payload: Readonly<Record<string, unknown>>, keys: readonly string[]): boolean {
  const actual = Object.keys(payload).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length
    && actual.every((key, index) => key === expected[index]);
}

function nonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function invalidPayload(): never {
  throw new OperationGateError('INVALID_PAYLOAD');
}

export function validateOperationRequest(request: OperationRequest): void {
  const payload = payloadObject(request);
  switch (request.operation) {
    case 'complete_explicit_task':
      if (!hasExactKeys(payload, [])) invalidPayload();
      return;
    case 'associate_existing_project':
      if (!hasExactKeys(payload, ['projectId']) || !nonEmptyString(payload.projectId)) {
        invalidPayload();
      }
      return;
    case 'apply_strong_task_conversation_link':
      if (
        !hasExactKeys(payload, ['conversationId', 'contribution'])
        || !nonEmptyString(payload.conversationId)
        || !['planning', 'status', 'blocker', 'decision', 'outcome', 'evidence']
          .includes(payload.contribution as string)
      ) {
        invalidPayload();
      }
      return;
    case 'update_explicit_followup_status':
      if (
        !hasExactKeys(payload, ['status'])
        || !['open', 'completed', 'cancelled'].includes(payload.status as string)
      ) {
        invalidPayload();
      }
      return;
    case 'update_explicit_blocker_status':
      if (
        !hasExactKeys(payload, ['status'])
        || !['open', 'resolved'].includes(payload.status as string)
      ) {
        invalidPayload();
      }
      return;
    case 'update_explicit_project_status':
      if (
        !hasExactKeys(payload, ['status'])
        || !['active', 'paused', 'completed', 'archived'].includes(payload.status as string)
      ) {
        invalidPayload();
      }
      return;
  }
}

function canExecute(snapshot: CapabilitySnapshot | null, operation: PermittedOperation): boolean {
  return snapshot?.operation === operation
    && snapshot.permissionGrantedAt !== null
    && ['permission_granted', 'trial', 'trusted'].includes(snapshot.state);
}

function applyRecordOperation(request: OperationRequest, record: WorkRecord): WorkRecord {
  if (request.operation !== 'complete_explicit_task' || record.kind !== 'task') {
    throw new OperationGateError('INVALID_TARGET');
  }
  return {
    ...record,
    status: 'completed',
    revision: record.revision + 1,
    updatedAt: request.requestedAt,
    lastConfirmedAt: request.requestedAt,
  };
}

export async function executePermittedOperation(
  request: OperationRequest,
  deps: OperationDependencies,
): Promise<OperationReceipt> {
  validateOperationRequest(request);
  const snapshot = await deps.getCapability(request.operation);
  if (!canExecute(snapshot, request.operation)) {
    throw new OperationGateError('OPERATION_NOT_PERMITTED');
  }
  if (request.ambiguity !== 'strong') {
    throw new OperationGateError('CONFIRMATION_REQUIRED');
  }

  const current = await deps.getRecord(request.targetId);
  if (current === null) {
    throw new OperationGateError('TARGET_NOT_FOUND');
  }
  if (current.revision !== request.expectedRevision) {
    throw new OperationGateError('REVISION_CONFLICT');
  }
  const updated = applyRecordOperation(request, current);
  const visibility = snapshot?.state === 'trusted' ? 'history' : 'trial';
  const receipt: OperationReceipt = {
    id: request.id,
    operation: request.operation,
    targetId: request.targetId,
    sourceId: request.sourceId,
    priorRevision: current.revision,
    resultingRevision: updated.revision,
    visibility,
    undoable: request.operation === 'complete_explicit_task',
    undoneAt: null,
    createdAt: request.requestedAt,
  };

  return deps.transaction(async (transaction) => {
    await transaction.updateRecord(updated);
    await transaction.appendRecordEvent(request, current, updated);
    await transaction.appendReceipt(receipt);
    await transaction.recordOutcome(request.operation, 'success');
    return receipt;
  });
}

export interface UndoTransaction {
  restoreRecord(record: WorkRecord): Promise<void>;
  appendUndoEvent(original: OperationReceipt, restored: WorkRecord): Promise<void>;
  markReceiptUndone(receiptId: string, undoneAt: string): Promise<void>;
  recordCorrection(operation: PermittedOperation): Promise<void>;
}

export interface UndoDependencies {
  getReceipt(id: string): Promise<OperationReceipt | null>;
  getRecord(id: string): Promise<WorkRecord | null>;
  getPriorRecord(receiptId: string): Promise<WorkRecord | null>;
  transaction<T>(work: (transaction: UndoTransaction) => Promise<T>): Promise<T>;
}

export async function undoOperation(
  receiptId: string,
  now: string,
  deps: UndoDependencies,
): Promise<OperationReceipt> {
  const original = await deps.getReceipt(receiptId);
  if (original === null || !original.undoable || original.undoneAt !== null) {
    throw new OperationGateError('UNDO_NOT_AVAILABLE');
  }

  const [current, prior] = await Promise.all([
    deps.getRecord(original.targetId),
    deps.getPriorRecord(receiptId),
  ]);
  if (current === null || prior === null || current.revision !== original.resultingRevision) {
    throw new OperationGateError('UNDO_CONFLICT');
  }

  const restored: WorkRecord = {
    ...prior,
    revision: current.revision + 1,
    updatedAt: now,
    lastConfirmedAt: now,
  };
  const receipt: OperationReceipt = {
    id: `${original.id}:undo`,
    operation: original.operation,
    targetId: original.targetId,
    sourceId: original.sourceId,
    priorRevision: current.revision,
    resultingRevision: restored.revision,
    visibility: 'history',
    undoable: false,
    undoneAt: null,
    createdAt: now,
  };

  return deps.transaction(async (transaction) => {
    await transaction.restoreRecord(restored);
    await transaction.appendUndoEvent(original, restored);
    await transaction.markReceiptUndone(original.id, now);
    await transaction.recordCorrection(original.operation);
    return receipt;
  });
}
