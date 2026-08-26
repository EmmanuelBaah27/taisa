import type { ProposalEnvelope } from './proposals';
import type { WorkRecordKind, WorkStatus } from './work';

export type OrganizationScope = 'conversation_task' | 'week';

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
  records: OrganizationRecord[];
  conversations: OrganizationConversation[];
}

export interface OrganizationResponse {
  requestId: string;
  proposals: ProposalEnvelope[];
}
