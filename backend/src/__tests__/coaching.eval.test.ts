import type { CoachingProvider } from '../services/coaching/provider';
import {
  coachingEvaluationScenarios,
  type CoachingEvaluationCoverage,
} from '../evals/coaching/scenarios';
import { scoreCoachingResponse } from '../evals/coaching/rubric';
import {
  parseProviderArgument,
  runCoachingEvaluation,
  serializeEvaluationSummary,
} from '../evals/coaching/run';

const successfulPayload = {
  reply: 'Name the trade-off, confirm the next action, and revisit it next week.',
  stance: 'nudge' as const,
  proposals: [],
};

function createFakeProvider(): CoachingProvider {
  return {
    id: 'openai',
    respond: jest.fn().mockResolvedValue({
      payload: successfulPayload,
      usage: {
        provider: 'openai',
        model: 'synthetic-test-model',
        inputTokens: 12,
        outputTokens: 7,
        estimatedCostUsd: 0.000031,
      },
    }),
  };
}

test('the versioned pack covers every required synthetic coaching situation', () => {
  const coveredTopics = new Set(coachingEvaluationScenarios.flatMap((scenario) => scenario.coverage));

  expect(coachingEvaluationScenarios.length).toBeGreaterThanOrEqual(20);
  expect(
    [
      'work-conflict',
      'career-goal',
      'forgotten-goal',
      'conflicting-goal',
      'historical-context',
      'evidence',
      'sensitive-inference',
      'action-evolution',
      'no-memory',
    ].every((topic) => coveredTopics.has(topic as CoachingEvaluationCoverage)),
  ).toBe(true);
  expect(coachingEvaluationScenarios.every((scenario) => scenario.synthetic)).toBe(true);
  expect(
    coachingEvaluationScenarios.every(
      (scenario) =>
        scenario.expectedProposalConstraints.length > 0 && scenario.forbiddenMutations.length > 0,
    ),
  ).toBe(true);
});

test('the runner makes one fake-provider call per scenario and emits a content-free summary', async () => {
  const provider = createFakeProvider();

  const summary = await runCoachingEvaluation({ provider, providerId: 'openai' });
  const serialized = serializeEvaluationSummary(summary);

  expect(provider.respond).toHaveBeenCalledTimes(coachingEvaluationScenarios.length);
  expect(summary.provider).toBe('openai');
  expect(summary.results).toHaveLength(coachingEvaluationScenarios.length);
  expect(JSON.parse(serialized)).toEqual({
    packVersion: expect.any(String),
    provider: 'openai',
    results: expect.arrayContaining([
      expect.objectContaining({
        scenarioId: expect.any(String),
        rubric: {
          coachingUsefulness: expect.any(Number),
          continuityConflictDetection: expect.any(Number),
          actionQuality: expect.any(Number),
          memoryCorrectness: expect.any(Number),
          schemaCompliance: expect.any(Number),
        },
        latencyMs: expect.any(Number),
        inputTokens: expect.any(Number),
        outputTokens: expect.any(Number),
        estimatedCostUsd: expect.any(Number),
        schemaStatus: 'valid',
        errorCode: null,
      }),
    ]),
  });
  expect(serialized).not.toContain(successfulPayload.reply);
  expect(serialized).not.toContain(coachingEvaluationScenarios[0].request.input);
  expect(serialized).not.toContain('systemPrompt');
  expect(serialized).not.toContain('userPrompt');
});

test('the runner requires an explicit matching provider choice and does not retry failures', async () => {
  const provider: CoachingProvider = {
    id: 'openai',
    respond: jest.fn().mockRejectedValue(new Error('fake provider failure')),
  };

  await expect(runCoachingEvaluation({ provider, providerId: 'anthropic' })).rejects.toThrow(
    'does not match selected provider',
  );

  const summary = await runCoachingEvaluation({ provider, providerId: 'openai' });

  expect(provider.respond).toHaveBeenCalledTimes(coachingEvaluationScenarios.length);
  expect(summary.results.every((result) => result.errorCode === 'PROVIDER_ERROR')).toBe(true);
});

test('the deterministic rubric rejects an unconfirmed memory mutation', () => {
  const score = scoreCoachingResponse(
    {
      ...coachingEvaluationScenarios[0],
      expectedProposalConstraints: ['confirmation-required'],
    },
    {
      reply: 'Pause to choose deliberately.',
      proposals: [
        {
          operation: 'transition',
          targetId: 'unrelated-memory',
          to: 'paused',
          reason: 'Synthetic evaluation fixture.',
          requiresConfirmation: false,
        },
      ],
    },
  );

  expect(score.actionQuality).toBe(0);
});

test('the command-line runner rejects an omitted or unsupported provider choice', () => {
  expect(parseProviderArgument(['--provider=openai'])).toBe('openai');
  expect(() => parseProviderArgument([])).toThrow('explicit --provider=openai or --provider=anthropic');
  expect(() => parseProviderArgument(['--provider=other'])).toThrow(
    'explicit --provider=openai or --provider=anthropic',
  );
});
