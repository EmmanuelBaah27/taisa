import type { ProposalEnvelope, ProposalType } from '@taisa/shared';

import type { RepositoryConnection, RepositoryTransaction } from '../db/types';

interface ProposalRow {
  id: string;
  type: ProposalType;
  source_id: string;
  source_revision: number;
  evidence_ids_json: string;
  evidence_fingerprint: string;
  reasoning: string;
  effect_json: string;
  ambiguity: ProposalEnvelope['ambiguity'];
  admission: ProposalEnvelope['admission'];
  resolution: ProposalEnvelope['resolution'];
  revalidation: ProposalEnvelope['revalidation'];
  created_at: string;
  updated_at: string;
}

function parseEvidenceIds(value: string): string[] {
  const parsed: unknown = JSON.parse(value);
  if (!Array.isArray(parsed) || parsed.some((item) => typeof item !== 'string')) {
    throw new Error('Invalid proposal evidence IDs');
  }
  return parsed;
}

function parseEffect(value: string): Record<string, unknown> {
  const parsed: unknown = JSON.parse(value);
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('Invalid proposal effect');
  }
  return parsed as Record<string, unknown>;
}

export interface ProposalRepository {
  get(id: string): Promise<ProposalEnvelope | null>;
  insert<T extends ProposalType>(
    transaction: RepositoryTransaction,
    proposal: ProposalEnvelope<T>,
    idempotencyId: string,
  ): Promise<void>;
}

export function createProposalRepository(_database: RepositoryConnection): ProposalRepository {
  return {
    async get(id) {
      const row = await _database.getFirstAsync<ProposalRow>(
        `SELECT id, type, source_id, source_revision, evidence_ids_json,
           evidence_fingerprint, reasoning, effect_json, ambiguity, admission,
           resolution, revalidation, created_at, updated_at
         FROM proposals WHERE id = $id`,
        { $id: id },
      );
      if (row === null) return null;
      return {
        id: row.id,
        type: row.type,
        sourceId: row.source_id,
        sourceRevision: row.source_revision,
        evidenceIds: parseEvidenceIds(row.evidence_ids_json),
        evidenceFingerprint: row.evidence_fingerprint,
        reasoning: row.reasoning,
        effect: parseEffect(row.effect_json) as never,
        ambiguity: row.ambiguity,
        admission: row.admission,
        resolution: row.resolution,
        revalidation: row.revalidation,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
      };
    },

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
