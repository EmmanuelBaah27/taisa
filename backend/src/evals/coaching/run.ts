import { CoachingResponsePayloadSchema } from '../../schemas/coaching';
import type { MemoryDelta } from '@taisa/shared';
import { buildSeniorSelfPrompt } from '../../prompts/system/seniorSelf';
import { createProviderForId } from '../../services/coaching/provider';
import type { CoachingProvider, CoachingProviderId } from '../../services/coaching/provider';
import { scoreCoachingResponse, type CoachingRubricScores } from './rubric';
import { COACHING_EVALUATION_PACK_VERSION, coachingEvaluationScenarios } from './scenarios';

export interface CoachingEvaluationResult {
  scenarioId: string;
  rubric: CoachingRubricScores;
  latencyMs: number;
  inputTokens: number;
  outputTokens: number;
  estimatedCostUsd: number;
  schemaStatus: 'valid' | 'invalid';
  errorCode: 'INVALID_SCHEMA' | 'PROVIDER_ERROR' | null;
}

export interface CoachingEvaluationSummary {
  packVersion: string;
  provider: 'openai' | 'anthropic';
  results: CoachingEvaluationResult[];
}

export interface RunCoachingEvaluationOptions {
  providerId: CoachingProviderId;
  provider: CoachingProvider;
  now?: () => number;
}

const zeroRubric: CoachingRubricScores = {
  coachingUsefulness: 0,
  continuityConflictDetection: 0,
  actionQuality: 0,
  memoryCorrectness: 0,
  schemaCompliance: 0,
};

export async function runCoachingEvaluation(
  options: RunCoachingEvaluationOptions,
): Promise<CoachingEvaluationSummary> {
  if (options.provider.id !== options.providerId) {
    throw new Error(`Selected provider ${options.providerId} does not match selected provider adapter`);
  }

  const now = options.now ?? Date.now;
  const results: CoachingEvaluationResult[] = [];

  for (const scenario of coachingEvaluationScenarios) {
    const startedAt = now();
    try {
      const providerResult = await options.provider.respond(buildSeniorSelfPrompt(scenario.request));
      const latencyMs = Math.max(0, now() - startedAt);
      const parsed = CoachingResponsePayloadSchema.safeParse(providerResult.payload);

      if (!parsed.success) {
        results.push({
          scenarioId: scenario.id,
          rubric: zeroRubric,
          latencyMs,
          inputTokens: providerResult.usage.inputTokens ?? 0,
          outputTokens: providerResult.usage.outputTokens ?? 0,
          estimatedCostUsd: providerResult.usage.estimatedCostUsd,
          schemaStatus: 'invalid',
          errorCode: 'INVALID_SCHEMA',
        });
        continue;
      }

      results.push({
        scenarioId: scenario.id,
        rubric: scoreCoachingResponse(
          scenario,
          parsed.data as { reply: string; stance: 'mirror' | 'nudge' | 'challenge' | 'direct'; proposals: MemoryDelta[] },
        ),
        latencyMs,
        inputTokens: providerResult.usage.inputTokens ?? 0,
        outputTokens: providerResult.usage.outputTokens ?? 0,
        estimatedCostUsd: providerResult.usage.estimatedCostUsd,
        schemaStatus: 'valid',
        errorCode: null,
      });
    } catch {
      results.push({
        scenarioId: scenario.id,
        rubric: zeroRubric,
        latencyMs: Math.max(0, now() - startedAt),
        inputTokens: 0,
        outputTokens: 0,
        estimatedCostUsd: 0,
        schemaStatus: 'invalid',
        errorCode: 'PROVIDER_ERROR',
      });
    }
  }

  return { packVersion: COACHING_EVALUATION_PACK_VERSION, provider: options.providerId, results };
}

export function serializeEvaluationSummary(summary: CoachingEvaluationSummary): string {
  return JSON.stringify(summary);
}

export function parseProviderArgument(argv: string[]): 'openai' | 'anthropic' {
  const providerArgument = argv.find((argument) => argument.startsWith('--provider='));
  const providerId = providerArgument?.slice('--provider='.length);
  if (providerId !== 'openai' && providerId !== 'anthropic') {
    throw new Error('An explicit --provider=openai or --provider=anthropic argument is required');
  }
  return providerId;
}

export function parseEvaluationBudgetArgument(argv: string[]): number {
  const budgetArgument = argv.find((argument) => argument.startsWith('--max-cost-usd='));
  if (!budgetArgument) {
    throw new Error('An explicit --max-cost-usd=<positive number> argument is required');
  }
  const budget = Number(budgetArgument.slice('--max-cost-usd='.length));
  if (!Number.isFinite(budget) || budget <= 0) {
    throw new Error('--max-cost-usd must be a positive finite number');
  }
  return budget;
}

export interface EvaluationCliDependencies {
  createProvider: (providerId: CoachingProviderId) => CoachingProvider;
  writeStdout: (output: string) => void;
  writeStderr: (output: string) => void;
}

const defaultCliDependencies: EvaluationCliDependencies = {
  createProvider: createProviderForId,
  writeStdout: (output) => process.stdout.write(output),
  writeStderr: (output) => process.stderr.write(output),
};

export async function runEvaluationCli(
  argv: string[],
  dependencies: EvaluationCliDependencies = defaultCliDependencies,
): Promise<0 | 1> {
  try {
    const providerId = parseProviderArgument(argv);
    parseEvaluationBudgetArgument(argv);
    const provider = dependencies.createProvider(providerId);
    const summary = await runCoachingEvaluation({ providerId, provider });
    dependencies.writeStdout(`${serializeEvaluationSummary(summary)}\n`);
    return 0;
  } catch {
    dependencies.writeStderr('EVAL_COACHING_FAILED\n');
    return 1;
  }
}

async function main(): Promise<void> {
  process.exitCode = await runEvaluationCli(process.argv.slice(2));
}

if (require.main === module) {
  main().catch(() => {
    process.stderr.write('EVAL_COACHING_FAILED\n');
    process.exitCode = 1;
  });
}
