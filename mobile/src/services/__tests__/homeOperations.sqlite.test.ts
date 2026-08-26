import type { CapabilitySnapshot, WorkRecord } from '@taisa/shared';

import { createHomeOperationService } from '../homeOperations';
import { createTestDatabase } from '../../repositories/__tests__/testDatabase';
import { createReadinessRepository } from '../../repositories/readinessRepository';
import { createWorkRepository } from '../../repositories/workRepository';

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
