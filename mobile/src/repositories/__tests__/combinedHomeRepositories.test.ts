import type {
  CapabilitySnapshot,
  LocalNotification,
  ProposalEnvelope,
  WorkRecord,
} from '@taisa/shared';

import { SCHEMA_VERSION } from '../../db/migrations';
import { SCHEMA_V5_STATEMENTS } from '../../db/schema';
import type {
  RepositoryConnection,
  RepositoryTransaction,
  SQLiteBindParams,
} from '../../db/types';
import { createWorkRepository } from '../workRepository';
import { createNotificationRepository } from '../notificationRepository';
import { createProposalRepository } from '../proposalRepository';
import { createReadinessRepository } from '../readinessRepository';

class FakeConnection implements RepositoryConnection {
  readonly runs: Array<{ source: string; params?: SQLiteBindParams }> = [];
  readonly rows = new Map<string, Record<string, unknown>>();

  async execAsync(): Promise<void> {}

  async runAsync(source: string, params?: SQLiteBindParams) {
    this.runs.push({ source, params });
    return { lastInsertRowId: 0, changes: 1 };
  }

  async getFirstAsync<T>(_source: string, params?: SQLiteBindParams): Promise<T | null> {
    const id = !Array.isArray(params) && params ? params.$id : null;
    return typeof id === 'string' ? (this.rows.get(id) as T | undefined) ?? null : null;
  }

  async getAllAsync<T>(): Promise<T[]> {
    return [];
  }
}

const task: WorkRecord = {
  id: 'task-1',
  kind: 'task',
  title: 'Send proposal',
  projectId: null,
  status: 'open',
  freshness: 'current',
  plannedWeek: '2026-08-24',
  plannedDay: null,
  sourceId: 'conversation-1',
  revision: 1,
  createdAt: '2026-08-25T08:00:00Z',
  updatedAt: '2026-08-25T08:00:00Z',
  lastConfirmedAt: '2026-08-25T08:00:00Z',
};

test('schema version 5 creates each governed Home table once', () => {
  expect(SCHEMA_VERSION).toBe(5);

  for (const table of [
    'projects',
    'work_records',
    'work_relationships',
    'record_events',
    'proposals',
    'insights',
    'growth_reflections',
    'experiments',
    'weekly_periods',
    'weekly_period_snapshots',
    'capability_states',
    'operation_events',
    'behavior_events',
    'behavior_aggregates',
    'local_notifications',
  ]) {
    expect(
      SCHEMA_V5_STATEMENTS.some((statement) =>
        statement.includes(`CREATE TABLE ${table}`),
      ),
    ).toBe(true);
  }
});

test('work repository maps records and requires caller transactions for writes', async () => {
  const connection = new FakeConnection();
  const repository = createWorkRepository(connection);

  await repository.insert(connection as unknown as RepositoryTransaction, task, 'insert-1');

  expect(connection.runs.at(-1)).toMatchObject({
    source: expect.stringContaining('INSERT INTO work_records'),
    params: expect.objectContaining({ $id: 'task-1', $revision: 1 }),
  });

  connection.rows.set('task-1', {
    id: 'task-1', kind: 'task', title: 'Send proposal', project_id: null,
    status: 'open', freshness: 'current', planned_week: '2026-08-24',
    planned_day: null, source_id: 'conversation-1', revision: 1,
    created_at: '2026-08-25T08:00:00Z', updated_at: '2026-08-25T08:00:00Z',
    last_confirmed_at: '2026-08-25T08:00:00Z',
  });

  await expect(repository.get('task-1')).resolves.toEqual(task);
});

test('proposal repository validates JSON at its boundary', async () => {
  const connection = new FakeConnection();
  const repository = createProposalRepository(connection);
  const proposal: ProposalEnvelope<'project_association'> = {
    id: 'proposal-1', type: 'project_association', sourceId: 'conversation-1',
    sourceRevision: 2, evidenceIds: ['evidence-1'], evidenceFingerprint: 'fp-1',
    reasoning: 'Explicit project name', effect: { recordId: 'task-1', projectId: 'project-1' },
    ambiguity: 'strong', admission: 'pending', resolution: 'unapplied',
    revalidation: 'valid', createdAt: '2026-08-25T08:00:00Z',
    updatedAt: '2026-08-25T08:00:00Z',
  };

  await repository.insert(connection as unknown as RepositoryTransaction, proposal, 'proposal-insert-1');
  expect(connection.runs.at(-1)?.params).toEqual(expect.objectContaining({
    $evidenceIdsJson: '["evidence-1"]',
    $effectJson: '{"recordId":"task-1","projectId":"project-1"}',
  }));
});

test('readiness repository keeps permission and evidence fields independent', async () => {
  const connection = new FakeConnection();
  const repository = createReadinessRepository(connection);
  const snapshot: CapabilitySnapshot = {
    operation: 'complete_explicit_task', policyVersion: 1, state: 'ready',
    permissionGrantedAt: null, relevantExamples: 8, corrections: 0,
    contradictions: 0, latestEvidenceAt: '2026-08-25T08:00:00Z',
    cleanTrialOutcomes: 0, updatedAt: '2026-08-25T08:00:00Z',
  };

  await repository.put(connection as unknown as RepositoryTransaction, snapshot);
  expect(connection.runs.at(-1)).toMatchObject({
    source: expect.stringContaining('INSERT INTO capability_states'),
    params: expect.objectContaining({ $state: 'ready', $permissionGrantedAt: null }),
  });
});

test('notification repository persists read state separately from disposition', async () => {
  const connection = new FakeConnection();
  const repository = createNotificationRepository(connection);
  const notification: LocalNotification = {
    id: 'notification-1', sourceType: 'proposal', sourceId: 'proposal-1',
    groupingKey: 'proposal-review', readState: 'unread', disposition: 'snoozed',
    snoozedUntil: '2026-08-26T08:00:00Z', createdAt: '2026-08-25T08:00:00Z',
  };

  await repository.insert(connection as unknown as RepositoryTransaction, notification, 'notification-insert-1');
  expect(connection.runs.at(-1)?.params).toEqual(expect.objectContaining({
    $readState: 'unread', $disposition: 'snoozed',
  }));
});
