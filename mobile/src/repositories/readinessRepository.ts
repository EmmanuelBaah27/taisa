import type { CapabilitySnapshot } from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';

export interface ReadinessRepository {
  put(transaction: RepositoryTransaction, snapshot: CapabilitySnapshot): Promise<void>;
}

export function createReadinessRepository(_database: RepositoryConnection): ReadinessRepository {
  return {
    async put(transaction, snapshot) {
      await transaction.runAsync(
        `INSERT INTO capability_states
          (operation, policy_version, state, permission_granted_at, relevant_examples,
           corrections, contradictions, latest_evidence_at, clean_trial_outcomes, updated_at)
         VALUES ($operation, $policyVersion, $state, $permissionGrantedAt, $relevantExamples,
           $corrections, $contradictions, $latestEvidenceAt, $cleanTrialOutcomes, $updatedAt)
         ON CONFLICT(operation) DO UPDATE SET
           policy_version = excluded.policy_version, state = excluded.state,
           permission_granted_at = excluded.permission_granted_at,
           relevant_examples = excluded.relevant_examples, corrections = excluded.corrections,
           contradictions = excluded.contradictions,
           latest_evidence_at = excluded.latest_evidence_at,
           clean_trial_outcomes = excluded.clean_trial_outcomes, updated_at = excluded.updated_at`,
        {
          $operation: snapshot.operation,
          $policyVersion: snapshot.policyVersion,
          $state: snapshot.state,
          $permissionGrantedAt: snapshot.permissionGrantedAt,
          $relevantExamples: snapshot.relevantExamples,
          $corrections: snapshot.corrections,
          $contradictions: snapshot.contradictions,
          $latestEvidenceAt: snapshot.latestEvidenceAt,
          $cleanTrialOutcomes: snapshot.cleanTrialOutcomes,
          $updatedAt: snapshot.updatedAt,
        },
      );
    },
  };
}
