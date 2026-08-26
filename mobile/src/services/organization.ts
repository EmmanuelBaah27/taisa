import type { OrganizationRequest, OrganizationResponse, ProposalEnvelope } from '@taisa/shared';

import api from './api';

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

function validProposal(value: unknown): value is ProposalEnvelope {
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

export const requestOrganization = createOrganizationClient(api);
