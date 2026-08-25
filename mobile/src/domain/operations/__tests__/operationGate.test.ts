import type { CapabilitySnapshot, OperationReceipt, WorkRecord } from '@taisa/shared';

import {
  executePermittedOperation,
  undoOperation,
  OperationGateError,
  validateOperationRequest,
  type OperationDependencies,
  type OperationRequest,
  type UndoDependencies,
} from '../operationGate';

const task: WorkRecord = {
  id: 'task-1', kind: 'task', title: 'Send proposal', projectId: null,
  status: 'open', freshness: 'current', plannedWeek: null, plannedDay: null,
  sourceId: 'conversation-1', revision: 3,
  createdAt: '2026-08-25T08:00:00Z', updatedAt: '2026-08-25T08:00:00Z',
  lastConfirmedAt: '2026-08-25T08:00:00Z',
};

function capability(
  operation: CapabilitySnapshot['operation'],
  state: CapabilitySnapshot['state'] = 'trusted',
): CapabilitySnapshot {
  return {
    operation, policyVersion: 1, state, permissionGrantedAt: '2026-08-24T08:00:00Z',
    relevantExamples: 8, corrections: 0, contradictions: 0,
    latestEvidenceAt: '2026-08-25T08:00:00Z', cleanTrialOutcomes: 5,
    updatedAt: '2026-08-25T08:00:00Z',
  };
}

function request(overrides: Partial<OperationRequest> = {}): OperationRequest {
  return {
    id: 'operation-1', operation: 'complete_explicit_task', targetId: 'task-1',
    sourceId: 'conversation-1', expectedRevision: 3, ambiguity: 'strong',
    requestedAt: '2026-08-25T09:00:00Z', ...overrides,
  } as OperationRequest;
}

function dependencies(snapshot: CapabilitySnapshot, record: WorkRecord = task) {
  const writes: string[] = [];
  const receipts: OperationReceipt[] = [];
  const deps: OperationDependencies = {
    getCapability: async () => snapshot,
    getRecord: async () => record,
    transaction: async (work) => work({
      updateRecord: async () => { writes.push('record'); },
      appendRecordEvent: async () => { writes.push('event'); },
      appendReceipt: async (receipt) => { writes.push('receipt'); receipts.push(receipt); },
      recordOutcome: async () => { writes.push('outcome'); },
    }),
  };
  return { deps, writes, receipts };
}

test('permission is exact and cannot authorize an adjacent mutation', async () => {
  const { deps, writes } = dependencies(capability('associate_existing_project'));

  await expect(executePermittedOperation(request(), deps)).rejects.toMatchObject({
    code: 'OPERATION_NOT_PERMITTED',
  });
  expect(writes).toEqual([]);
});

test('revision conflict is atomic and records no successful outcome', async () => {
  const { deps, writes } = dependencies(capability('complete_explicit_task'));

  await expect(executePermittedOperation(request({ expectedRevision: 2 }), deps))
    .rejects.toMatchObject({ code: 'REVISION_CONFLICT' });
  expect(writes).toEqual([]);
});

test('ambiguous language returns to Ask me before mutation', async () => {
  const { deps, writes } = dependencies(capability('complete_explicit_task'));

  await expect(executePermittedOperation(request({ ambiguity: 'ambiguous' }), deps))
    .rejects.toBeInstanceOf(OperationGateError);
  await expect(executePermittedOperation(request({ ambiguity: 'ambiguous' }), deps))
    .rejects.toMatchObject({ code: 'CONFIRMATION_REQUIRED' });
  expect(writes).toEqual([]);
});

test('Trial execution emits a visible undoable receipt in one transaction', async () => {
  const { deps, writes, receipts } = dependencies(capability('complete_explicit_task', 'trial'));

  await expect(executePermittedOperation(request(), deps)).resolves.toMatchObject({
    visibility: 'trial', undoable: true, priorRevision: 3, resultingRevision: 4,
  });
  expect(writes).toEqual(['record', 'event', 'receipt', 'outcome']);
  expect(receipts).toHaveLength(1);
});

test.each<OperationRequest>([
  request({ operation: 'complete_explicit_task', payload: {} }),
  request({ operation: 'associate_existing_project', payload: { projectId: 'project-1' } }),
  request({
    operation: 'apply_strong_task_conversation_link',
    payload: { conversationId: 'conversation-2', contribution: 'planning' },
  }),
  request({ operation: 'update_explicit_followup_status', payload: { status: 'completed' } }),
  request({ operation: 'update_explicit_blocker_status', payload: { status: 'resolved' } }),
  request({ operation: 'update_explicit_project_status', payload: { status: 'paused' } }),
])('accepts the exact payload for $operation', (candidate) => {
  expect(() => validateOperationRequest(candidate)).not.toThrow();
});

test.each<OperationRequest>([
  request({ operation: 'complete_explicit_task', payload: { status: 'completed' } }),
  request({ operation: 'associate_existing_project', payload: { projectId: '' } }),
  request({
    operation: 'apply_strong_task_conversation_link',
    payload: { conversationId: 'conversation-2', contribution: 'owner' },
  }),
  request({ operation: 'update_explicit_followup_status', payload: { status: 'resolved' } }),
  request({ operation: 'update_explicit_blocker_status', payload: { status: 'completed' } }),
  request({
    operation: 'update_explicit_project_status',
    payload: { status: 'paused', recordId: 'task-1' },
  }),
])('rejects malformed or adjacent payloads for $operation', (candidate) => {
  expect(() => validateOperationRequest(candidate)).toThrowError(
    expect.objectContaining({ code: 'INVALID_PAYLOAD' }),
  );
});

function undoDependencies(currentRevision: number) {
  const writes: string[] = [];
  const original: OperationReceipt = {
    id: 'operation-1', operation: 'complete_explicit_task', targetId: 'task-1',
    sourceId: 'conversation-1', priorRevision: 3, resultingRevision: 4,
    visibility: 'trial', undoable: true, undoneAt: null,
    createdAt: '2026-08-25T09:00:00Z',
  };
  const deps: UndoDependencies = {
    getReceipt: async () => original,
    getRecord: async () => ({ ...task, status: 'completed', revision: currentRevision }),
    getPriorRecord: async () => task,
    transaction: async (work) => work({
      restoreRecord: async () => { writes.push('record'); },
      appendUndoEvent: async () => { writes.push('event'); },
      markReceiptUndone: async () => { writes.push('receipt'); },
      recordCorrection: async () => { writes.push('correction'); },
    }),
  };
  return { deps, writes };
}

test('Undo restores an unchanged target and records a correction atomically', async () => {
  const { deps, writes } = undoDependencies(4);

  await expect(undoOperation('operation-1', '2026-08-25T10:00:00Z', deps))
    .resolves.toMatchObject({ priorRevision: 4, resultingRevision: 5, undoable: false });
  expect(writes).toEqual(['record', 'event', 'receipt', 'correction']);
});

test('Undo refuses a target changed after the operation and writes nothing', async () => {
  const { deps, writes } = undoDependencies(5);

  await expect(undoOperation('operation-1', '2026-08-25T10:00:00Z', deps))
    .rejects.toMatchObject({ code: 'UNDO_CONFLICT' });
  expect(writes).toEqual([]);
});
