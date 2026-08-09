import type { MemoryDelta } from '@taisa/shared';
import type { CoachingEvaluationScenario } from './scenarios';

export interface CoachingRubricScores {
  coachingUsefulness: number;
  continuityConflictDetection: number;
  actionQuality: number;
  memoryCorrectness: number;
  schemaCompliance: number;
}

export function scoreCoachingResponse(
  scenario: CoachingEvaluationScenario,
  payload: { reply: string; proposals: MemoryDelta[] },
): CoachingRubricScores {
  const targetIds = payload.proposals.flatMap((proposal) =>
    proposal.operation === 'propose' ? [] : [proposal.targetId],
  );
  const touchesForbiddenMemory = targetIds.some((id) => scenario.forbiddenMutations.includes(id));
  const hasContinuityContext = scenario.coverage.some((coverage) =>
    ['forgotten-goal', 'conflicting-goal', 'historical-context'].includes(coverage),
  );

  return {
    coachingUsefulness: payload.reply.trim().length > 0 ? 1 : 0,
    continuityConflictDetection: hasContinuityContext ? (payload.reply.trim().length > 0 ? 1 : 0) : 1,
    actionQuality:
      scenario.expectedProposalConstraints.includes('confirmation-required') &&
      payload.proposals.some(
        (proposal) => proposal.operation !== 'support' && proposal.requiresConfirmation === false,
      )
        ? 0
        : 1,
    memoryCorrectness: touchesForbiddenMemory ? 0 : 1,
    schemaCompliance: 1,
  };
}
