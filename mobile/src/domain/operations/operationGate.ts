import type {
  CapabilitySnapshot,
  OperationReceipt,
  PermittedOperation,
  Project,
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
  authorization?: 'delegated' | 'user_confirmed';
  proposalId?: string;
}

export interface OperationTransaction {
  updateRecord(record: WorkRecord): Promise<void>;
  updateProject(project: Project): Promise<void>;
  linkConversation(request: OperationRequest, record: WorkRecord): Promise<void>;
  appendRecordEvent(request: OperationRequest, before: WorkRecord, after: WorkRecord): Promise<void>;
  appendProjectEvent(request: OperationRequest, before: Project, after: Project): Promise<void>;
  appendReceipt(receipt: OperationReceipt): Promise<void>;
  recordOutcome(operation: PermittedOperation, outcome: 'success'): Promise<void>;
  resolveProposal?(proposalId: string, resolvedAt: string): Promise<void>;
}

export interface OperationDependencies {
  getCapability(operation: PermittedOperation): Promise<CapabilitySnapshot | null>;
  getRecord(id: string): Promise<WorkRecord | null>;
  getProject(id: string): Promise<Project | null>;
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
        || !['waiting', 'completed', 'rescheduled', 'cancelled'].includes(payload.status as string)
      ) {
        invalidPayload();
      }
      return;
    case 'update_explicit_blocker_status':
      if (
        !hasExactKeys(payload, ['status'])
        || !['active', 'being_resolved', 'resolved', 'no_longer_relevant'].includes(payload.status as string)
      ) {
        invalidPayload();
      }
      return;
    case 'update_explicit_project_status':
      if (
        !hasExactKeys(payload, ['status'])
        || !['active', 'archived'].includes(payload.status as string)
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
  const payload = payloadObject(request);
  const common = { revision: record.revision + 1, updatedAt: request.requestedAt };
  switch (request.operation) {
    case 'complete_explicit_task':
      if (record.kind !== 'task') throw new OperationGateError('INVALID_TARGET');
      return { ...record, ...common, status: 'completed', lastConfirmedAt: request.requestedAt };
    case 'associate_existing_project':
      if (record.kind !== 'task') throw new OperationGateError('INVALID_TARGET');
      return { ...record, ...common, projectId: payload.projectId as string };
    case 'apply_strong_task_conversation_link':
      if (record.kind !== 'task') throw new OperationGateError('INVALID_TARGET');
      return { ...record, ...common };
    case 'update_explicit_followup_status':
      if (record.kind !== 'followup') throw new OperationGateError('INVALID_TARGET');
      return { ...record, ...common, status: payload.status as typeof record.status,
        lastConfirmedAt: request.requestedAt };
    case 'update_explicit_blocker_status':
      if (record.kind !== 'blocker') throw new OperationGateError('INVALID_TARGET');
      return { ...record, ...common, status: payload.status as typeof record.status,
        lastConfirmedAt: request.requestedAt };
    case 'update_explicit_project_status':
      throw new OperationGateError('INVALID_TARGET');
  }
}

function operationReceipt(
  request: OperationRequest,
  snapshot: CapabilitySnapshot,
  priorRevision: number,
  resultingRevision: number,
): OperationReceipt {
  return {
    id: request.id,
    operation: request.operation,
    targetId: request.targetId,
    sourceId: request.sourceId,
    priorRevision,
    resultingRevision,
    visibility: request.authorization === 'user_confirmed' || snapshot.state === 'trusted'
      ? 'history'
      : 'trial',
    undoable: request.operation === 'complete_explicit_task',
    undoneAt: null,
    createdAt: request.requestedAt,
  };
}

export async function executePermittedOperation(
  request: OperationRequest,
  deps: OperationDependencies,
): Promise<OperationReceipt> {
  validateOperationRequest(request);
  const snapshot = await deps.getCapability(request.operation);
  const userConfirmed = request.authorization === 'user_confirmed';
  if (!userConfirmed && !canExecute(snapshot, request.operation)) {
    throw new OperationGateError('OPERATION_NOT_PERMITTED');
  }
  if (!userConfirmed && request.ambiguity !== 'strong') {
    throw new OperationGateError('CONFIRMATION_REQUIRED');
  }

  if (request.operation === 'associate_existing_project') {
    const projectId = payloadObject(request).projectId as string;
    if (await deps.getProject(projectId) === null) {
      throw new OperationGateError('TARGET_NOT_FOUND');
    }
  }

  if (snapshot === null) throw new OperationGateError('OPERATION_NOT_PERMITTED');
  if (request.proposalId !== undefined && request.proposalId.trim().length === 0) {
    throw new OperationGateError('INVALID_PAYLOAD');
  }

  if (request.operation === 'update_explicit_project_status') {
    const currentProject = await deps.getProject(request.targetId);
    if (currentProject === null) throw new OperationGateError('TARGET_NOT_FOUND');
    if (currentProject.revision !== request.expectedRevision) {
      throw new OperationGateError('REVISION_CONFLICT');
    }
    const updatedProject: Project = {
      ...currentProject,
      status: payloadObject(request).status as Project['status'],
      revision: currentProject.revision + 1,
      updatedAt: request.requestedAt,
    };
    const receipt = operationReceipt(
      request, snapshot, currentProject.revision, updatedProject.revision,
    );
    return deps.transaction(async (transaction) => {
      await transaction.updateProject(updatedProject);
      await transaction.appendProjectEvent(request, currentProject, updatedProject);
      await transaction.appendReceipt(receipt);
      if (request.proposalId !== undefined) {
        if (transaction.resolveProposal === undefined) throw new OperationGateError('INVALID_PAYLOAD');
        await transaction.resolveProposal(request.proposalId, request.requestedAt);
      }
      await transaction.recordOutcome(request.operation, 'success');
      return receipt;
    });
  }

  const current = await deps.getRecord(request.targetId);
  if (current === null) {
    throw new OperationGateError('TARGET_NOT_FOUND');
  }
  if (current.revision !== request.expectedRevision) {
    throw new OperationGateError('REVISION_CONFLICT');
  }
  const updated = applyRecordOperation(request, current);
  const receipt = operationReceipt(request, snapshot, current.revision, updated.revision);

  return deps.transaction(async (transaction) => {
    await transaction.updateRecord(updated);
    if (request.operation === 'apply_strong_task_conversation_link') {
      await transaction.linkConversation(request, updated);
    }
    await transaction.appendRecordEvent(request, current, updated);
    await transaction.appendReceipt(receipt);
    if (request.proposalId !== undefined) {
      if (transaction.resolveProposal === undefined) throw new OperationGateError('INVALID_PAYLOAD');
      await transaction.resolveProposal(request.proposalId, request.requestedAt);
    }
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
