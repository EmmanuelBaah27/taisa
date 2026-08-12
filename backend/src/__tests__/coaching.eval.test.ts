import {
  createProviderForId,
  type CoachingProvider,
} from '../services/coaching/provider';
import {
  coachingEvaluationScenarios,
  type CoachingEvaluationCoverage,
} from '../evals/coaching/scenarios';
import { scoreCoachingResponse } from '../evals/coaching/rubric';
import {
  parseProviderArgument,
  parseEvaluationBudgetArgument,
  runCoachingEvaluation,
  runEvaluationCli,
  serializeEvaluationSummary,
} from '../evals/coaching/run';

const successfulPayload = {
  reply: 'Name the trade-off, confirm the next action, and revisit it next week.',
  stance: 'nudge' as const,
  proposals: [],
};

function createFakeProvider(id: 'openai' | 'anthropic' = 'openai'): CoachingProvider {
  return {
    id,
    respond: jest.fn().mockResolvedValue({
      payload: successfulPayload,
      usage: {
        provider: id,
        model: 'synthetic-test-model',
        inputTokens: 12,
        outputTokens: 7,
        estimatedCostUsd: 0.000031,
      },
    }),
  };
}

test('the versioned pack covers every required synthetic coaching situation with executable constraints', () => {
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
        scenario.expected.allowedStances.length > 0 &&
        (scenario.request.context.memory.length === 0 ||
          scenario.expected.forbiddenTargetIdsByOperation.transition.length > 0),
    ),
  ).toBe(true);
});

test('the runner makes one fake-provider call per scenario and emits only allowlisted summary keys', async () => {
  const provider = createFakeProvider();
  const summary = await runCoachingEvaluation({ provider, providerId: 'openai' });
  const serialized = serializeEvaluationSummary(summary);
  const parsed = JSON.parse(serialized);

  expect(provider.respond).toHaveBeenCalledTimes(coachingEvaluationScenarios.length);
  expect(Object.keys(parsed).sort()).toEqual(['packVersion', 'provider', 'results']);
  expect(Object.keys(parsed.results[0]).sort()).toEqual([
    'errorCode',
    'estimatedCostUsd',
    'inputTokens',
    'latencyMs',
    'outputTokens',
    'rubric',
    'scenarioId',
    'schemaStatus',
  ]);
  expect(Object.keys(parsed.results[0].rubric).sort()).toEqual([
    'actionQuality',
    'coachingUsefulness',
    'continuityConflictDetection',
    'memoryCorrectness',
    'schemaCompliance',
  ]);
  expect(serialized).not.toContain(successfulPayload.reply);
  expect(serialized).not.toContain(coachingEvaluationScenarios[0].request.input);
  expect(serialized).not.toContain('systemPrompt');
  expect(serialized).not.toContain('userPrompt');
});

test('a fluent hallucinated reply earns no automatic usefulness or continuity credit', () => {
  const conflictScenario = coachingEvaluationScenarios.find((scenario) => scenario.id === 'synthetic-07')!;

  const score = scoreCoachingResponse(conflictScenario, {
    reply: 'Everything will work out brilliantly.',
    stance: 'mirror',
    proposals: [],
  });

  expect(score.coachingUsefulness).toBe(0);
  expect(score.continuityConflictDetection).toBe(0);
});

test('the rubric rejects an invented propose mutation that supersedes a forbidden target', () => {
  const score = scoreCoachingResponse(coachingEvaluationScenarios[0], {
    reply: 'A concise synthetic response.',
    stance: 'nudge',
    proposals: [
      {
        operation: 'propose',
        candidate: {
          type: 'goal',
          statement: 'Invented replacement goal',
          provenance: 'ai-inferred',
          lifecycle: 'active',
          confidence: 'tentative',
          sourceMessageIds: ['synthetic-source'],
          supersedesId: 'goal-staff',
        },
        reason: 'Synthetic evaluation fixture.',
        requiresConfirmation: true,
      },
    ],
  });

  expect(score.memoryCorrectness).toBe(0);
});

test('the rubric enforces required proposed memory type and provenance', () => {
  const careerScenario = coachingEvaluationScenarios.find((scenario) => scenario.id === 'synthetic-03')!;
  const score = scoreCoachingResponse(careerScenario, {
    reply: 'A concise synthetic response.',
    stance: 'nudge',
    proposals: [{
      operation: 'propose',
      candidate: {
        type: 'preference', statement: 'Invented preference', provenance: 'user-confirmed',
        lifecycle: 'active', confidence: 'tentative', sourceMessageIds: ['synthetic-source'],
      },
      reason: 'Synthetic evaluation fixture.', requiresConfirmation: true,
    }],
  });

  expect(score.actionQuality).toBe(0);
  expect(score.memoryCorrectness).toBe(0);
});

const protectedMemoryCases = ['synthetic-05', 'synthetic-07', 'synthetic-08', 'synthetic-09', 'synthetic-10', 'synthetic-19'] as const;
const targetBearingOperations = ['transition', 'support', 'propose'] as const;

function proposalTargeting(
  operation: (typeof targetBearingOperations)[number],
  targetId: string,
) {
  if (operation === 'support') {
    return {
      operation, targetId, sourceMessageId: 'synthetic-source',
      reason: 'Synthetic evaluation fixture.', requiresConfirmation: false as const,
    };
  }
  if (operation === 'transition') {
    return {
      operation, targetId, to: 'paused' as const,
      reason: 'Synthetic evaluation fixture.', requiresConfirmation: true,
    };
  }
  return {
    operation,
    candidate: {
      type: 'goal' as const, statement: 'Synthetic proposal', provenance: 'user-stated' as const,
      lifecycle: 'proposed' as const, confidence: 'tentative' as const,
      sourceMessageIds: ['synthetic-source'], supersedesId: targetId,
    },
    reason: 'Synthetic evaluation fixture.', requiresConfirmation: true,
  };
}

test.each(
  protectedMemoryCases.flatMap((scenarioId) =>
    targetBearingOperations.map((operation) => [scenarioId, operation, operation === 'support' ? 1 : 0] as const),
  ),
)('scenario %s scores protected known-memory %s targets accurately', (scenarioId, operation, expectedScore) => {
  const scenario = coachingEvaluationScenarios.find((candidate) => candidate.id === scenarioId)!;
  const targetId = scenario.request.context.memory[0].id;
  const score = scoreCoachingResponse({
    ...scenario,
    expected: {
      ...scenario.expected,
      requiredProposedMemoryTypes: [],
      requiredProposedProvenance: [],
    },
  }, {
    reply: 'Synthetic response.',
    stance: scenario.expected.requiredStance ?? 'nudge',
    proposals: [proposalTargeting(operation, targetId)],
  });

  expect(score.memoryCorrectness).toBe(expectedScore);
});

test('the runner records invalid schemas without exposing their payload', async () => {
  const provider: CoachingProvider = {
    id: 'openai',
    respond: jest.fn().mockResolvedValue({
      payload: { reply: '', stance: 'unknown', proposals: [], secret: 'do-not-print' },
      usage: {
        provider: 'openai',
        model: 'synthetic-test-model',
        inputTokens: 12,
        outputTokens: 7,
        estimatedCostUsd: 0.000031,
      },
    }),
  };

  const summary = await runCoachingEvaluation({ provider, providerId: 'openai' });

  expect(summary.results.every((result) => result.schemaStatus === 'invalid')).toBe(true);
  expect(summary.results.every((result) => result.errorCode === 'INVALID_SCHEMA')).toBe(true);
  expect(serializeEvaluationSummary(summary)).not.toContain('do-not-print');
});

test('the runner requires a matching provider choice and does not retry failures', async () => {
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

test.each(['openai', 'anthropic'] as const)(
  'the CLI selects the explicit %s provider through its injected factory',
  async (providerId) => {
    const provider = createFakeProvider(providerId);
    const createProvider = jest.fn().mockReturnValue(provider);
    const writeStdout = jest.fn();
    const writeStderr = jest.fn();

    const exitCode = await runEvaluationCli([`--provider=${providerId}`, '--max-cost-usd=1'], {
      createProvider,
      writeStdout,
      writeStderr,
    });

    expect(exitCode).toBe(0);
    expect(createProvider).toHaveBeenCalledWith(providerId);
    expect(writeStdout).toHaveBeenCalledTimes(1);
    expect(writeStderr).not.toHaveBeenCalled();
  },
);

test.each(['openai', 'anthropic'] as const)(
  'the explicit %s factory path ignores TAISA_COACHING_PROVIDER and reads selected configuration',
  (providerId) => {
    const selected = createProviderForId(
      providerId,
      {
        TAISA_COACHING_PROVIDER: providerId === 'openai' ? 'anthropic' : 'openai',
        [`TAISA_${providerId.toUpperCase()}_MODEL`]: 'synthetic-model',
        [`TAISA_${providerId.toUpperCase()}_INPUT_PRICE_USD_PER_MILLION_TOKENS`]: '1',
        [`TAISA_${providerId.toUpperCase()}_OUTPUT_PRICE_USD_PER_MILLION_TOKENS`]: '2',
        [`TAISA_${providerId.toUpperCase()}_MAX_OUTPUT_TOKENS`]: '1024',
        [`TAISA_${providerId.toUpperCase()}_STRUCTURED_OUTPUT_INPUT_TOKEN_OVERHEAD`]: '512',
      },
      {
        openai: createFakeProvider('openai'),
        anthropic: createFakeProvider('anthropic'),
      },
    );

    expect(selected.id).toBe(providerId);
  },
);

test('the CLI prints only a fixed error code when factory creation throws sensitive text', async () => {
  const writeStdout = jest.fn();
  const writeStderr = jest.fn();

  const exitCode = await runEvaluationCli(['--provider=openai', '--max-cost-usd=1'], {
    createProvider: () => {
      throw new Error('secret-key=do-not-print');
    },
    writeStdout,
    writeStderr,
  });

  expect(exitCode).toBe(1);
  expect(writeStdout).not.toHaveBeenCalled();
  expect(writeStderr).toHaveBeenCalledWith('EVAL_COACHING_FAILED\n');
  expect(writeStderr.mock.calls.flat().join('')).not.toContain('secret-key=do-not-print');
});

test('the command-line parser rejects an omitted or unsupported provider choice', () => {
  expect(parseProviderArgument(['--provider=openai'])).toBe('openai');
  expect(() => parseProviderArgument([])).toThrow('explicit --provider=openai or --provider=anthropic');
  expect(() => parseProviderArgument(['--provider=other'])).toThrow(
    'explicit --provider=openai or --provider=anthropic',
  );
});

test('the command-line parser requires a finite positive evaluation budget', () => {
  expect(parseEvaluationBudgetArgument(['--max-cost-usd=0.25'])).toBe(0.25);
  expect(() => parseEvaluationBudgetArgument(['--provider=openai'])).toThrow('explicit --max-cost-usd');
  expect(() => parseEvaluationBudgetArgument(['--max-cost-usd=0'])).toThrow('positive finite number');
});
