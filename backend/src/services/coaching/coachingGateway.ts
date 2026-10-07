import type { CoachingRequest, CoachingResponse } from '@taisa/shared';
import { ZodError } from 'zod';
import { buildSeniorSelfPrompt } from '../../prompts/system/seniorSelf';
import { CoachingResponsePayloadSchema } from '../../schemas/coaching';
import {
  getConfiguredFallbackProvider,
  type FallbackCoachingProvider,
  type ProviderAttemptObserver,
  type ProviderAttemptOutcome,
} from './fallbackProvider';
import type { AttemptEstimate } from '../usage/costLedger';
import {
  estimateMaximumCoachingUsage,
  getConfiguredProviderPairSettings,
  type CoachingEnvironment,
} from './provider';

export class RecoverableCoachingError extends Error {
  readonly code = 'INVALID_COACHING_OUTPUT';
  readonly recoverable = true;

  constructor() {
    super('The coaching provider returned an invalid structured response');
    this.name = 'RecoverableCoachingError';
  }
}

export function estimateConfiguredCoachingAttempts(
  request: CoachingRequest,
  environment: CoachingEnvironment = process.env,
): readonly AttemptEstimate[] {
  const prompt = buildSeniorSelfPrompt(request);
  const { primaryId, fallbackId, configs } = getConfiguredProviderPairSettings(environment);
  return [
    {
      attemptId: 'primary',
      receipt: estimateMaximumCoachingUsage(primaryId, prompt, configs[primaryId]),
    },
    {
      attemptId: 'fallback',
      receipt: estimateMaximumCoachingUsage(fallbackId, prompt, configs[fallbackId]),
    },
  ];
}

export interface CoachingExecution {
  response: CoachingResponse;
  attempts: readonly ProviderAttemptOutcome[];
}

export type StreamingCoachingProviderItem =
  | { kind: 'delta'; delta: string }
  | { kind: 'completed'; result: { payload: unknown; usage: CoachingResponse['usage'] }; attempts: readonly ProviderAttemptOutcome[] };

export interface StreamingFallbackCoachingProvider {
  stream(
    input: { systemPrompt: string; userPrompt: string },
    observer: ProviderAttemptObserver,
  ): AsyncIterable<StreamingCoachingProviderItem>;
}

export type StreamingCoachingItem =
  | { kind: 'delta'; delta: string }
  | { kind: 'completed'; response: CoachingResponse; attempts: readonly ProviderAttemptOutcome[] };

export async function* requestStreamingCoaching(
  request: CoachingRequest,
  provider: StreamingFallbackCoachingProvider,
  observer: ProviderAttemptObserver = NOOP_ATTEMPT_OBSERVER,
): AsyncIterable<StreamingCoachingItem> {
  const prompt = buildSeniorSelfPrompt(request);
  for await (const item of provider.stream(prompt, observer)) {
    if (item.kind === 'delta') {
      yield item;
      continue;
    }
    const payload = CoachingResponsePayloadSchema.parse(item.result.payload);
    yield {
      kind: 'completed',
      response: { requestId: request.requestId, ...payload, usage: item.result.usage },
      attempts: item.attempts,
    };
  }
}

const NOOP_ATTEMPT_OBSERVER: ProviderAttemptObserver = {
  beginAttempt: () => undefined,
  settleAttempt: () => undefined,
};

export async function requestCoaching(
  request: CoachingRequest,
  provider: FallbackCoachingProvider = getConfiguredFallbackProvider(),
  observer: ProviderAttemptObserver = NOOP_ATTEMPT_OBSERVER,
): Promise<CoachingExecution> {
  const prompt = buildSeniorSelfPrompt(request);

  try {
    const execution = await provider.respond(prompt, observer);
    const payload = CoachingResponsePayloadSchema.parse(execution.result.payload);
    return {
      response: {
        requestId: request.requestId,
        ...payload,
        usage: execution.result.usage,
      },
      attempts: execution.attempts,
    };
  } catch (error) {
    if (error instanceof ZodError) throw new RecoverableCoachingError();
    throw error;
  }
}
