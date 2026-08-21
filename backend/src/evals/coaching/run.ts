import { CoachingResponsePayloadSchema, type CoachingResponsePayload } from '../../schemas/coaching';
import { buildSeniorSelfPrompt } from '../../prompts/system/seniorSelf';
import { createProviderForId } from '../../services/coaching/provider';
import type { CoachingProvider, CoachingProviderId } from '../../services/coaching/provider';
import { scoreCoachingResponse, type CoachingRubricScores } from './rubric';
import {
  COACHING_EVALUATION_PACK_VERSION,
  GUARDRAIL_SCENARIO_IDS,
  coachingEvaluationScenarios,
} from './scenarios';
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
  manualReviewResponse?: CoachingResponsePayload;
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
    const providerInput = buildSeniorSelfPrompt(scenario.request);
    let reservation: ReturnType<UsageLedger['reserveUsage']> | null = null;
    try {
      if (options.maxCostUsd !== undefined || options.usageLedger !== undefined) {
        if (options.maxCostUsd === undefined || options.usageLedger === undefined) {
          throw new Error('Evaluation cost enforcement requires a total budget and durable ledger');
        }
        if (options.provider.estimateMaximumUsage === undefined) {
          throw new Error('Selected provider cannot conservatively reserve maximum usage');
        }
        const maximumUsage = options.provider.estimateMaximumUsage(providerInput);
        reservation = options.usageLedger.reserveUsage(
          maximumUsage,
          {
            perRequestUsd: options.maxCostUsd,
            dailyUsd: options.maxCostUsd,
            monthlyUsd: options.maxCostUsd,
          },
        );
      }
      reservation?.beginProviderInvocation();
      const providerResult = await options.provider.respond(providerInput);
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
        manualReviewResponse: parsed.data,
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
  const guardrailScenarioIds = new Set<string>(GUARDRAIL_SCENARIO_IDS);
  const guardrailResultIds = summary.results
    .filter((result) => result.scenarioId.startsWith('guardrail-')).map((result) => result.scenarioId);
  const hasExactGuardrailResults = guardrailResultIds.length === guardrailScenarioIds.size &&
    new Set(guardrailResultIds).size === guardrailScenarioIds.size &&
    guardrailResultIds.every((scenarioId) => guardrailScenarioIds.has(scenarioId));
  const automatedPassed = hasExactGuardrailResults &&
    average('schemaCompliance') >= COACHING_EVALUATION_THRESHOLDS.schemaComplianceMinimum &&
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
    reviews: summary.results.flatMap((result) => {
      const scenario = coachingEvaluationScenarios.find((candidate) => candidate.id === result.scenarioId)!;
      if (!scenario?.synthetic) return [];
      const response = result.manualReviewResponse;
      return {
        scenarioId: result.scenarioId,
        coverage: scenario.coverage,
        syntheticInput: scenario.request.input,
        response: response?.reply ?? '',
        mode: response?.mode ?? null,
        relevance: response?.relevance ?? null,
        contextSufficiency: response?.contextSufficiency ?? null,
        stance: response?.stance ?? null,
        proposals: response?.proposals ?? [],
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

export interface CompletedManualReview {
  scenarioId: string;
  manualUsefulness: number;
  inventedReferent: boolean;
  inventedEmotion: boolean;
  inventedParticipantOrPurpose: boolean;
  clarificationQuestionNeutral: boolean | null;
  proposalsGroundedInSupportedObservation: boolean | null;
}

export interface ProviderEvaluationDecision {
  provider: CoachingProviderId;
  packVersion: string;
  automatedPassed: boolean;
  manualPassed: boolean;
  passed: boolean;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function assertExactKeys(value: Record<string, unknown>, expectedKeys: readonly string[], label: string): void {
  const actualKeys = Object.keys(value).sort();
  const sortedExpectedKeys = [...expectedKeys].sort();
  if (actualKeys.length !== sortedExpectedKeys.length ||
      actualKeys.some((key, index) => key !== sortedExpectedKeys[index])) {
    throw new Error(`${label} has invalid fields`);
  }
}

function assertThresholds(value: unknown): void {
  if (!isRecord(value)) throw new Error('Evaluation thresholds are invalid');
  assertExactKeys(value, Object.keys(COACHING_EVALUATION_THRESHOLDS), 'Evaluation thresholds');
  for (const [key, threshold] of Object.entries(COACHING_EVALUATION_THRESHOLDS)) {
    if (value[key] !== threshold) throw new Error('Evaluation thresholds do not match');
  }
}

function parseCompletedReview(value: unknown): CompletedManualReview {
  if (!isRecord(value)) throw new Error('Completed review is invalid');
  assertExactKeys(value, [
    'scenarioId', 'manualUsefulness', 'inventedReferent', 'inventedEmotion',
    'inventedParticipantOrPurpose', 'clarificationQuestionNeutral',
    'proposalsGroundedInSupportedObservation',
  ], 'Completed review');
  if (typeof value.scenarioId !== 'string' || value.scenarioId.length === 0 ||
      typeof value.manualUsefulness !== 'number' || !Number.isFinite(value.manualUsefulness) ||
      value.manualUsefulness < 0 || value.manualUsefulness > 1 ||
      typeof value.inventedReferent !== 'boolean' || typeof value.inventedEmotion !== 'boolean' ||
      typeof value.inventedParticipantOrPurpose !== 'boolean' ||
      (value.clarificationQuestionNeutral !== null && typeof value.clarificationQuestionNeutral !== 'boolean') ||
      (value.proposalsGroundedInSupportedObservation !== null &&
        typeof value.proposalsGroundedInSupportedObservation !== 'boolean')) {
    throw new Error('Completed review has invalid values');
  }
  return value as unknown as CompletedManualReview;
}

export function validateCompletedManualReview(
  artifact: ReturnType<typeof buildManualReviewArtifact>,
  reviews: readonly CompletedManualReview[],
): ProviderEvaluationDecision {
  if (!isRecord(artifact) ||
      (artifact.provider !== 'openai' && artifact.provider !== 'anthropic') ||
      typeof artifact.packVersion !== 'string' || artifact.packVersion.length === 0 ||
      artifact.syntheticOnly !== true || artifact.manualReviewStatus !== 'required' ||
      typeof artifact.automatedPassed !== 'boolean' || !Array.isArray(artifact.reviews)) {
    throw new Error('Manual review artifact is invalid');
  }
  assertThresholds(artifact.thresholds);
  if (!Array.isArray(reviews) || artifact.reviews.length === 0) {
    throw new Error('Completed reviews are invalid');
  }

  const artifactReviews = new Map<string, { mode: unknown; proposals: readonly unknown[] }>();
  for (const artifactReview of artifact.reviews) {
    if (!isRecord(artifactReview) || typeof artifactReview.scenarioId !== 'string' ||
        artifactReview.scenarioId.length === 0 || !Array.isArray(artifactReview.proposals) ||
        artifactReviews.has(artifactReview.scenarioId)) {
      throw new Error('Manual review artifact scenarios are invalid');
    }
    artifactReviews.set(artifactReview.scenarioId, {
      mode: artifactReview.mode,
      proposals: artifactReview.proposals,
    });
  }

  const completedByScenario = new Map<string, CompletedManualReview>();
  for (const rawReview of reviews as readonly unknown[]) {
    const review = parseCompletedReview(rawReview);
    const artifactReview = artifactReviews.get(review.scenarioId);
    if (!artifactReview || completedByScenario.has(review.scenarioId)) {
      throw new Error('Completed reviews must match artifact scenarios exactly once');
    }
    const clarificationApplicable = artifactReview.mode === 'clarify';
    const proposalsApplicable = artifactReview.proposals.length > 0;
    if ((clarificationApplicable && typeof review.clarificationQuestionNeutral !== 'boolean') ||
        (!clarificationApplicable && review.clarificationQuestionNeutral !== null) ||
        (proposalsApplicable && typeof review.proposalsGroundedInSupportedObservation !== 'boolean') ||
        (!proposalsApplicable && review.proposalsGroundedInSupportedObservation !== null)) {
      throw new Error('Completed review applicability does not match the artifact response');
    }
    completedByScenario.set(review.scenarioId, review);
  }
  if (completedByScenario.size !== artifactReviews.size) {
    throw new Error('Completed reviews must match artifact scenarios exactly once');
  }

  const completed = [...completedByScenario.values()];
  const averageUsefulness = completed.reduce((sum, review) => sum + review.manualUsefulness, 0) /
    completed.length;
  const manualPassed = averageUsefulness >= COACHING_EVALUATION_THRESHOLDS.manualUsefulnessMinimum &&
    completed.every((review) => !review.inventedReferent && !review.inventedEmotion &&
      !review.inventedParticipantOrPurpose && review.clarificationQuestionNeutral !== false &&
      review.proposalsGroundedInSupportedObservation !== false);
  const automatedPassed = artifact.automatedPassed;
  return {
    provider: artifact.provider,
    packVersion: artifact.packVersion,
    automatedPassed,
    manualPassed,
    passed: automatedPassed && manualPassed,
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
    const reviewArtifact = buildManualReviewArtifact(summary);
    dependencies.writeArtifact?.(outputPath, `${JSON.stringify(reviewArtifact, null, 2)}\n`);
    dependencies.writeStdout(`${serializeEvaluationSummary(summary)}\n`);
    if (!reviewArtifact.automatedPassed || reviewArtifact.manualReviewStatus === 'required') {
      dependencies.writeStderr('EVAL_COACHING_REVIEW_REQUIRED\n');
      return 1;
    }
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
