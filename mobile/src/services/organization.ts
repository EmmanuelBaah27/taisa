import type {
  OrganizationProposalCandidate,
  OrganizationRequest,
  OrganizationResponse,
  ProposalEnvelope,
} from '@taisa/shared';

import api from './api';
import { withTaisaDatabase } from '../db/openDatabase';
import type { ExclusiveTransactionConnection, RepositoryConnection, RepositoryTransaction } from '../db/types';
import { withRepositoryTransaction } from '../db/types';
import { admitProposal } from '../domain/proposals/proposalPolicy';
import { createProposalRepository } from '../repositories/proposalRepository';
import { fingerprintMutationPayload } from '../repositories/mutationFingerprint';
import { createHomeOperationService } from './homeOperations';

interface HttpClient {
  post(path: string, body: unknown, config?: unknown): Promise<{ data: unknown }>;
}

export interface OrganizationPreview {
  request: OrganizationRequest;
  approved: boolean;
}

export class OrganizationClientError extends Error {
  constructor(readonly code: 'ORGANIZATION_REQUEST_FAILED' | 'INVALID_ORGANIZATION_RESPONSE') {
    super(code);
    this.name = 'OrganizationClientError';
  }
}

function object(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function validProposal(value: unknown): value is OrganizationProposalCandidate {
  const proposal = object(value);
  return proposal !== null
    && typeof proposal.id === 'string'
    && typeof proposal.type === 'string'
    && typeof proposal.sourceId === 'string'
    && Number.isSafeInteger(proposal.sourceRevision)
    && Array.isArray(proposal.evidenceIds)
    && proposal.evidenceIds.every((id) => typeof id === 'string')
    && object(proposal.effect) !== null;
}

function validatedResponse(value: unknown, requestId: string): OrganizationResponse | null {
  const envelope = object(value);
  const data = envelope?.success === true ? object(envelope.data) : null;
  if (
    data === null
    || data.requestId !== requestId
    || !Array.isArray(data.proposals)
    || !data.proposals.every(validProposal)
  ) return null;
  return data as unknown as OrganizationResponse;
}

export function createOrganizationClient(http: HttpClient) {
  return async function submitOrganizationPreview(preview: OrganizationPreview) {
    if (!preview.approved) return { kind: 'cancelled' as const };
    try {
      const result = await http.post('/organization/analyze', preview.request, {
        headers: { 'x-request-id': preview.request.requestId },
      });
      const response = validatedResponse(result.data, preview.request.requestId);
      if (response === null) throw new OrganizationClientError('INVALID_ORGANIZATION_RESPONSE');
      return { kind: 'received' as const, response };
    } catch (error) {
      if (error instanceof OrganizationClientError) throw error;
      throw new OrganizationClientError('ORGANIZATION_REQUEST_FAILED');
    }
  };
}

function suppliedRevision(request: OrganizationRequest, sourceId: string): number | null {
  return request.records.find((item) => item.id === sourceId)?.revision
    ?? request.conversations.find((item) => item.id === sourceId)?.revision
    ?? null;
}

function locallyApplicable(
  database: RepositoryConnection,
  request: OrganizationRequest,
  candidate: OrganizationProposalCandidate,
): Promise<boolean> {
  if (suppliedRevision(request, candidate.sourceId) !== candidate.sourceRevision) {
    return Promise.resolve(false);
  }
  const suppliedIds = new Set([
    ...request.records.map((item) => item.id),
    ...request.conversations.map((item) => item.id),
  ]);
  if (candidate.evidenceIds.length === 0 || candidate.evidenceIds.some((id) => !suppliedIds.has(id))) {
    return Promise.resolve(false);
  }
  const effect = candidate.effect as Record<string, unknown>;
  if ('recordId' in effect && !request.records.some((item) => item.id === effect.recordId)) {
    return Promise.resolve(false);
  }
  if ('conversationId' in effect && !request.conversations.some((item) => item.id === effect.conversationId)) {
    return Promise.resolve(false);
  }
  const projectId = 'projectId' in effect ? effect.projectId : null;
  if (typeof projectId !== 'string') return Promise.resolve(true);
  return database.getFirstAsync<{ id: string }>(
    'SELECT id FROM projects WHERE id = $id', { $id: projectId },
  ).then((row) => row !== null);
}

async function persistCandidate(
  transaction: RepositoryTransaction,
  request: OrganizationRequest,
  candidate: OrganizationProposalCandidate,
): Promise<ProposalEnvelope | null> {
  const fingerprint = await fingerprintMutationPayload({
    type: candidate.type, effect: candidate.effect, evidenceIds: [...candidate.evidenceIds].sort(),
  });
  const repository = createProposalRepository(transaction);
  const rows = await transaction.getAllAsync<{ id: string }>(
    'SELECT id FROM proposals WHERE type = $type AND evidence_fingerprint = $fingerprint',
    { $type: candidate.type, $fingerprint: fingerprint },
  );
  const existing = (await Promise.all(rows.map((row) => repository.get(row.id))))
    .filter((item): item is ProposalEnvelope => item !== null);
  const incoming = {
    ...candidate,
    evidenceFingerprint: fingerprint,
    admission: 'pending', resolution: 'unapplied', revalidation: 'valid',
    createdAt: request.submittedAt, updatedAt: request.submittedAt,
  } as ProposalEnvelope;
  const decision = admitProposal(incoming, existing as never);
  if (decision.kind === 'suppressed') return null;
  if (decision.kind === 'consolidated') {
    await transaction.runAsync(
      `UPDATE proposals SET evidence_ids_json = $evidenceIds, updated_at = $updatedAt WHERE id = $id`,
      { $id: decision.proposal.id, $evidenceIds: JSON.stringify(decision.proposal.evidenceIds),
        $updatedAt: request.submittedAt },
    );
    return decision.proposal;
  }
  await repository.insert(transaction, decision.proposal, `${request.requestId}:${candidate.id}`);
  return decision.proposal;
}

export async function admitOrganizationResponse(
  database: ExclusiveTransactionConnection,
  request: OrganizationRequest,
  response: OrganizationResponse,
): Promise<ProposalEnvelope[]> {
  const applicable: OrganizationProposalCandidate[] = [];
  for (const candidate of response.proposals) {
    if (await locallyApplicable(database, request, candidate)) applicable.push(candidate);
  }
  return withRepositoryTransaction(database, async (transaction) => {
    const admitted: Array<ProposalEnvelope | null> = [];
    for (const candidate of applicable) {
      admitted.push(await persistCandidate(transaction, request, candidate));
    }
    return admitted.filter((item): item is ProposalEnvelope => item !== null);
  });
}

export async function executeEligibleStrongLinks(
  database: ExclusiveTransactionConnection,
  proposals: ProposalEnvelope[],
  now: string,
): Promise<ProposalEnvelope[]> {
  const remaining: ProposalEnvelope[] = [];
  for (const proposal of proposals) {
    if (proposal.type !== 'task_conversation_link' || proposal.ambiguity !== 'strong') {
      remaining.push(proposal);
      continue;
    }
    const effect = proposal.effect as {
      recordId: string;
      conversationId: string;
      contribution: 'planning' | 'status' | 'blocker' | 'decision' | 'outcome' | 'evidence';
    };
    const current = await database.getFirstAsync<{ revision: number }>(
      'SELECT revision FROM work_records WHERE id = $id', { $id: effect.recordId },
    );
    if (current === null) {
      remaining.push(proposal);
      continue;
    }
    try {
      await createHomeOperationService(database).execute({
        id: `${proposal.id}:delegated`, operation: 'apply_strong_task_conversation_link',
        targetId: effect.recordId, sourceId: proposal.sourceId,
        expectedRevision: current.revision, ambiguity: 'strong', requestedAt: now,
        payload: {
          conversationId: effect.conversationId,
          contribution: effect.contribution,
        },
        proposalId: proposal.id,
      });
    } catch {
      remaining.push(proposal);
    }
  }
  return remaining;
}

const submitOrganization = createOrganizationClient(api);

export async function requestOrganization(preview: OrganizationPreview) {
  const result = await submitOrganization(preview);
  if (result.kind === 'cancelled') return result;
  const proposals = await withTaisaDatabase(async (database) => {
    const admitted = await admitOrganizationResponse(database, preview.request, result.response);
    return executeEligibleStrongLinks(database, admitted, preview.request.submittedAt);
  });
  return { kind: 'admitted' as const, requestId: result.response.requestId, proposals };
}
