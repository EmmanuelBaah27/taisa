import type { CapabilitySnapshot, PermittedOperation } from '@taisa/shared';

import type { ExclusiveTransactionConnection } from '../db/types';
import { withRepositoryTransaction } from '../db/types';
import { grantAuthority, revokeAuthority } from '../domain/readiness/readinessPolicy';
import { createReadinessRepository } from '../repositories/readinessRepository';

type CapabilityRow = {
  operation: PermittedOperation; policy_version: number; state: CapabilitySnapshot['state'];
  permission_granted_at: string | null; relevant_examples: number; corrections: number;
  contradictions: number; latest_evidence_at: string | null; clean_trial_outcomes: number;
  updated_at: string;
};

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
