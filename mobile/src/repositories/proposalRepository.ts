import type { ProposalEnvelope, ProposalType } from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';

export interface ProposalRepository {
  insert<T extends ProposalType>(
    transaction: RepositoryTransaction,
    proposal: ProposalEnvelope<T>,
    idempotencyId: string,
  ): Promise<void>;
}

export function createProposalRepository(_database: RepositoryConnection): ProposalRepository {
  return {
    async insert(transaction, proposal, idempotencyId) {
      await transaction.runAsync(
        `INSERT INTO proposals
          (id, type, source_id, source_revision, evidence_ids_json, evidence_fingerprint,
           reasoning, effect_json, ambiguity, admission, resolution, revalidation,
           created_at, updated_at, idempotency_key)
         VALUES ($id, $type, $sourceId, $sourceRevision, $evidenceIdsJson,
           $evidenceFingerprint, $reasoning, $effectJson, $ambiguity, $admission,
           $resolution, $revalidation, $createdAt, $updatedAt, $idempotencyId)`,
        {
          $id: proposal.id,
          $type: proposal.type,
          $sourceId: proposal.sourceId,
          $sourceRevision: proposal.sourceRevision,
          $evidenceIdsJson: JSON.stringify(proposal.evidenceIds),
          $evidenceFingerprint: proposal.evidenceFingerprint,
          $reasoning: proposal.reasoning,
          $effectJson: JSON.stringify(proposal.effect),
          $ambiguity: proposal.ambiguity,
          $admission: proposal.admission,
          $resolution: proposal.resolution,
          $revalidation: proposal.revalidation,
          $createdAt: proposal.createdAt,
          $updatedAt: proposal.updatedAt,
          $idempotencyId: idempotencyId,
        },
      );
    },
  };
}
