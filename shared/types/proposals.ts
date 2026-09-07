export interface ProposalPayloadRegistry {
  project_association: { recordId: string; projectId: string };
  task_conversation_link: {
    recordId: string;
    conversationId: string;
    contribution: 'planning' | 'status' | 'blocker' | 'decision' | 'outcome' | 'evidence';
  };
  task_completion: { recordId: string };
  followup_status_update: { recordId: string; status: 'waiting' | 'completed' | 'rescheduled' | 'cancelled' };
  blocker_status_update: { recordId: string; status: 'active' | 'being_resolved' | 'resolved' | 'no_longer_relevant' };
  project_status_update: { projectId: string; status: 'active' | 'archived' };
  work_record: { kind: 'task' | 'followup' | 'blocker' | 'decision'; title: string; projectId: string | null };
  insight: { title: string; body: string };
  growth_reflection: { title: string; body: string };
  experiment: { title: string; hypothesis: string };
}

export type ProposalType = keyof ProposalPayloadRegistry;

export interface ProposalEnvelope<T extends ProposalType = ProposalType> {
  id: string;
  type: T;
  sourceId: string;
  sourceRevision: number;
  evidenceIds: string[];
  evidenceFingerprint: string;
  reasoning: string;
  effect: ProposalPayloadRegistry[T];
  ambiguity: 'strong' | 'ambiguous';
  admission: 'pending' | 'admitted' | 'suppressed';
  resolution: 'unapplied' | 'accepted' | 'rejected' | 'expired';
  revalidation: 'valid' | 'stale' | 'conflicted';
  createdAt: string;
  updatedAt: string;
}
