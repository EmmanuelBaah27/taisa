import type {
  OrganizationProposalCandidate,
  OrganizationRequest,
  OrganizationScope,
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

export interface OrganizationScopeSelection {
  requestId: string;
  submittedAt: string;
  scope: OrganizationScope;
  scopeId: string | null;
  period: OrganizationRequest['period'];
}

export class OrganizationClientError extends Error {
  constructor(readonly code: 'ORGANIZATION_REQUEST_FAILED' | 'INVALID_ORGANIZATION_RESPONSE') {
    super(code);
    this.name = 'OrganizationClientError';
  }
}

export class OrganizationScopeError extends Error {
  constructor(readonly code: 'INVALID_ORGANIZATION_SCOPE' | 'ORGANIZATION_SCOPE_TOO_LARGE') {
    super(code);
    this.name = 'OrganizationScopeError';
  }
}

type OrganizationRecordRow = {
  id: string; kind: OrganizationRequest['records'][number]['kind']; title: string;
  status: OrganizationRequest['records'][number]['status']; revision: number;
  project_id: string | null; planned_week: string | null;
};

type OrganizationConversationRow = { id: string; summary: string; revision: number };

const RECORD_SELECT = `SELECT id, kind, title, status, revision, project_id, planned_week
  FROM work_records`;
const CONVERSATION_SELECT = `SELECT c.id,
    COALESCE((SELECT m.content FROM messages m WHERE m.conversation_id = c.id
      AND m.lifecycle IN ('submitted', 'received') ORDER BY m.created_at DESC LIMIT 1),
      c.title, 'Conversation') AS summary,
    1 + (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id
      AND m.lifecycle IN ('submitted', 'received')) AS revision
  FROM conversations c`;

function mapOrganizationRecord(row: OrganizationRecordRow): OrganizationRequest['records'][number] {
  return { id: row.id, kind: row.kind, title: row.title, status: row.status,
    revision: row.revision, projectId: row.project_id, plannedWeek: row.planned_week };
}

function isMondaySunday(period: OrganizationRequest['period']) {
  if (period === null) return false;
  const start = new Date(`${period.startsOn}T00:00:00Z`);
  const end = new Date(`${period.endsOn}T00:00:00Z`);
  return start.getUTCDay() === 1 && end.getTime() - start.getTime() === 6 * 86_400_000;
}

export async function assembleOrganizationRequest(
  database: RepositoryConnection,
  selection: OrganizationScopeSelection,
): Promise<OrganizationRequest> {
  let recordRows: OrganizationRecordRow[];
  let conversationRows: OrganizationConversationRow[];
  if (selection.scope === 'conversation') {
    if (selection.scopeId === null || selection.period !== null) {
      throw new OrganizationScopeError('INVALID_ORGANIZATION_SCOPE');
    }
    recordRows = await database.getAllAsync<OrganizationRecordRow>(
      `${RECORD_SELECT} WHERE kind = 'task' AND status = 'open' ORDER BY updated_at DESC LIMIT 31`,
    );
    conversationRows = await database.getAllAsync<OrganizationConversationRow>(
      `${CONVERSATION_SELECT} WHERE c.id = $id`, { $id: selection.scopeId },
    );
    if (conversationRows.length !== 1) throw new OrganizationScopeError('INVALID_ORGANIZATION_SCOPE');
  } else if (selection.scope === 'task') {
    const period = selection.period;
    if (selection.scopeId === null || period === null || !isMondaySunday(period)) {
      throw new OrganizationScopeError('INVALID_ORGANIZATION_SCOPE');
    }
    recordRows = await database.getAllAsync<OrganizationRecordRow>(
      `${RECORD_SELECT} WHERE id = $id AND kind = 'task' AND status = 'open'
       AND planned_week = $startsOn`,
      { $id: selection.scopeId, $startsOn: period.startsOn },
    );
    if (recordRows.length !== 1) throw new OrganizationScopeError('INVALID_ORGANIZATION_SCOPE');
    conversationRows = await database.getAllAsync<OrganizationConversationRow>(
      `${CONVERSATION_SELECT} WHERE EXISTS (SELECT 1 FROM messages scoped
        WHERE scoped.conversation_id = c.id AND scoped.lifecycle = 'submitted'
          AND date(scoped.created_at) BETWEEN $startsOn AND $endsOn)
       ORDER BY (SELECT MAX(scoped.created_at) FROM messages scoped
         WHERE scoped.conversation_id = c.id AND scoped.lifecycle = 'submitted'
           AND date(scoped.created_at) BETWEEN $startsOn AND $endsOn) DESC LIMIT 21`,
      { $startsOn: period.startsOn, $endsOn: period.endsOn },
    );
  } else {
    const period = selection.period;
    if (selection.scopeId !== null || period === null || !isMondaySunday(period)) {
      throw new OrganizationScopeError('INVALID_ORGANIZATION_SCOPE');
    }
    recordRows = await database.getAllAsync<OrganizationRecordRow>(
      `${RECORD_SELECT} WHERE kind = 'task' AND status = 'open' AND planned_week = $startsOn
       ORDER BY updated_at DESC LIMIT 31`, { $startsOn: period.startsOn },
    );
    conversationRows = await database.getAllAsync<OrganizationConversationRow>(
      `${CONVERSATION_SELECT} WHERE EXISTS (SELECT 1 FROM messages scoped
        WHERE scoped.conversation_id = c.id AND scoped.lifecycle = 'submitted'
          AND date(scoped.created_at) BETWEEN $startsOn AND $endsOn)
       ORDER BY (SELECT MAX(scoped.created_at) FROM messages scoped
         WHERE scoped.conversation_id = c.id AND scoped.lifecycle = 'submitted'
           AND date(scoped.created_at) BETWEEN $startsOn AND $endsOn) DESC LIMIT 31`,
      { $startsOn: period.startsOn, $endsOn: period.endsOn },
    );
  }
  const recordLimit = 30;
  const conversationLimit = selection.scope === 'task' ? 20 : 30;
  if (recordRows.length > recordLimit || conversationRows.length > conversationLimit) {
    throw new OrganizationScopeError('ORGANIZATION_SCOPE_TOO_LARGE');
  }
  return { ...selection, records: recordRows.map(mapOrganizationRecord), conversations: conversationRows };
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

async function currentRevision(database: RepositoryConnection, request: OrganizationRequest, id: string) {
  if (request.records.some((item) => item.id === id)) {
    return (await database.getFirstAsync<{ revision: number }>(
      'SELECT revision FROM work_records WHERE id = $id', { $id: id },
    ))?.revision ?? null;
  }
  if (request.conversations.some((item) => item.id === id)) {
    const row = await database.getFirstAsync<{ revision: number }>(
      `SELECT 1 + COUNT(m.id) AS revision FROM conversations c
       LEFT JOIN messages m ON m.conversation_id = c.id
         AND m.lifecycle IN ('submitted', 'received')
       WHERE c.id = $id GROUP BY c.id`,
      { $id: id },
    );
    return row?.revision ?? null;
  }
  return null;
}

async function locallyApplicable(
  database: RepositoryConnection,
  request: OrganizationRequest,
  candidate: OrganizationProposalCandidate,
): Promise<boolean> {
  if (suppliedRevision(request, candidate.sourceId) !== candidate.sourceRevision) {
    return false;
  }
  const suppliedIds = new Set([
    ...request.records.map((item) => item.id),
    ...request.conversations.map((item) => item.id),
  ]);
  if (candidate.evidenceIds.length === 0 || candidate.evidenceIds.some((id) => !suppliedIds.has(id))) {
    return false;
  }
  const effect = candidate.effect as Record<string, unknown>;
  if ('recordId' in effect && !request.records.some((item) => item.id === effect.recordId)) {
    return false;
  }
  if ('conversationId' in effect && !request.conversations.some((item) => item.id === effect.conversationId)) {
    return false;
  }
  const affectedIds = new Set([candidate.sourceId, ...candidate.evidenceIds]);
  if (typeof effect.recordId === 'string') affectedIds.add(effect.recordId);
  if (typeof effect.conversationId === 'string') affectedIds.add(effect.conversationId);
  for (const id of affectedIds) {
    const supplied = suppliedRevision(request, id);
    if (supplied === null || await currentRevision(database, request, id) !== supplied) return false;
  }
  if (typeof effect.recordId === 'string' && typeof effect.conversationId === 'string') {
    const relationship = await database.getFirstAsync<{ id: string }>(
      `SELECT id FROM work_relationships
       WHERE record_id = $recordId AND conversation_id = $conversationId`,
      { $recordId: effect.recordId, $conversationId: effect.conversationId },
    );
    if (relationship !== null) return false;
  }
  const projectId = 'projectId' in effect ? effect.projectId : null;
  if (typeof projectId !== 'string') return true;
  return (await database.getFirstAsync<{ id: string }>(
    'SELECT id FROM projects WHERE id = $id', { $id: projectId },
  )) !== null;
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
  return withRepositoryTransaction(database, async (transaction) => {
    const admitted: Array<ProposalEnvelope | null> = [];
    for (const candidate of response.proposals) {
      if (!await locallyApplicable(transaction, request, candidate)) continue;
      admitted.push(await persistCandidate(transaction, request, candidate));
    }
    return admitted.filter((item): item is ProposalEnvelope => item !== null);
  });
}

export async function executeEligibleStrongLinks(
  database: ExclusiveTransactionConnection,
  proposals: ProposalEnvelope[],
  now: string,
  request: OrganizationRequest,
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
    const expectedRevision = suppliedRevision(request, effect.recordId);
    if (expectedRevision === null
      || await currentRevision(database, request, effect.recordId) !== expectedRevision
      || await currentRevision(database, request, effect.conversationId)
        !== suppliedRevision(request, effect.conversationId)
      || await database.getFirstAsync(
        `SELECT id FROM work_relationships
         WHERE record_id = $recordId AND conversation_id = $conversationId`,
        { $recordId: effect.recordId, $conversationId: effect.conversationId },
      ) !== null) {
      remaining.push(proposal);
      continue;
    }
    try {
      await createHomeOperationService(database).execute({
        id: `${proposal.id}:delegated`, operation: 'apply_strong_task_conversation_link',
        targetId: effect.recordId, sourceId: proposal.sourceId,
        expectedRevision, ambiguity: 'strong', requestedAt: now,
        payload: {
          conversationId: effect.conversationId,
          contribution: effect.contribution,
          expectedConversationRevision: suppliedRevision(request, effect.conversationId),
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
    return executeEligibleStrongLinks(database, admitted, preview.request.submittedAt, preview.request);
  });
  return { kind: 'admitted' as const, requestId: result.response.requestId, proposals };
}
