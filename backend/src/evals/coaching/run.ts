import { CoachingResponsePayloadSchema } from '../../schemas/coaching';
import { buildSeniorSelfPrompt } from '../../prompts/system/seniorSelf';
import { createProviderForId } from '../../services/coaching/provider';
import type { CoachingProvider, CoachingProviderId } from '../../services/coaching/provider';
import { scoreCoachingResponse, type CoachingRubricScores } from './rubric';
import { COACHING_EVALUATION_PACK_VERSION, coachingEvaluationScenarios } from './scenarios';
import { writeFileSync } from 'fs';
import path from 'path';
import { costLedger, type UsageLedger } from '../../services/usage/costLedger';

export interface CoachingEvaluationResult {
  scenarioId: string;
  rubric: CoachingRubricScores;
  latencyMs: number;
  inputTokens: number;
  outputTokens: number;
  estimatedCostUsd: number;
  schemaStatus: 'valid' | 'invalid';
  errorCode: 'INVALID_SCHEMA' | 'PROVIDER_ERROR' | null;
  manualReviewResponse?: string;
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
  maxCostUsd?: number;
  usageLedger?: UsageLedger;
}

const zeroRubric: CoachingRubricScores = {
  coachingUsefulness: 0,
  continuityConflictDetection: 0,
  actionQuality: 0,
  memoryCorrectness: 0,
  schemaCompliance: 0,
  responseMode: 0,
  relevance: 0,
  contextSufficiency: 0,
  responseInvariants: 0,
  stance: 0,
  proposalInvariants: 0,
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
    const reservation = options.usageLedger && options.maxCostUsd
      ? options.usageLedger.reserveUsage(
        { provider: options.providerId, model: 'coaching-evaluation', estimatedCostUsd: options.maxCostUsd / coachingEvaluationScenarios.length },
        { perRequestUsd: options.maxCostUsd / coachingEvaluationScenarios.length, dailyUsd: options.maxCostUsd, monthlyUsd: options.maxCostUsd },
      ) : null;
    try {
      reservation?.beginProviderInvocation();
      const providerResult = await options.provider.respond(buildSeniorSelfPrompt(scenario.request));
      reservation?.commit(providerResult.usage);
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
          manualReviewResponse: '',
        });
        continue;
      }

      results.push({
        scenarioId: scenario.id,
        rubric: scoreCoachingResponse(
          scenario,
          parsed.data,
        ),
        latencyMs,
        inputTokens: providerResult.usage.inputTokens ?? 0,
        outputTokens: providerResult.usage.outputTokens ?? 0,
        estimatedCostUsd: providerResult.usage.estimatedCostUsd,
        schemaStatus: 'valid',
        errorCode: null,
        manualReviewResponse: parsed.data.reply,
      });
    } catch {
      reservation?.release();
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
  return JSON.stringify({
    packVersion: summary.packVersion,
    provider: summary.provider,
    results: summary.results.map(({ manualReviewResponse: _response, ...result }) => result),
  });
}

export const COACHING_EVALUATION_THRESHOLDS = Object.freeze({
  schemaComplianceMinimum: 1,
  memoryCorrectnessMinimum: 0.9,
  actionQualityMinimum: 0.8,
  continuityConflictDetectionMinimum: 0.7,
  guardrailResponseModeMinimum: 1,
  guardrailRelevanceMinimum: 1,
  guardrailContextSufficiencyMinimum: 1,
  guardrailResponseInvariantsMinimum: 1,
  guardrailStanceMinimum: 1,
  guardrailProposalInvariantsMinimum: 1,
  manualUsefulnessMinimum: 0.8,
});

export function buildManualReviewArtifact(summary: CoachingEvaluationSummary) {
  const average = (field: keyof CoachingRubricScores, scenarioIds?: Set<string>) => {
    const applicable = scenarioIds === undefined
      ? summary.results
      : summary.results.filter((result) => scenarioIds.has(result.scenarioId));
    return applicable.reduce((total, result) => total + result.rubric[field], 0) /
      Math.max(1, applicable.length);
  };
  const continuityScenarioIds = new Set(coachingEvaluationScenarios
    .filter((scenario) => scenario.expected.continuityRequired).map((scenario) => scenario.id));
  const guardrailScenarioIds = new Set(coachingEvaluationScenarios
    .filter((scenario) => scenario.id.startsWith('guardrail-')).map((scenario) => scenario.id));
  const automatedPassed = average('schemaCompliance') >= COACHING_EVALUATION_THRESHOLDS.schemaComplianceMinimum &&
    average('memoryCorrectness') >= COACHING_EVALUATION_THRESHOLDS.memoryCorrectnessMinimum &&
    average('actionQuality') >= COACHING_EVALUATION_THRESHOLDS.actionQualityMinimum &&
    average('continuityConflictDetection', continuityScenarioIds) >= COACHING_EVALUATION_THRESHOLDS.continuityConflictDetectionMinimum &&
    average('responseMode', guardrailScenarioIds) >= COACHING_EVALUATION_THRESHOLDS.guardrailResponseModeMinimum &&
    average('relevance', guardrailScenarioIds) >= COACHING_EVALUATION_THRESHOLDS.guardrailRelevanceMinimum &&
    average('contextSufficiency', guardrailScenarioIds) >= COACHING_EVALUATION_THRESHOLDS.guardrailContextSufficiencyMinimum &&
    average('responseInvariants', guardrailScenarioIds) >= COACHING_EVALUATION_THRESHOLDS.guardrailResponseInvariantsMinimum &&
    average('stance', guardrailScenarioIds) >= COACHING_EVALUATION_THRESHOLDS.guardrailStanceMinimum &&
    average('proposalInvariants', guardrailScenarioIds) >= COACHING_EVALUATION_THRESHOLDS.guardrailProposalInvariantsMinimum;
  return {
    packVersion: summary.packVersion, provider: summary.provider, syntheticOnly: true,
    thresholds: COACHING_EVALUATION_THRESHOLDS, automatedPassed,
    manualReviewStatus: 'required' as const,
    reviews: summary.results.map((result) => {
      const scenario = coachingEvaluationScenarios.find((candidate) => candidate.id === result.scenarioId)!;
      return {
        scenarioId: result.scenarioId,
        coverage: scenario.coverage,
        syntheticInput: scenario.request.input,
        response: result.manualReviewResponse ?? '',
        manualUsefulness: null,
        inventedReferent: null,
        inventedEmotion: null,
        inventedParticipantOrPurpose: null,
        clarificationQuestionNeutral: null,
        proposalsGroundedInSupportedObservation: null,
      };
    }),
  };
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
  usageLedger?: UsageLedger;
  writeArtifact?: (path: string, output: string) => void;
}

const defaultCliDependencies: EvaluationCliDependencies = {
  createProvider: createProviderForId,
  writeStdout: (output) => process.stdout.write(output),
  writeStderr: (output) => process.stderr.write(output),
  usageLedger: costLedger,
  writeArtifact: (target, output) => writeFileSync(target, output, { flag: 'wx' }),
};

export async function runEvaluationCli(
  argv: string[],
  dependencies: EvaluationCliDependencies = defaultCliDependencies,
): Promise<0 | 1> {
  try {
    const providerId = parseProviderArgument(argv);
    const maxCostUsd = parseEvaluationBudgetArgument(argv);
    const provider = dependencies.createProvider(providerId);
    const summary = await runCoachingEvaluation({ providerId, provider, maxCostUsd, usageLedger: dependencies.usageLedger });
    const outputArg = argv.find((argument) => argument.startsWith('--review-output='));
    const outputPath = outputArg?.slice('--review-output='.length) || path.resolve(process.cwd(), 'coaching-eval-review.json');
    dependencies.writeArtifact?.(outputPath, `${JSON.stringify(buildManualReviewArtifact(summary), null, 2)}\n`);
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
