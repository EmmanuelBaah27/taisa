import type { CapabilitySnapshot, OperationReceipt, Project, WorkRecord } from '@taisa/shared';

import {
  executePermittedOperation,
  undoOperation,
  OperationGateError,
  validateOperationRequest,
  type OperationDependencies,
  type OperationRequest,
  type UndoDependencies,
} from '../operationGate';

const task: Extract<WorkRecord, { kind: 'task' }> = {
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
  const recordUpdates: WorkRecord[] = [];
  const projectUpdates: Project[] = [];
  const project: Project = {
    id: 'project-1', name: 'Website Launch', status: 'active', sourceId: 'conversation-1',
    revision: 2, createdAt: '2026-08-25T08:00:00Z', updatedAt: '2026-08-25T08:00:00Z',
  };
  const deps: OperationDependencies = {
    getCapability: async () => snapshot,
    getRecord: async () => record,
    getProject: async () => project,
    transaction: async (work) => work({
      updateRecord: async (updated) => { writes.push('record'); recordUpdates.push(updated); },
      updateProject: async (updated) => { writes.push('project'); projectUpdates.push(updated); },
      linkConversation: async () => { writes.push('relationship'); },
      appendRecordEvent: async () => { writes.push('event'); },
      appendProjectEvent: async () => { writes.push('project_event'); },
      appendReceipt: async (receipt) => { writes.push('receipt'); receipts.push(receipt); },
      resolveProposal: async () => { writes.push('proposal'); },
      recordOutcome: async () => { writes.push('outcome'); },
    }),
  };
  return { deps, writes, receipts, recordUpdates, projectUpdates };
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

test('explicit user confirmation applies one proposal without delegated permission', async () => {
  const snapshot = { ...capability('complete_explicit_task', 'learning'), permissionGrantedAt: null };
  const { deps, writes } = dependencies(snapshot);

  const receipt = await executePermittedOperation(request({
    ambiguity: 'ambiguous', authorization: 'user_confirmed', proposalId: 'proposal-1',
  }), deps);

  expect(receipt.visibility).toBe('history');
  expect(writes).toEqual(['record', 'event', 'receipt', 'proposal', 'outcome']);
});

test('Trial execution emits a visible undoable receipt in one transaction', async () => {
  const { deps, writes, receipts } = dependencies(capability('complete_explicit_task', 'trial'));

  await expect(executePermittedOperation(request(), deps)).resolves.toMatchObject({
    visibility: 'trial', undoable: true, priorRevision: 3, resultingRevision: 4,
  });
  expect(writes).toEqual(['record', 'event', 'receipt', 'outcome']);
  expect(receipts).toHaveLength(1);
});

test.each([
  {
    operation: 'associate_existing_project' as const,
    record: task,
    payload: { projectId: 'project-1' },
    expected: { projectId: 'project-1', revision: 4 },
    writes: ['record', 'event', 'receipt', 'outcome'],
  },
  {
    operation: 'apply_strong_task_conversation_link' as const,
    record: task,
    payload: { conversationId: 'conversation-2', contribution: 'planning', expectedConversationRevision: 1 },
    expected: { revision: 4 },
    writes: ['record', 'relationship', 'event', 'receipt', 'outcome'],
  },
  {
    operation: 'update_explicit_followup_status' as const,
    record: { ...task, kind: 'followup' as const, status: 'waiting' as const },
    payload: { status: 'completed' },
    expected: { status: 'completed', revision: 4 },
    writes: ['record', 'event', 'receipt', 'outcome'],
  },
  {
    operation: 'update_explicit_blocker_status' as const,
    record: { ...task, kind: 'blocker' as const, status: 'active' as const },
    payload: { status: 'resolved' },
    expected: { status: 'resolved', revision: 4 },
    writes: ['record', 'event', 'receipt', 'outcome'],
  },
])('$operation applies its exact record mutation atomically', async ({
  operation, record, payload, expected, writes: expectedWrites,
}) => {
  const { deps, writes, recordUpdates } = dependencies(capability(operation), record);

  await executePermittedOperation(request({ operation, payload }), deps);

  expect(recordUpdates.at(-1)).toEqual(expect.objectContaining(expected));
  expect(writes).toEqual(expectedWrites);
});

test('project status updates the project revision without mutating a work record', async () => {
  const operation = 'update_explicit_project_status' as const;
  const { deps, writes, recordUpdates, projectUpdates } = dependencies(capability(operation));

  await executePermittedOperation(request({
    operation,
    targetId: 'project-1',
    expectedRevision: 2,
    payload: { status: 'archived' },
  }), deps);

  expect(recordUpdates).toEqual([]);
  expect(projectUpdates.at(-1)).toEqual(expect.objectContaining({ status: 'archived', revision: 3 }));
  expect(writes).toEqual(['project', 'project_event', 'receipt', 'outcome']);
});

test('project association rejects an unknown project before writing', async () => {
  const operation = 'associate_existing_project' as const;
  const { deps, writes } = dependencies(capability(operation));
  deps.getProject = async () => null;

  await expect(executePermittedOperation(request({
    operation,
    payload: { projectId: 'missing-project' },
  }), deps)).rejects.toMatchObject({ code: 'TARGET_NOT_FOUND' });
  expect(writes).toEqual([]);
});

test.each<OperationRequest>([
  request({ operation: 'complete_explicit_task', payload: {} }),
  request({ operation: 'associate_existing_project', payload: { projectId: 'project-1' } }),
  request({
    operation: 'apply_strong_task_conversation_link',
    payload: { conversationId: 'conversation-2', contribution: 'planning', expectedConversationRevision: 1 },
  }),
  request({ operation: 'update_explicit_followup_status', payload: { status: 'completed' } }),
  request({ operation: 'update_explicit_blocker_status', payload: { status: 'resolved' } }),
  request({ operation: 'update_explicit_project_status', payload: { status: 'archived' } }),
])('accepts the exact payload for $operation', (candidate) => {
  expect(() => validateOperationRequest(candidate)).not.toThrow();
});

test.each<OperationRequest>([
  request({ operation: 'complete_explicit_task', payload: { status: 'completed' } }),
  request({ operation: 'associate_existing_project', payload: { projectId: '' } }),
  request({
    operation: 'apply_strong_task_conversation_link',
    payload: { conversationId: 'conversation-2', contribution: 'owner', expectedConversationRevision: 1 },
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
