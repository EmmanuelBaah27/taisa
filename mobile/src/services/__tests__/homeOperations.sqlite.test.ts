import type { CapabilitySnapshot, WorkRecord } from '@taisa/shared';

import { createHomeOperationService } from '../homeOperations';
import { createTestDatabase } from '../../repositories/__tests__/testDatabase';
import { createReadinessRepository } from '../../repositories/readinessRepository';
import { createWorkRepository } from '../../repositories/workRepository';
import { createProposalRepository } from '../../repositories/proposalRepository';
import { createGovernanceActions } from '../governanceActions';

const NOW = '2026-08-26T09:00:00.000Z';

test('permitted completion and Undo are atomic and reload-visible', async () => {
  const database = createTestDatabase();
  const work = createWorkRepository(database);
  const readiness = createReadinessRepository(database);
  const record: WorkRecord = {
    id: 'task-1', kind: 'task', title: 'Send proposal', projectId: null,
    status: 'open', freshness: 'current', plannedWeek: '2026-08-24', plannedDay: null,
    sourceId: 'conversation-1', revision: 1, createdAt: NOW, updatedAt: NOW,
    lastConfirmedAt: NOW,
  };
  const capability: CapabilitySnapshot = {
    operation: 'complete_explicit_task', policyVersion: 1, state: 'permission_granted',
    permissionGrantedAt: NOW, relevantExamples: 8, corrections: 0, contradictions: 0,
    latestEvidenceAt: NOW, cleanTrialOutcomes: 0, updatedAt: NOW,
  };
  await database.withTransaction(async (transaction) => {
    await work.insert(transaction, record, 'seed-task');
    await readiness.put(transaction, capability);
  });
  const service = createHomeOperationService(database);

  const receipt = await service.execute({
    id: 'operation-1', operation: 'complete_explicit_task', targetId: record.id,
    sourceId: 'conversation-1', expectedRevision: 1, ambiguity: 'strong', requestedAt: NOW,
  });

  await expect(work.get(record.id)).resolves.toMatchObject({ status: 'completed', revision: 2 });
  expect(receipt).toMatchObject({ visibility: 'trial', undoable: true });
  await expect(database.getFirstAsync(
    'SELECT id, undone_at FROM operation_events WHERE id = $id', { $id: receipt.id },
  )).resolves.toEqual({ id: receipt.id, undone_at: null });

  await service.undo(receipt.id, '2026-08-26T09:05:00.000Z');

  await expect(work.get(record.id)).resolves.toMatchObject({ status: 'open', revision: 3 });
  await expect(database.getFirstAsync<{ undone_at: string }>(
    'SELECT undone_at FROM operation_events WHERE id = $id', { $id: receipt.id },
  )).resolves.toEqual({ undone_at: '2026-08-26T09:05:00.000Z' });
  database.close();
});

test('failed operation rolls back record, receipt, and readiness outcome together', async () => {
  const database = createTestDatabase();
  const work = createWorkRepository(database);
  const readiness = createReadinessRepository(database);
  const record: WorkRecord = {
    id: 'task-2', kind: 'task', title: 'Keep open', projectId: null,
    status: 'open', freshness: 'current', plannedWeek: null, plannedDay: null,
    sourceId: 'conversation-1', revision: 1, createdAt: NOW, updatedAt: NOW, lastConfirmedAt: NOW,
  };
  await database.withTransaction(async (transaction) => {
    await work.insert(transaction, record, 'seed-task-2');
    await readiness.put(transaction, {
      operation: 'complete_explicit_task', policyVersion: 1, state: 'permission_granted',
      permissionGrantedAt: NOW, relevantExamples: 8, corrections: 0, contradictions: 0,
      latestEvidenceAt: NOW, cleanTrialOutcomes: 0, updatedAt: NOW,
    });
  });
  const runAsync = database.runAsync.bind(database);
  database.runAsync = async (source, params) => {
    if (source.includes('INSERT INTO operation_events')) throw new Error('receipt rejected');
    return runAsync(source, params);
  };

  await expect(createHomeOperationService(database).execute({
    id: 'operation-2', operation: 'complete_explicit_task', targetId: record.id,
    sourceId: 'conversation-1', expectedRevision: 1, ambiguity: 'strong', requestedAt: NOW,
  })).rejects.toThrow('receipt rejected');

  await expect(work.get(record.id)).resolves.toMatchObject({ status: 'open', revision: 1 });
  await expect(database.getFirstAsync<{ count: number }>(
    'SELECT COUNT(*) AS count FROM record_events',
  )).resolves.toEqual({ count: 0 });
  database.close();
});

test('lost revision race records no receipt, event, proposal resolution, or readiness success', async () => {
  const database = createTestDatabase();
  const work = createWorkRepository(database);
  const readiness = createReadinessRepository(database);
  const record: WorkRecord = {
    id: 'task-race', kind: 'task', title: 'Race', projectId: null, status: 'open',
    freshness: 'current', plannedWeek: null, plannedDay: null, sourceId: 'conversation-1',
    revision: 1, createdAt: NOW, updatedAt: NOW, lastConfirmedAt: NOW,
  };
  await database.withTransaction(async (transaction) => {
    await work.insert(transaction, record, 'seed-race');
    await readiness.put(transaction, {
      operation: 'complete_explicit_task', policyVersion: 1, state: 'trusted',
      permissionGrantedAt: NOW, relevantExamples: 8, corrections: 0, contradictions: 0,
      latestEvidenceAt: NOW, cleanTrialOutcomes: 5, updatedAt: NOW,
    });
  });
  const runAsync = database.runAsync.bind(database);
  database.runAsync = async (source, params) => {
    if (source.includes('UPDATE work_records SET title')) return { changes: 0, lastInsertRowId: 0 };
    return runAsync(source, params);
  };

  await expect(createHomeOperationService(database).execute({
    id: 'operation-race', operation: 'complete_explicit_task', targetId: record.id,
    sourceId: record.sourceId, expectedRevision: 1, ambiguity: 'strong', requestedAt: NOW,
  })).rejects.toThrow('REVISION_CONFLICT');
  await expect(database.getFirstAsync<{ count: number }>(
    'SELECT COUNT(*) AS count FROM operation_events',
  )).resolves.toEqual({ count: 0 });
  await expect(database.getFirstAsync<{ count: number }>(
    'SELECT COUNT(*) AS count FROM record_events',
  )).resolves.toEqual({ count: 0 });
  database.close();
});

test('user-confirmed proposal applies its effect and resolves atomically without delegated permission', async () => {
  const database = createTestDatabase();
  const work = createWorkRepository(database);
  const readiness = createReadinessRepository(database);
  const proposals = createProposalRepository(database);
  const record: WorkRecord = {
    id: 'task-3', kind: 'task', title: 'Confirm me', projectId: null,
    status: 'open', freshness: 'current', plannedWeek: null, plannedDay: null,
    sourceId: 'conversation-1', revision: 1, createdAt: NOW, updatedAt: NOW, lastConfirmedAt: NOW,
  };
  await database.withTransaction(async (transaction) => {
    await work.insert(transaction, record, 'seed-task-3');
    await readiness.put(transaction, {
      operation: 'complete_explicit_task', policyVersion: 1, state: 'learning',
      permissionGrantedAt: null, relevantExamples: 1, corrections: 0, contradictions: 0,
      latestEvidenceAt: NOW, cleanTrialOutcomes: 0, updatedAt: NOW,
    });
    await proposals.insert(transaction, {
      id: 'proposal-3', type: 'task_completion', sourceId: 'conversation-1', sourceRevision: 1,
      evidenceIds: ['evidence-1'], evidenceFingerprint: 'fp-3', reasoning: 'User explicitly said done',
      effect: { recordId: record.id }, ambiguity: 'ambiguous', admission: 'admitted',
      resolution: 'unapplied', revalidation: 'valid', createdAt: NOW, updatedAt: NOW,
    }, 'seed-proposal-3');
  });

  await createGovernanceActions(database).acceptProposal('proposal-3', '2026-08-26T09:05:00.000Z');

  await expect(work.get(record.id)).resolves.toMatchObject({ status: 'completed', revision: 2 });
  await expect(database.getFirstAsync<{ resolution: string }>(
    'SELECT resolution FROM proposals WHERE id = $id', { $id: 'proposal-3' },
  )).resolves.toEqual({ resolution: 'accepted' });
  database.close();
});

test('accepted creation proposals persist bounded authoritative records', async () => {
  const database = createTestDatabase();
  const proposals = createProposalRepository(database);
  const fixtures = [
    { id: 'proposal-work', type: 'work_record' as const,
      effect: { kind: 'task' as const, title: 'New task', projectId: null } },
    { id: 'proposal-insight', type: 'insight' as const,
      effect: { title: 'Pattern', body: 'A grounded pattern.' } },
    { id: 'proposal-reflection', type: 'growth_reflection' as const,
      effect: { title: 'Growth', body: 'A grounded reflection.' } },
    { id: 'proposal-experiment', type: 'experiment' as const,
      effect: { title: 'Try focus', hypothesis: 'Focus improves delivery.' } },
  ];
  await database.withTransaction(async (transaction) => {
    for (const fixture of fixtures) {
      await proposals.insert(transaction, {
        ...fixture, sourceId: 'conversation-1', sourceRevision: 2,
        evidenceIds: ['evidence-1'], evidenceFingerprint: `fp-${fixture.id}`,
        reasoning: 'User-confirmed proposal', ambiguity: 'strong', admission: 'admitted',
        resolution: 'unapplied', revalidation: 'valid', createdAt: NOW, updatedAt: NOW,
      }, `seed-${fixture.id}`);
    }
  });
  const governance = createGovernanceActions(database);
  for (const fixture of fixtures) await governance.acceptProposal(fixture.id, NOW);

  await expect(database.getFirstAsync<{ count: number }>(
    `SELECT COUNT(*) AS count FROM proposals WHERE resolution = 'accepted'`,
  )).resolves.toEqual({ count: 4 });
  await expect(database.getFirstAsync<{ count: number }>(
    `SELECT COUNT(*) AS count FROM work_records WHERE id = 'proposal-work:work'`,
  )).resolves.toEqual({ count: 1 });
  await expect(database.getFirstAsync<{ count: number }>(
    `SELECT COUNT(*) AS count FROM insights WHERE id = 'proposal-insight:insight'`,
  )).resolves.toEqual({ count: 1 });
  await expect(database.getFirstAsync<{ state: string }>(
    `SELECT state FROM growth_reflections WHERE id = 'proposal-reflection:reflection'`,
  )).resolves.toEqual({ state: 'confirmed' });
  await expect(database.getFirstAsync<{ state: string }>(
    `SELECT state FROM experiments WHERE id = 'proposal-experiment:experiment'`,
  )).resolves.toEqual({ state: 'active' });
  database.close();
});

test('creation proposal rolls back its authoritative insert when resolution fails', async () => {
  const database = createTestDatabase();
  await database.withTransaction((transaction) => createProposalRepository(database).insert(transaction, {
    id: 'proposal-rollback', type: 'insight', sourceId: 'conversation-1', sourceRevision: 1,
    evidenceIds: ['evidence-1'], evidenceFingerprint: 'fp-rollback', reasoning: 'Rollback test',
    effect: { title: 'Must roll back', body: 'No partial insert.' }, ambiguity: 'strong',
    admission: 'admitted', resolution: 'unapplied', revalidation: 'valid', createdAt: NOW, updatedAt: NOW,
  }, 'seed-proposal-rollback'));
  const runAsync = database.runAsync.bind(database);
  database.runAsync = async (source, params) => {
    if (source.includes("UPDATE proposals SET resolution = 'accepted'")) throw new Error('resolution failed');
    return runAsync(source, params);
  };

  await expect(createGovernanceActions(database).acceptProposal('proposal-rollback', NOW))
    .rejects.toThrow('resolution failed');
  await expect(database.getFirstAsync<{ count: number }>(
    `SELECT COUNT(*) AS count FROM insights WHERE id = 'proposal-rollback:insight'`,
  )).resolves.toEqual({ count: 0 });
  database.close();
});
