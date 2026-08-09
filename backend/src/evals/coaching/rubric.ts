import type { CoachingResponse, MemoryDelta } from '@taisa/shared';
import type { CoachingEvaluationScenario } from './scenarios';

export interface CoachingRubricScores { coachingUsefulness: number; continuityConflictDetection: number; actionQuality: number; memoryCorrectness: number; schemaCompliance: number; }

function proposalTargets(proposals: MemoryDelta[]): Array<{ operation: MemoryDelta['operation']; targetId: string }> {
  const targets: Array<{ operation: MemoryDelta['operation']; targetId: string }> = [];
  for (const proposal of proposals) {
    if (proposal.operation === 'propose' && proposal.candidate.supersedesId) {
      targets.push({ operation: proposal.operation, targetId: proposal.candidate.supersedesId });
    } else if (proposal.operation !== 'propose') {
      targets.push({ operation: proposal.operation, targetId: proposal.targetId });
    }
  }
  return targets;
}

export function scoreCoachingResponse(
  scenario: CoachingEvaluationScenario,
  payload: Pick<CoachingResponse, 'reply' | 'stance' | 'proposals'>,
): CoachingRubricScores {
  const { expected } = scenario;
  const operations = payload.proposals.map((proposal) => proposal.operation);
  const targets = proposalTargets(payload.proposals);
  const targetIds = targets.map((target) => target.targetId);
  const allowedStance = expected.allowedStances.includes(payload.stance);
  const requiredStance = !expected.requiredStance || payload.stance === expected.requiredStance;
  const allowedOperations = operations.every((operation) => expected.allowedProposalOperations.includes(operation));
  const requiredOperations = expected.requiredProposalOperations.every((operation) => operations.includes(operation));
  const requiredTargets = expected.requiredProposalTargetIds.every((targetId) => targetIds.includes(targetId));
  const invalidTarget = targets.some((target) =>
    expected.forbiddenTargetIdsByOperation[target.operation].includes(target.targetId) ||
    (expected.allowedTargetIdsByOperation[target.operation].length > 0 &&
      !expected.allowedTargetIdsByOperation[target.operation].includes(target.targetId)),
  );
  const unconfirmedMutation = payload.proposals.some((proposal) => proposal.operation !== 'support' && !proposal.requiresConfirmation);
  const proposedMemories = payload.proposals.filter((proposal): proposal is Extract<MemoryDelta, { operation: 'propose' }> => proposal.operation === 'propose');
  const proposedMemoryInvalid = payload.proposals.some((proposal) => proposal.operation === 'propose' &&
    (!expected.allowedProposedMemoryTypes.includes(proposal.candidate.type) || !expected.allowedProposedProvenance.includes(proposal.candidate.provenance)));
  const requiredTypes = expected.requiredProposedMemoryTypes.every((type) => proposedMemories.some((proposal) => proposal.candidate.type === type));
  const requiredProvenance = expected.requiredProposedProvenance.every((provenance) => proposedMemories.some((proposal) => proposal.candidate.provenance === provenance));
  const proposesMemory = proposedMemories.length > 0;
  const noProposalViolation = expected.requireNoProposals && payload.proposals.length > 0;
  const constraintsMet = allowedStance && requiredStance && allowedOperations && requiredOperations && requiredTargets && requiredTypes && requiredProvenance;

  return {
    coachingUsefulness: expected.manualReviewRequired ? 0 : constraintsMet ? 1 : 0,
    continuityConflictDetection: expected.continuityRequired && constraintsMet ? 1 : 0,
    actionQuality: noProposalViolation || !allowedOperations || !requiredOperations || !requiredTypes || !requiredProvenance || (expected.requireConfirmationForMutations && unconfirmedMutation) ? 0 : 1,
    memoryCorrectness: invalidTarget || proposedMemoryInvalid || !requiredTypes || !requiredProvenance || (expected.noInventedMemory && proposesMemory) ? 0 : 1,
    schemaCompliance: 1,
  };
}
