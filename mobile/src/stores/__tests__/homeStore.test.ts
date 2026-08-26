import type {
  CapabilitySnapshot,
  HomeView,
  Insight,
  ProposalEnvelope,
  WeeklyPeriod,
  WorkRecord,
} from '@taisa/shared';

import { createHomeStore } from '../homeStore';
import { createGovernanceStore } from '../governanceStore';

const period: WeeklyPeriod = {
  id: 'week-2026-08-24', startsOn: '2026-08-24', endsOn: '2026-08-30',
  state: 'open', reviewedAt: null, closedAt: null,
};

const record: WorkRecord = {
  id: 'task-1', kind: 'task', title: 'Send proposal', projectId: null,
  status: 'open', freshness: 'current', plannedWeek: period.startsOn, plannedDay: null,
  sourceId: 'conversation-1', revision: 1, createdAt: '2026-08-25T08:00:00Z',
  updatedAt: '2026-08-25T08:00:00Z', lastConfirmedAt: '2026-08-25T08:00:00Z',
};

const insight: Insight = {
  id: 'insight-1', kind: 'operational', title: 'One priority', body: 'Send it.',
  freshness: 'current', evidence: [], createdAt: '2026-08-25T08:00:00Z',
  updatedAt: '2026-08-25T08:00:00Z',
};

const proposal = {
  id: 'proposal-1', type: 'work_record', sourceId: 'conversation-1', sourceRevision: 1,
  evidenceIds: ['evidence-1'], evidenceFingerprint: 'fingerprint', reasoning: 'Explicit task',
  effect: { kind: 'task', title: 'Send proposal', projectId: null }, ambiguity: 'strong', admission: 'pending',
  resolution: 'unapplied', revalidation: 'valid', createdAt: '2026-08-25T08:00:00Z',
  updatedAt: '2026-08-25T08:00:00Z',
} satisfies ProposalEnvelope<'work_record'>;

const capability: CapabilitySnapshot = {
  operation: 'complete_explicit_task', policyVersion: 1, state: 'ready',
  permissionGrantedAt: null, relevantExamples: 8, corrections: 0, contradictions: 0,
  latestEvidenceAt: '2026-08-25T08:00:00Z', cleanTrialOutcomes: 0,
  updatedAt: '2026-08-25T08:00:00Z',
};

test('Home hydration is local-only and replaces stale view state on reload', async () => {
  const load = jest.fn()
    .mockResolvedValueOnce({ period, records: [record], insights: [insight], pendingProposalCount: 1 })
    .mockResolvedValueOnce({ period, records: [], insights: [], pendingProposalCount: 0 });
  const remote = { get: jest.fn(), respond: jest.fn() };
  const store = createHomeStore({ load });

  await store.getState().hydrate('2026-08-25T09:00:00Z');
  expect(store.getState().view?.thisWeek).toEqual([record]);
  expect(store.getState().view?.pendingProposalCount).toBe(1);
  expect(remote.get).not.toHaveBeenCalled();
  expect(remote.respond).not.toHaveBeenCalled();

  await store.getState().hydrate('2026-08-25T10:00:00Z');
  expect(store.getState().view?.thisWeek).toEqual([]);
  expect(store.getState().hydratedAt).toBe('2026-08-25T10:00:00Z');
});

test('Home hydration exposes a recoverable local archive failure', async () => {
  const store = createHomeStore({ load: jest.fn().mockRejectedValue(new Error('closed')) });

  await store.getState().hydrate('2026-08-25T09:00:00Z');

  expect(store.getState()).toMatchObject({
    view: null,
    isHydrating: false,
    error: 'The local Home archive is unavailable.',
  });
  store.getState().clearError();
  expect(store.getState().error).toBeNull();
});

test('governance hydration keeps proposals and per-capability authority explicit', async () => {
  const load = jest.fn().mockResolvedValue({ proposals: [proposal], capabilities: [capability] });
  const store = createGovernanceStore({ load });

  await store.getState().hydrate('2026-08-25T09:00:00Z');

  expect(store.getState().pendingProposals).toEqual([proposal]);
  expect(store.getState().capabilities).toEqual([capability]);
  expect(store.getState().capabilities[0]).toMatchObject({
    state: 'ready', permissionGrantedAt: null,
  });
});

test('late hydration cannot overwrite a newer local snapshot', async () => {
  const snapshot = { period, records: [], insights: [], pendingProposalCount: 0 };
  let resolveFirst!: (value: typeof snapshot) => void;
  const first = new Promise<typeof snapshot>((resolve) => { resolveFirst = resolve; });
  const load = jest.fn()
    .mockReturnValueOnce(first)
    .mockResolvedValueOnce({ ...snapshot, records: [record] });
  const store = createHomeStore({ load });

  const older = store.getState().hydrate('2026-08-25T09:00:00Z');
  await store.getState().hydrate('2026-08-25T10:00:00Z');
  resolveFirst(snapshot);
  await older;

  expect((store.getState().view as HomeView).thisWeek).toEqual([record]);
  expect(store.getState().hydratedAt).toBe('2026-08-25T10:00:00Z');
});

test('completion exposes its Trial receipt, reloads Home, and Undo clears it', async () => {
  const load = jest.fn().mockResolvedValue({ period, records: [record], insights: [], pendingProposalCount: 0 });
  const receipt = {
    id: 'operation-1', operation: 'complete_explicit_task', targetId: record.id,
    sourceId: record.sourceId, priorRevision: 1, resultingRevision: 2,
    visibility: 'trial', undoable: true, undoneAt: null, createdAt: '2026-08-25T09:00:00Z',
  } as const;
  const execute = jest.fn().mockResolvedValue(receipt);
  const undo = jest.fn().mockResolvedValue({ ...receipt, id: 'operation-1:undo' });
  const store = createHomeStore({ load, execute, undo });
  const request = {
    id: receipt.id, operation: 'complete_explicit_task', targetId: record.id,
    sourceId: record.sourceId, expectedRevision: 1, ambiguity: 'strong',
    requestedAt: receipt.createdAt,
  } as const;

  await store.getState().completeTask(request);
  expect(store.getState().activeReceipt).toEqual(receipt);
  expect(execute).toHaveBeenCalledWith(request);

  await store.getState().undoOperation(receipt.id, '2026-08-25T09:05:00Z');
  expect(undo).toHaveBeenCalledWith(receipt.id, '2026-08-25T09:05:00Z');
  expect(store.getState().activeReceipt).toBeNull();
  expect(load).toHaveBeenCalledTimes(2);
});

test('governance commands remain capability-specific and rehydrate after writes', async () => {
  const load = jest.fn().mockResolvedValue({ proposals: [], capabilities: [{ ...capability, state: 'ask_me' }] });
  const grant = jest.fn().mockResolvedValue(undefined);
  const revoke = jest.fn().mockResolvedValue(undefined);
  const rejectProposal = jest.fn().mockResolvedValue(undefined);
  const store = createGovernanceStore({ load, grant, revoke, rejectProposal });

  await store.getState().grantAuthority(capability.operation, '2026-08-25T09:00:00Z');
  await store.getState().askMe(capability.operation, '2026-08-25T09:05:00Z');
  await store.getState().rejectProposal(proposal.id, '2026-08-25T09:10:00Z');

  expect(grant).toHaveBeenCalledWith(capability.operation, '2026-08-25T09:00:00Z');
  expect(revoke).toHaveBeenCalledWith(capability.operation, '2026-08-25T09:05:00Z');
  expect(rejectProposal).toHaveBeenCalledWith(proposal.id, '2026-08-25T09:10:00Z');
  expect(load).toHaveBeenCalledTimes(3);
  expect(store.getState().capabilities[0].state).toBe('ask_me');
});
