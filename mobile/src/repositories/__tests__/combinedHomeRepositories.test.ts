import type {
  CapabilitySnapshot,
  Insight,
  LocalNotification,
  Project,
  ProposalEnvelope,
  WeeklyPeriod,
  WorkRecord,
  WorkRelationship,
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
import { createBehaviorRepository, type BehaviorEvent } from '../behaviorRepository';
import { createInsightRepository } from '../insightRepository';
import { createPeriodRepository } from '../periodRepository';
import { createProposalRepository } from '../proposalRepository';
import { createReadinessRepository } from '../readinessRepository';

class FakeConnection implements RepositoryConnection {
  readonly runs: Array<{ source: string; params?: SQLiteBindParams }> = [];
  readonly rows = new Map<string, Record<string, unknown>>();
  allRows: Record<string, unknown>[] = [];

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
    return this.allRows as T[];
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

test('work movement records prior placement in the caller transaction', async () => {
  const connection = new FakeConnection();
  connection.rows.set('task-1', {
    id: 'task-1', kind: 'task', title: 'Send proposal', project_id: null,
    status: 'open', freshness: 'current', planned_week: '2026-08-24',
    planned_day: null, source_id: 'conversation-1', revision: 1,
    created_at: '2026-08-25T08:00:00Z', updated_at: '2026-08-25T08:00:00Z',
    last_confirmed_at: '2026-08-25T08:00:00Z',
  });
  const repository = createWorkRepository(connection);

  await repository.moveToWeek(
    connection as unknown as RepositoryTransaction,
    'task-1',
    '2026-08-31',
    { id: 'event-1', sourceId: 'user-1', occurredAt: '2026-08-25T09:00:00Z', idempotencyId: 'move-1' },
  );

  expect(connection.runs).toHaveLength(2);
  expect(connection.runs[0]).toMatchObject({
    source: expect.stringContaining('UPDATE work_records'),
    params: expect.objectContaining({ $plannedWeek: '2026-08-31', $expectedRevision: 1 }),
  });
  expect(connection.runs[1]).toMatchObject({
    source: expect.stringContaining('INSERT INTO record_events'),
    params: expect.objectContaining({ $priorValueJson: '"2026-08-24"', $resultingValueJson: '"2026-08-31"' }),
  });
});

test('work repository persists projects and typed conversation relationships', async () => {
  const connection = new FakeConnection();
  const repository = createWorkRepository(connection);
  const project: Project = {
    id: 'project-1', name: 'Website Launch', status: 'active', sourceId: 'conversation-1',
    revision: 1, createdAt: '2026-08-25T08:00:00Z', updatedAt: '2026-08-25T08:00:00Z',
  };
  const relationship: WorkRelationship = {
    id: 'relationship-1', recordId: 'task-1', conversationId: 'conversation-1',
    role: 'primary', contribution: 'planning', sourceRevision: 2,
    createdAt: '2026-08-25T08:00:00Z',
  };

  await repository.insertProject(connection as unknown as RepositoryTransaction, project, 'project-insert-1');
  await repository.linkConversation(connection as unknown as RepositoryTransaction, relationship, 'link-1');

  expect(connection.runs[0]).toMatchObject({
    source: expect.stringContaining('INSERT INTO projects'),
    params: expect.objectContaining({ $id: 'project-1', $revision: 1 }),
  });
  expect(connection.runs[1]).toMatchObject({
    source: expect.stringContaining('INSERT INTO work_relationships'),
    params: expect.objectContaining({ $role: 'primary', $contribution: 'planning' }),
  });
});

test('work repository maps append-only movement history', async () => {
  const connection = new FakeConnection();
  connection.allRows = [{
    id: 'event-1', record_id: 'task-1', operation: 'move_week',
    prior_value_json: '"2026-08-24"', resulting_value_json: '"2026-08-31"',
    source_id: 'user-1', occurred_at: '2026-08-25T09:00:00Z',
    idempotency_key: 'move-1',
  }];
  const repository = createWorkRepository(connection);

  await expect(repository.listEvents('task-1')).resolves.toEqual([{
    id: 'event-1', recordId: 'task-1', operation: 'move_week',
    priorValue: '2026-08-24', resultingValue: '2026-08-31',
    sourceId: 'user-1', occurredAt: '2026-08-25T09:00:00Z', idempotencyId: 'move-1',
  }]);
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

  connection.rows.set('proposal-1', {
    id: 'proposal-1', type: 'project_association', source_id: 'conversation-1',
    source_revision: 2, evidence_ids_json: '["evidence-1"]', evidence_fingerprint: 'fp-1',
    reasoning: 'Explicit project name', effect_json: '{"recordId":"task-1","projectId":"project-1"}',
    ambiguity: 'strong', admission: 'pending', resolution: 'unapplied',
    revalidation: 'valid', created_at: '2026-08-25T08:00:00Z',
    updated_at: '2026-08-25T08:00:00Z',
  });
  await expect(repository.get('proposal-1')).resolves.toEqual(proposal);

  connection.rows.set('proposal-bad', {
    ...connection.rows.get('proposal-1'), id: 'proposal-bad', evidence_ids_json: '{"not":"an array"}',
  });
  await expect(repository.get('proposal-bad')).rejects.toThrow('Invalid proposal evidence IDs');
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

test('insight repository preserves evidence provenance as structured JSON', async () => {
  const connection = new FakeConnection();
  const repository = createInsightRepository(connection);
  const insight: Insight = {
    id: 'insight-1', kind: 'operational', title: 'Decisions are waiting',
    body: 'Two decisions remain open.', freshness: 'current',
    evidence: [{ evidenceId: 'evidence-1', sourceId: 'conversation-1', sourceRevision: 3 }],
    createdAt: '2026-08-25T08:00:00Z', updatedAt: '2026-08-25T08:00:00Z',
  };

  await repository.insertInsight(connection as unknown as RepositoryTransaction, insight);
  expect(connection.runs.at(-1)?.params).toEqual(expect.objectContaining({
    $freshness: 'current',
    $evidenceJson: '[{"evidenceId":"evidence-1","sourceId":"conversation-1","sourceRevision":3}]',
  }));
});

test('period repository persists review state without moving work records', async () => {
  const connection = new FakeConnection();
  const repository = createPeriodRepository(connection);
  const period: WeeklyPeriod = {
    id: 'week-2026-08-24', startsOn: '2026-08-24', endsOn: '2026-08-30',
    state: 'auto_closed_unreviewed', reviewedAt: null, closedAt: '2026-08-31T00:00:00Z',
  };

  await repository.putPeriod(connection as unknown as RepositoryTransaction, period);
  expect(connection.runs).toHaveLength(1);
  expect(connection.runs[0]).toMatchObject({
    source: expect.stringContaining('INSERT INTO weekly_periods'),
    params: expect.objectContaining({ $state: 'auto_closed_unreviewed', $reviewedAt: null }),
  });
});

test('behavior repository stores bounded metadata with explicit expiry', async () => {
  const connection = new FakeConnection();
  const repository = createBehaviorRepository(connection);
  const event: BehaviorEvent = {
    id: 'behavior-1', category: 'correction', eventType: 'proposal_rejected',
    sourceId: 'proposal-1', occurredAt: '2026-08-25T08:00:00Z',
    expiresAt: '2026-11-23T08:00:00Z',
  };

  await repository.insertEvent(connection as unknown as RepositoryTransaction, event, 'behavior-insert-1');
  expect(connection.runs.at(-1)).toMatchObject({
    source: expect.stringContaining('INSERT INTO behavior_events'),
    params: expect.objectContaining({ $category: 'correction', $expiresAt: '2026-11-23T08:00:00Z' }),
  });
});
