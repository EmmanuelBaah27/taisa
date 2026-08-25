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
  | 'INVALID_TARGET';

export class OperationGateError extends Error {
  constructor(readonly code: OperationGateErrorCode) {
    super(code);
    this.name = 'OperationGateError';
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
