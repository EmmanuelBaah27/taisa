import type { CapabilitySnapshot, PermittedOperation, ProposalEnvelope } from '@taisa/shared';

import type { ExclusiveTransactionConnection } from '../db/types';
import { withRepositoryTransaction } from '../db/types';
import { grantAuthority, revokeAuthority } from '../domain/readiness/readinessPolicy';
import { createReadinessRepository } from '../repositories/readinessRepository';
import { createInsightRepository } from '../repositories/insightRepository';
import { createWorkRepository } from '../repositories/workRepository';
import { createHomeOperationService } from './homeOperations';
import type { OperationRequest } from '../domain/operations/operationGate';

type CapabilityRow = {
  operation: PermittedOperation; policy_version: number; state: CapabilitySnapshot['state'];
  permission_granted_at: string | null; relevant_examples: number; corrections: number;
  contradictions: number; latest_evidence_at: string | null; clean_trial_outcomes: number;
  updated_at: string;
};
type ProposalRow = {
  id: string; type: ProposalEnvelope['type']; source_id: string; source_revision: number;
  evidence_ids_json: string; ambiguity: 'strong' | 'ambiguous'; effect_json: string;
};

async function acceptCreationProposal(
  database: ExclusiveTransactionConnection,
  proposal: ProposalRow,
  effect: Record<string, unknown>,
  now: string,
): Promise<boolean> {
  if (!['work_record', 'insight', 'growth_reflection', 'experiment'].includes(proposal.type)) {
    return false;
  }
  await withRepositoryTransaction(database, async (transaction) => {
    const evidenceIds = JSON.parse(proposal.evidence_ids_json) as string[];
    const evidence = evidenceIds.map((evidenceId) => ({
      evidenceId, sourceId: proposal.source_id, sourceRevision: proposal.source_revision,
    }));
    const insights = createInsightRepository(transaction);
    switch (proposal.type) {
      case 'work_record':
        const kind = effect.kind as 'task' | 'followup' | 'blocker' | 'decision';
        const initialStatus = {
          task: 'open', followup: 'waiting', blocker: 'active', decision: 'current',
        } as const;
        await createWorkRepository(transaction).insert(transaction, {
          id: `${proposal.id}:work`, kind, title: effect.title as string,
          projectId: effect.projectId as string | null, status: initialStatus[kind], freshness: 'current',
          plannedWeek: null, plannedDay: null, sourceId: proposal.source_id, revision: 1,
          createdAt: now, updatedAt: now, lastConfirmedAt: now,
        } as never, `${proposal.id}:accept`);
        break;
      case 'insight':
        await insights.insertInsight(transaction, {
          id: `${proposal.id}:insight`, kind: 'operational', title: effect.title as string,
          body: effect.body as string, freshness: 'current', evidence, createdAt: now, updatedAt: now,
        });
        break;
      case 'growth_reflection':
        await insights.insertReflection(transaction, {
          id: `${proposal.id}:reflection`, kind: 'growth_reflection', title: effect.title as string,
          body: effect.body as string, state: 'confirmed', evidence, createdAt: now, updatedAt: now,
        });
        break;
      case 'experiment':
        await insights.insertExperiment(transaction, {
          id: `${proposal.id}:experiment`, title: effect.title as string,
          hypothesis: effect.hypothesis as string, state: 'active', sourceReflectionId: null,
          createdAt: now, updatedAt: now,
        });
        break;
    }
    const resolved = await transaction.runAsync(
      `UPDATE proposals SET resolution = 'accepted', updated_at = $now
       WHERE id = $id AND admission IN ('pending', 'admitted')
         AND resolution = 'unapplied' AND revalidation = 'valid'`,
      { $id: proposal.id, $now: now },
    );
    if (resolved.changes !== 1) throw new Error('Proposal is no longer applicable');
  });
  return true;
}

function mapCapability(row: CapabilityRow | null): CapabilitySnapshot | null {
  return row === null ? null : {
    operation: row.operation, policyVersion: row.policy_version, state: row.state,
    permissionGrantedAt: row.permission_granted_at, relevantExamples: row.relevant_examples,
    corrections: row.corrections, contradictions: row.contradictions,
    latestEvidenceAt: row.latest_evidence_at, cleanTrialOutcomes: row.clean_trial_outcomes,
    updatedAt: row.updated_at,
  };
}

async function readCapability(database: ExclusiveTransactionConnection, operation: PermittedOperation) {
  return mapCapability(await database.getFirstAsync<CapabilityRow>(
    `SELECT operation, policy_version, state, permission_granted_at, relevant_examples,
       corrections, contradictions, latest_evidence_at, clean_trial_outcomes, updated_at
     FROM capability_states WHERE operation = $operation`, { $operation: operation },
  ));
}

export function createGovernanceActions(database: ExclusiveTransactionConnection) {
  return {
    async acceptProposal(proposalId: string, now: string): Promise<void> {
      const proposal = await database.getFirstAsync<ProposalRow>(
        `SELECT id, type, source_id, source_revision, evidence_ids_json, ambiguity, effect_json FROM proposals
         WHERE id = $id AND admission IN ('pending', 'admitted')
           AND resolution = 'unapplied' AND revalidation = 'valid'`,
        { $id: proposalId },
      );
      if (proposal === null) throw new Error('Proposal is no longer applicable');
      const effect = JSON.parse(proposal.effect_json) as Record<string, unknown>;
      if (await acceptCreationProposal(database, proposal, effect, now)) return;
      let operation: OperationRequest['operation'];
      let targetId: string;
      let payload: Record<string, unknown> = {};
      switch (proposal.type) {
        case 'task_completion':
          operation = 'complete_explicit_task'; targetId = effect.recordId as string; break;
        case 'project_association':
          operation = 'associate_existing_project'; targetId = effect.recordId as string;
          payload = { projectId: effect.projectId }; break;
        case 'task_conversation_link':
          operation = 'apply_strong_task_conversation_link'; targetId = effect.recordId as string;
          payload = { conversationId: effect.conversationId, contribution: effect.contribution }; break;
        case 'followup_status_update':
          operation = 'update_explicit_followup_status'; targetId = effect.recordId as string;
          payload = { status: effect.status }; break;
        case 'blocker_status_update':
          operation = 'update_explicit_blocker_status'; targetId = effect.recordId as string;
          payload = { status: effect.status }; break;
        case 'project_status_update':
          operation = 'update_explicit_project_status'; targetId = effect.projectId as string;
          payload = { status: effect.status }; break;
        default:
          throw new Error('Proposal type requires a more specific confirmation contract');
      }
      const table = operation === 'update_explicit_project_status' ? 'projects' : 'work_records';
      const current = await database.getFirstAsync<{ revision: number }>(
        `SELECT revision FROM ${table} WHERE id = $id`, { $id: targetId },
      );
      if (current === null) throw new Error('Proposal target is unavailable');
      await createHomeOperationService(database).execute({
        id: `${proposal.id}:accept`, operation, targetId, sourceId: proposal.source_id,
        expectedRevision: current.revision, ambiguity: proposal.ambiguity, requestedAt: now,
        payload, authorization: 'user_confirmed', proposalId: proposal.id,
      });
    },
    async grant(operation: PermittedOperation, now: string): Promise<void> {
      await withRepositoryTransaction(database, async (transaction) => {
        const current = await readCapability(transaction as unknown as ExclusiveTransactionConnection, operation);
        if (current === null) throw new Error('Missing capability state');
        await createReadinessRepository(transaction).put(transaction, grantAuthority(current, now));
      });
    },
    async revoke(operation: PermittedOperation, now: string): Promise<void> {
      await withRepositoryTransaction(database, async (transaction) => {
        const current = await readCapability(transaction as unknown as ExclusiveTransactionConnection, operation);
        if (current === null) throw new Error('Missing capability state');
        await createReadinessRepository(transaction).put(transaction, revokeAuthority(current, now));
      });
    },
    async rejectProposal(proposalId: string, now: string): Promise<void> {
      await withRepositoryTransaction(database, async (transaction) => {
        const result = await transaction.runAsync(
          `UPDATE proposals SET resolution = 'rejected', updated_at = $now
           WHERE id = $id AND admission = 'pending' AND resolution = 'unapplied'
             AND revalidation = 'valid'`,
          { $id: proposalId, $now: now },
        );
        if (result.changes !== 1) throw new Error('Proposal is no longer reviewable');
      });
    },
  };
}
