import type {
  CoachingRelevance,
  CoachingResponse,
  CoachingResponseMode,
  ContextSufficiency,
  MemoryDelta,
  OutcomeDelta,
} from '@taisa/shared';
import type { CoachingEvaluationScenario } from './scenarios';

export interface CoachingRubricScores {
  coachingUsefulness: number;
  continuityConflictDetection: number;
  actionQuality: number;
  memoryCorrectness: number;
  schemaCompliance: number;
  responseMode: number;
  relevance: number;
  contextSufficiency: number;
  responseInvariants: number;
  stance: number;
  proposalInvariants: number;
}

type CoachingEvaluationPayload = {
  mode: CoachingResponseMode;
  relevance: CoachingRelevance;
  contextSufficiency: ContextSufficiency;
  reply: string;
  stance: CoachingResponse['stance'];
  proposals: Array<MemoryDelta | OutcomeDelta>;
};

function proposalTargets(proposals: CoachingEvaluationPayload['proposals']): Array<{ operation: MemoryDelta['operation']; targetId: string }> {
  const targets: Array<{ operation: MemoryDelta['operation']; targetId: string }> = [];
  for (const proposal of proposals) {
    if (proposal.operation === 'propose' && proposal.candidate.supersedesId) {
      targets.push({ operation: proposal.operation, targetId: proposal.candidate.supersedesId });
    } else if (proposal.operation === 'transition' || proposal.operation === 'support') {
      targets.push({ operation: proposal.operation, targetId: proposal.targetId });
    }
  }
  return targets;
}

export function scoreCoachingResponse(
  scenario: CoachingEvaluationScenario,
  payload: CoachingEvaluationPayload,
): CoachingRubricScores {
  const { expected } = scenario;
  const operations = payload.proposals.map((proposal) => proposal.operation);
  const targets = proposalTargets(payload.proposals);
  const targetIds = targets.map((target) => target.targetId);
  const modeMatches = payload.mode === expected.mode;
  const relevanceMatches = expected.allowedRelevance.includes(payload.relevance);
  const contextSufficiencyMatches = expected.allowedContextSufficiency.includes(payload.contextSufficiency);
  const allowedStance = expected.allowedStances.includes(payload.stance);
  const requiredStance = !expected.requiredStance || payload.stance === expected.requiredStance;
  const allowedOperations = operations.every((operation) =>
    expected.allowedProposalOperations.includes(operation));
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
  const responseInvariantMet = payload.mode === 'coach'
    ? payload.relevance !== 'outside-scope' && payload.contextSufficiency !== 'insufficient' && payload.stance !== null
    : payload.mode === 'clarify'
      ? payload.contextSufficiency === 'insufficient' && payload.stance === null && payload.proposals.length === 0
      : payload.relevance === 'outside-scope' && payload.contextSufficiency !== 'insufficient' && payload.stance === null && payload.proposals.length === 0;
  const stanceMatches = allowedStance && requiredStance;
  const proposalInvariantsMet = allowedOperations && requiredOperations && requiredTargets && requiredTypes && requiredProvenance &&
    !invalidTarget && !proposedMemoryInvalid && !noProposalViolation &&
    (!expected.requireConfirmationForMutations || !unconfirmedMutation);
  const constraintsMet = modeMatches && relevanceMatches && contextSufficiencyMatches && responseInvariantMet &&
    stanceMatches && proposalInvariantsMet;

  return {
    coachingUsefulness: expected.manualReviewRequired ? 0 : constraintsMet ? 1 : 0,
    continuityConflictDetection: expected.continuityRequired && constraintsMet ? 1 : 0,
    actionQuality: noProposalViolation || !allowedOperations || !requiredOperations || !requiredTypes || !requiredProvenance || (expected.requireConfirmationForMutations && unconfirmedMutation) ? 0 : 1,
    memoryCorrectness: invalidTarget || proposedMemoryInvalid || !requiredTypes || !requiredProvenance || (expected.noInventedMemory && proposesMemory) ? 0 : 1,
    schemaCompliance: 1,
    responseMode: modeMatches ? 1 : 0,
    relevance: relevanceMatches ? 1 : 0,
    contextSufficiency: contextSufficiencyMatches ? 1 : 0,
    responseInvariants: responseInvariantMet && modeMatches && relevanceMatches && contextSufficiencyMatches &&
      stanceMatches && proposalInvariantsMet ? 1 : 0,
    stance: stanceMatches ? 1 : 0,
    proposalInvariants: proposalInvariantsMet ? 1 : 0,
  };
}
