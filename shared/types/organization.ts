import type { ProposalPayloadRegistry, ProposalType } from './proposals';
import type { WorkRecordKind, WorkStatus } from './work';

export type OrganizationScope = 'conversation' | 'task' | 'week';

export type OrganizationProposalCandidate = {
  [T in ProposalType]: {
    id: string;
    type: T;
    sourceId: string;
    sourceRevision: number;
    evidenceIds: string[];
    reasoning: string;
    ambiguity: 'strong' | 'ambiguous';
    effect: ProposalPayloadRegistry[T];
  }
}[ProposalType];

export interface OrganizationRecord {
  id: string;
  kind: WorkRecordKind;
  title: string;
  status: WorkStatus;
  revision: number;
  projectId: string | null;
}

export interface OrganizationConversation {
  id: string;
  summary: string;
  revision: number;
}

export interface OrganizationRequest {
  requestId: string;
  submittedAt: string;
  scope: OrganizationScope;
  scopeId: string | null;
  records: OrganizationRecord[];
  conversations: OrganizationConversation[];
}

export interface OrganizationResponse {
  requestId: string;
  proposals: OrganizationProposalCandidate[];
}
