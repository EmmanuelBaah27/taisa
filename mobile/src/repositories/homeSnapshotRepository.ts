import type {
  CapabilitySnapshot,
  Insight,
  ProposalEnvelope,
  LocalNotification,
  WeeklyPeriod,
  WorkRecord,
} from '@taisa/shared';

import type { RepositoryConnection } from '../db/types';
import { deriveWeeklyPeriod } from '../domain/periods/weeklyPeriod';
import type { GovernanceSnapshot } from '../stores/governanceStore';
import type { HomeSnapshot } from '../stores/homeStore';

type WorkRow = {
  id: string; kind: WorkRecord['kind']; title: string; project_id: string | null;
  status: WorkRecord['status']; freshness: WorkRecord['freshness']; planned_week: string | null;
  planned_day: string | null; source_id: string; revision: number; created_at: string;
  updated_at: string; last_confirmed_at: string | null;
};
type InsightRow = {
  id: string; kind: Insight['kind']; title: string; body: string; freshness: Insight['freshness'];
  evidence_json: string; created_at: string; updated_at: string;
};
type PeriodRow = {
  id: string; starts_on: string; ends_on: string; state: WeeklyPeriod['state'];
  reviewed_at: string | null; closed_at: string | null;
};
type ProposalRow = {
  id: string; type: ProposalEnvelope['type']; source_id: string; source_revision: number;
  evidence_ids_json: string; evidence_fingerprint: string; reasoning: string; effect_json: string;
  ambiguity: ProposalEnvelope['ambiguity']; admission: ProposalEnvelope['admission'];
  resolution: ProposalEnvelope['resolution']; revalidation: ProposalEnvelope['revalidation'];
  created_at: string; updated_at: string;
};
type CapabilityRow = {
  operation: CapabilitySnapshot['operation']; policy_version: number; state: CapabilitySnapshot['state'];
  permission_granted_at: string | null; relevant_examples: number; corrections: number;
  contradictions: number; latest_evidence_at: string | null; clean_trial_outcomes: number;
  updated_at: string;
};
type NotificationRow = {
  id: string; source_type: LocalNotification['sourceType']; source_id: string; grouping_key: string;
  read_state: LocalNotification['readState']; disposition: LocalNotification['disposition'];
  snoozed_until: string | null; created_at: string;
};

export async function loadHomeSnapshot(
  database: RepositoryConnection,
  now: string,
): Promise<HomeSnapshot> {
  const derived = deriveWeeklyPeriod(new Date(now));
  const [periodRow, records, insights, count, notifications] = await Promise.all([
    database.getFirstAsync<PeriodRow>(
      `SELECT id, starts_on, ends_on, state, reviewed_at, closed_at
       FROM weekly_periods WHERE id = $id`, { $id: derived.id },
    ),
    database.getAllAsync<WorkRow>(
      `SELECT id, kind, title, project_id, status, freshness, planned_week, planned_day,
         source_id, revision, created_at, updated_at, last_confirmed_at FROM work_records`,
    ),
    database.getAllAsync<InsightRow>(
      `SELECT id, kind, title, body, freshness, evidence_json, created_at, updated_at
       FROM insights`,
    ),
    database.getFirstAsync<{ count: number }>(
      `SELECT COUNT(*) AS count FROM proposals
       WHERE admission = 'pending' AND resolution = 'unapplied'`,
    ),
    database.getAllAsync<NotificationRow>(
      `SELECT id, source_type, source_id, grouping_key, read_state, disposition,
         snoozed_until, created_at FROM local_notifications ORDER BY created_at DESC, id`,
    ),
  ]);
  const period: WeeklyPeriod = periodRow === null ? derived : {
    id: periodRow.id, startsOn: periodRow.starts_on, endsOn: periodRow.ends_on,
    state: periodRow.state, reviewedAt: periodRow.reviewed_at, closedAt: periodRow.closed_at,
  };
  return {
    period,
    records: records.map((row) => ({
      id: row.id, kind: row.kind, title: row.title, projectId: row.project_id,
      status: row.status, freshness: row.freshness, plannedWeek: row.planned_week,
      plannedDay: row.planned_day, sourceId: row.source_id, revision: row.revision,
      createdAt: row.created_at, updatedAt: row.updated_at, lastConfirmedAt: row.last_confirmed_at,
    })),
    insights: insights.map((row) => ({
      id: row.id, kind: row.kind, title: row.title, body: row.body, freshness: row.freshness,
      evidence: JSON.parse(row.evidence_json), createdAt: row.created_at, updatedAt: row.updated_at,
    })),
    pendingProposalCount: count?.count ?? 0,
    notifications: notifications.map((row) => ({
      id: row.id, sourceType: row.source_type, sourceId: row.source_id,
      groupingKey: row.grouping_key, readState: row.read_state,
      disposition: row.disposition, snoozedUntil: row.snoozed_until, createdAt: row.created_at,
    })),
  };
}

export async function loadGovernanceSnapshot(
  database: RepositoryConnection,
): Promise<GovernanceSnapshot> {
  const [proposals, capabilities] = await Promise.all([
    database.getAllAsync<ProposalRow>(
      `SELECT id, type, source_id, source_revision, evidence_ids_json, evidence_fingerprint,
         reasoning, effect_json, ambiguity, admission, resolution, revalidation, created_at, updated_at
       FROM proposals WHERE admission = 'pending' AND resolution = 'unapplied'
       ORDER BY created_at, id`,
    ),
    database.getAllAsync<CapabilityRow>(
      `SELECT operation, policy_version, state, permission_granted_at, relevant_examples,
         corrections, contradictions, latest_evidence_at, clean_trial_outcomes, updated_at
       FROM capability_states ORDER BY operation`,
    ),
  ]);
  return {
    proposals: proposals.map((row) => ({
      id: row.id, type: row.type, sourceId: row.source_id, sourceRevision: row.source_revision,
      evidenceIds: JSON.parse(row.evidence_ids_json), evidenceFingerprint: row.evidence_fingerprint,
      reasoning: row.reasoning, effect: JSON.parse(row.effect_json), ambiguity: row.ambiguity,
      admission: row.admission, resolution: row.resolution, revalidation: row.revalidation,
      createdAt: row.created_at, updatedAt: row.updated_at,
    } as ProposalEnvelope)),
    capabilities: capabilities.map((row) => ({
      operation: row.operation, policyVersion: row.policy_version, state: row.state,
      permissionGrantedAt: row.permission_granted_at, relevantExamples: row.relevant_examples,
      corrections: row.corrections, contradictions: row.contradictions,
      latestEvidenceAt: row.latest_evidence_at, cleanTrialOutcomes: row.clean_trial_outcomes,
      updatedAt: row.updated_at,
    })),
  };
}
