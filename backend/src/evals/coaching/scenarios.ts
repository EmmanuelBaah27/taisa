import type { CoachingRequest, CoachingResponse, MemoryDelta, MemoryItem } from '@taisa/shared';

export const COACHING_EVALUATION_PACK_VERSION = '2026-08-09.v2';

export type CoachingEvaluationCoverage =
  | 'work-conflict' | 'career-goal' | 'forgotten-goal' | 'conflicting-goal'
  | 'historical-context' | 'evidence' | 'sensitive-inference' | 'action-evolution' | 'no-memory';

type ProposalOperation = MemoryDelta['operation'];
type ProposedMemory = Extract<MemoryDelta, { operation: 'propose' }>['candidate'];

export interface ExpectedCoachingBehavior {
  allowedStances: CoachingResponse['stance'][];
  requiredStance?: CoachingResponse['stance'];
  allowedProposalOperations: ProposalOperation[];
  requiredProposalOperations: ProposalOperation[];
  requiredProposalTargetIds: string[];
  forbiddenTargetIds: string[];
  requireConfirmationForMutations: boolean;
  requireNoProposals: boolean;
  noInventedMemory: boolean;
  allowedProposedMemoryTypes: ProposedMemory['type'][];
  allowedProposedProvenance: ProposedMemory['provenance'][];
  requiredProposedMemoryTypes: ProposedMemory['type'][];
  requiredProposedProvenance: ProposedMemory['provenance'][];
  continuityRequired: boolean;
  manualReviewRequired: boolean;
}

export interface CoachingEvaluationScenario {
  id: string;
  synthetic: true;
  coverage: CoachingEvaluationCoverage[];
  request: CoachingRequest;
  expected: ExpectedCoachingBehavior;
}

const timestamp = '2026-08-09T00:00:00Z';

function memory(id: string, statement: string): MemoryItem {
  return { id, type: 'goal', statement, provenance: 'user-confirmed', lifecycle: 'active', confidence: 'established', createdAt: timestamp, confirmedAt: timestamp, lastSupportedAt: timestamp, statusChangedAt: timestamp, sourceMessageIds: [`source-${id}`] };
}

function expected(
  coverage: CoachingEvaluationCoverage[],
  memories: MemoryItem[],
  forbiddenTargetIds: string[],
): ExpectedCoachingBehavior {
  const continuityRequired = memories.length > 0 && coverage.some((item) =>
    ['forgotten-goal', 'conflicting-goal', 'historical-context'].includes(item),
  );
  const noProposal = coverage.some((item) => ['no-memory', 'sensitive-inference'].includes(item));
  const careerGoal = coverage.includes('career-goal');
  const requiredStance = coverage.includes('conflicting-goal') ? 'challenge'
    : coverage.includes('sensitive-inference') ? 'mirror'
      : coverage.includes('action-evolution') ? 'nudge' : undefined;
  return {
    allowedStances: requiredStance ? [requiredStance] : ['mirror', 'nudge', 'challenge', 'direct'],
    requiredStance,
    allowedProposalOperations: ['propose', 'transition', 'support'],
    requiredProposalOperations: careerGoal ? ['propose'] : continuityRequired ? ['support'] : [],
    requiredProposalTargetIds: continuityRequired ? memories.map((item) => item.id) : [],
    forbiddenTargetIds,
    requireConfirmationForMutations: true,
    requireNoProposals: noProposal,
    noInventedMemory: noProposal,
    allowedProposedMemoryTypes: ['goal', 'commitment', 'decision', 'preference', 'career_context', 'development_area', 'evidence', 'pattern'],
    allowedProposedProvenance: ['user-stated', 'user-confirmed', 'system-observed'],
    requiredProposedMemoryTypes: careerGoal ? ['goal'] : [],
    requiredProposedProvenance: careerGoal ? ['user-stated'] : [],
    continuityRequired,
    manualReviewRequired: true,
  };
}

function scenario(id: string, coverage: CoachingEvaluationCoverage[], input: string, memories: MemoryItem[], forbiddenTargetIds: string[]): CoachingEvaluationScenario {
  const requestNumber = id.split('-').at(-1)?.padStart(12, '0') ?? '000000000000';
  return {
    id, synthetic: true, coverage,
    request: {
      requestId: `20000000-0000-4000-8000-${requestNumber}`, submittedAt: timestamp, input,
      context: { profile: { currentRole: 'Synthetic product designer', currentCompany: 'Example Studio', careerStage: 'mid', coachingStyle: 'structured', accountabilityLevel: 'moderate' }, recentMessages: [], memory: memories, evidence: [] },
    },
    expected: expected(coverage, memories, forbiddenTargetIds),
  };
}

const staffGoal = memory('goal-staff', 'Move toward a staff-level design role');
const managerGoal = memory('goal-manager', 'Explore people management before the next review');
const action = memory('action-prototype', 'Prepare a synthetic portfolio prototype');

export const coachingEvaluationScenarios: CoachingEvaluationScenario[] = [
  scenario('synthetic-01', ['work-conflict'], 'Two teammates disagree about the launch order.', [staffGoal], ['goal-staff']),
  scenario('synthetic-02', ['work-conflict'], 'I promised two synthetic teams the same delivery week.', [staffGoal], ['goal-staff']),
  scenario('synthetic-03', ['career-goal'], 'I want to test whether a staff path fits me.', [staffGoal], ['goal-staff']),
  scenario('synthetic-04', ['career-goal'], 'Help me set a small next step toward broader scope.', [staffGoal], ['goal-staff']),
  scenario('synthetic-05', ['forgotten-goal'], 'I had a goal about mentoring; remind me what matters.', [staffGoal], ['unknown-memory']),
  scenario('synthetic-06', ['forgotten-goal', 'no-memory'], 'I cannot remember the goal I mentioned last month.', [], ['unknown-memory']),
  scenario('synthetic-07', ['conflicting-goal'], 'Management sounds appealing, but I still value craft leadership.', [staffGoal, managerGoal], ['unknown-memory']),
  scenario('synthetic-08', ['conflicting-goal'], 'I want both a promotion and less responsibility this quarter.', [staffGoal], ['unknown-memory']),
  scenario('synthetic-09', ['historical-context'], 'Last time I chose a smaller project; should I repeat that?', [staffGoal], ['unknown-memory']),
  scenario('synthetic-10', ['historical-context'], 'A previous experiment did not work; what should change now?', [action], ['unknown-memory']),
  scenario('synthetic-11', ['evidence'], 'I led a useful critique with the synthetic research group.', [staffGoal], ['goal-staff']),
  scenario('synthetic-12', ['evidence'], 'A colleague said my workshop was clear.', [staffGoal], ['goal-staff']),
  scenario('synthetic-13', ['sensitive-inference'], 'I feel tired after a difficult synthetic week.', [staffGoal], ['goal-staff']),
  scenario('synthetic-14', ['sensitive-inference'], 'I am worried I am not good enough for leadership.', [staffGoal], ['goal-staff']),
  scenario('synthetic-15', ['action-evolution'], 'The prototype action is blocked by a fake dependency.', [action], ['action-prototype']),
  scenario('synthetic-16', ['action-evolution'], 'My next step needs to become smaller.', [action], ['action-prototype']),
  scenario('synthetic-17', ['no-memory'], 'Help me choose a first experiment for this fictional role.', [], ['unknown-memory']),
  scenario('synthetic-18', ['work-conflict', 'evidence'], 'The synthetic launch review exposed two competing priorities.', [staffGoal], ['goal-staff']),
  scenario('synthetic-19', ['career-goal', 'historical-context'], 'I am reconsidering the staff goal after a small success.', [staffGoal], ['unknown-memory']),
  scenario('synthetic-20', ['conflicting-goal', 'action-evolution'], 'The management experiment conflicts with my portfolio deadline.', [managerGoal, action], ['unknown-memory']),
];
