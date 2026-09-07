export type PermittedOperation =
  | 'complete_explicit_task'
  | 'associate_existing_project'
  | 'apply_strong_task_conversation_link'
  | 'update_explicit_followup_status'
  | 'update_explicit_blocker_status'
  | 'update_explicit_project_status';

export type CapabilityState =
  | 'learning'
  | 'ready'
  | 'permission_granted'
  | 'trial'
  | 'trusted'
  | 'ask_me';

export interface ReadinessPolicy {
  operation: PermittedOperation;
  version: number;
  minimumRelevantExamples: number;
  maximumEvidenceAgeDays: number;
  maximumCorrections: number;
  trialSampleSize: number;
  contradictionsAllowed: 0;
}

export interface CapabilitySnapshot {
  operation: PermittedOperation;
  policyVersion: number;
  state: CapabilityState;
  permissionGrantedAt: string | null;
  relevantExamples: number;
  corrections: number;
  contradictions: number;
  latestEvidenceAt: string | null;
  cleanTrialOutcomes: number;
  updatedAt: string;
}

export interface OperationReceipt {
  id: string;
  operation: PermittedOperation;
  targetId: string;
  sourceId: string;
  priorRevision: number;
  resultingRevision: number;
  visibility: 'trial' | 'history';
  undoable: boolean;
  undoneAt: string | null;
  createdAt: string;
}
