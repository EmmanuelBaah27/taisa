import type { CapabilitySnapshot, OperationReceipt, WorkRecord } from '@taisa/shared';

import {
  executePermittedOperation,
  OperationGateError,
  type OperationDependencies,
  type OperationRequest,
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
