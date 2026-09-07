import type { PermittedOperation, ReadinessPolicy } from '@taisa/shared';

function policy(operation: PermittedOperation): ReadinessPolicy {
  return {
    operation,
    version: 1,
    minimumRelevantExamples: 8,
    maximumEvidenceAgeDays: 30,
    maximumCorrections: 1,
    trialSampleSize: 5,
    contradictionsAllowed: 0,
  };
}

export const READINESS_POLICIES_V1: Readonly<Record<PermittedOperation, ReadinessPolicy>> = {
  complete_explicit_task: policy('complete_explicit_task'),
  associate_existing_project: policy('associate_existing_project'),
  apply_strong_task_conversation_link: policy('apply_strong_task_conversation_link'),
  update_explicit_followup_status: policy('update_explicit_followup_status'),
  update_explicit_blocker_status: policy('update_explicit_blocker_status'),
  update_explicit_project_status: policy('update_explicit_project_status'),
};
