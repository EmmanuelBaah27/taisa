import { ZodError } from 'zod';
import {
  UsageExceedsReservationError,
  type AttemptEstimate,
  type AttemptSettlement,
} from '../usage/costLedger';
import {
  classifyOperationalProviderFailure,
  type OperationalFailureClass,
} from './providerFailure';
import {
  createProviderForId,
  getConfiguredProviderPairSettings,
  type CoachingEnvironment,
  type CoachingProvider,
  type CoachingProviderId,
  type ProviderCoachingInput,
  type ProviderCoachingResult,
  type ProviderCoachingStreamItem,
  type ProviderRegistry,
} from './provider';

export interface ProviderAttemptOutcome {
  attemptId: 'primary' | 'fallback';
  providerId: CoachingProviderId;
  result?: ProviderCoachingResult;
  failureClass?: OperationalFailureClass | 'invalid_output';
}

export interface FallbackCoachingResult {
  result: ProviderCoachingResult;
  attempts: readonly ProviderAttemptOutcome[];
}

export interface ProviderAttemptObserver {
  beginAttempt(attemptId: AttemptEstimate['attemptId']): void;
  settleAttempt(settlement: AttemptSettlement): void;
}

export interface FallbackCoachingProvider {
  readonly primaryId: CoachingProviderId;
  readonly fallbackId: CoachingProviderId;
  estimateMaximumAttempts(input: ProviderCoachingInput): readonly AttemptEstimate[];
  respond(
    input: ProviderCoachingInput,
    observer: ProviderAttemptObserver,
  ): Promise<FallbackCoachingResult>;
}

export interface StreamingFallbackCoachingProvider extends FallbackCoachingProvider {
  stream(input: ProviderCoachingInput, observer: ProviderAttemptObserver): AsyncIterable<
    | { kind: 'delta'; delta: string }
    | { kind: 'completed'; result: ProviderCoachingResult; attempts: readonly ProviderAttemptOutcome[] }
  >;
}

export interface ContentFreeFailedAttempt {
  attemptId: AttemptEstimate['attemptId'];
  failureClass?: OperationalFailureClass | 'invalid_output';
}

function classifyContentFreeProviderFailure(
  error: unknown,
): OperationalFailureClass | 'invalid_output' | null {
  if (error instanceof ZodError) return 'invalid_output';
  return classifyOperationalProviderFailure(error);
}

export class ContentFreeFallbackError extends Error {
  constructor(readonly attempts: readonly ContentFreeFailedAttempt[]) {
    super('Both coaching provider attempts failed');
    this.name = 'ContentFreeFallbackError';
  }
}

export class ContentFreeFallbackInvalidOutputError extends ContentFreeFallbackError {
  readonly code = 'INVALID_COACHING_OUTPUT';
  readonly recoverable = true;

  constructor(primaryFailureClass: OperationalFailureClass) {
    super([
      { attemptId: 'primary', failureClass: primaryFailureClass },
      { attemptId: 'fallback', failureClass: 'invalid_output' },
    ]);
    this.name = 'ContentFreeFallbackInvalidOutputError';
  }
}

type EstimatingCoachingProvider = CoachingProvider & {
  estimateMaximumUsage(input: ProviderCoachingInput): ProviderCoachingResult['usage'];
};

type StreamingCoachingProvider = EstimatingCoachingProvider & {
  streamRespond(input: ProviderCoachingInput): AsyncIterable<ProviderCoachingStreamItem>;
};

function requireStreamingProvider(providerId: CoachingProviderId, provider: EstimatingCoachingProvider): StreamingCoachingProvider {
  if (!provider.streamRespond) throw new Error(`${providerId} provider must support streaming`);
  return provider as StreamingCoachingProvider;
}

function requireEstimatingProvider(
  providerId: CoachingProviderId,
  provider: CoachingProvider,
): EstimatingCoachingProvider {
  if (!provider.estimateMaximumUsage) {
    throw new Error(`${providerId} provider must estimate maximum usage`);
  }
  return provider as EstimatingCoachingProvider;
}

function requireMaximumEstimate(
  attemptId: AttemptEstimate['attemptId'],
  providerId: CoachingProviderId,
  provider: EstimatingCoachingProvider,
  input: ProviderCoachingInput,
): AttemptEstimate {
  const receipt = provider.estimateMaximumUsage(input);
  if (receipt.provider !== providerId) {
    throw new Error(`${providerId} provider maximum usage identity does not match`);
  }
  return { attemptId, receipt };
}

async function invokeProviderAttempt(
  attemptId: AttemptEstimate['attemptId'],
  provider: CoachingProvider,
  input: ProviderCoachingInput,
  observer: ProviderAttemptObserver,
): Promise<
  | { succeeded: true; result: ProviderCoachingResult }
  | { succeeded: false; error: unknown }
> {
  observer.beginAttempt(attemptId);
  let result: ProviderCoachingResult;
  try {
    result = await provider.respond(input);
  } catch (error) {
    observer.settleAttempt({ attemptId });
    return { succeeded: false, error };
  }
  try {
    observer.settleAttempt({ attemptId, receipt: result.usage });
  } catch (error) {
    if (!(error instanceof UsageExceedsReservationError)) throw error;
    // The actual usage is already durable. Losing the valid response would make a retry charge
    // again, so retain the existing content-free warning and return the paid answer.
    console.warn('[Taisa diagnostic] COACHING_USAGE_EXCEEDED_RESERVATION');
  }
  return { succeeded: true, result };
}

export function getConfiguredFallbackProvider(
  environment: CoachingEnvironment = process.env,
  providers?: ProviderRegistry,
): StreamingFallbackCoachingProvider {
  const { primaryId, fallbackId } = getConfiguredProviderPairSettings(environment);
  const registry: ProviderRegistry = providers ?? {
    openai: createProviderForId('openai', environment),
    anthropic: createProviderForId('anthropic', environment),
  };
  const primary = requireEstimatingProvider(primaryId, registry[primaryId]);
  const fallback = requireEstimatingProvider(fallbackId, registry[fallbackId]);

  return {
    primaryId,
    fallbackId,
    estimateMaximumAttempts(input) {
      return [
        requireMaximumEstimate('primary', primaryId, primary, input),
        requireMaximumEstimate('fallback', fallbackId, fallback, input),
      ];
    },
    async respond(input, observer) {
      const attempts: ProviderAttemptOutcome[] = [];
      const primaryAttempt = await invokeProviderAttempt(
        'primary', primary, input, observer,
      );
      if ('result' in primaryAttempt) {
        attempts.push({
          attemptId: 'primary',
          providerId: primaryId,
          result: primaryAttempt.result,
        });
        return { result: primaryAttempt.result, attempts };
      }
      const primaryFailureClass = classifyOperationalProviderFailure(primaryAttempt.error);
      if (!primaryFailureClass) throw primaryAttempt.error;
      attempts.push({
        attemptId: 'primary',
        providerId: primaryId,
        failureClass: primaryFailureClass,
      });

      const fallbackAttempt = await invokeProviderAttempt(
        'fallback', fallback, input, observer,
      );
      if ('result' in fallbackAttempt) {
        attempts.push({
          attemptId: 'fallback',
          providerId: fallbackId,
          result: fallbackAttempt.result,
        });
        return { result: fallbackAttempt.result, attempts };
      }
      if (fallbackAttempt.error instanceof ZodError) {
        throw new ContentFreeFallbackInvalidOutputError(primaryFailureClass);
      }
      const fallbackFailureClass = classifyOperationalProviderFailure(fallbackAttempt.error);
      throw new ContentFreeFallbackError([
        { attemptId: 'primary', failureClass: primaryFailureClass },
        {
          attemptId: 'fallback',
          ...(fallbackFailureClass ? { failureClass: fallbackFailureClass } : {}),
        },
      ]);
    },
    async *stream(input, observer) {
      const candidates = [
        { attemptId: 'primary' as const, providerId: primaryId, provider: requireStreamingProvider(primaryId, primary) },
        { attemptId: 'fallback' as const, providerId: fallbackId, provider: requireStreamingProvider(fallbackId, fallback) },
      ];
      const attempts: ProviderAttemptOutcome[] = [];
      for (const candidate of candidates) {
        observer.beginAttempt(candidate.attemptId);
        const bufferedDeltas: string[] = [];
        let attemptSettled = false;
        try {
          for await (const item of candidate.provider.streamRespond(input)) {
            if (item.kind === 'delta') {
              bufferedDeltas.push(item.delta);
              continue;
            }
            try {
              observer.settleAttempt({ attemptId: candidate.attemptId, receipt: item.result.usage });
              attemptSettled = true;
            } catch (error) {
              if (!(error instanceof UsageExceedsReservationError)) throw error;
              // Settlement records the actual usage before reporting an overrun. Keep the paid
              // result and do not settle the same attempt a second time.
              attemptSettled = true;
              console.warn('[Taisa diagnostic] COACHING_USAGE_EXCEEDED_RESERVATION');
            }
            attempts.push({ attemptId: candidate.attemptId, providerId: candidate.providerId, result: item.result });
            for (const delta of bufferedDeltas) {
              yield { kind: 'delta', delta } as const;
            }
            yield { kind: 'completed', result: item.result, attempts } as const;
            return;
          }
          throw new Error('Provider stream ended without a terminal result');
        } catch (error) {
          if (!attemptSettled) observer.settleAttempt({ attemptId: candidate.attemptId });
          const failureClass = classifyContentFreeProviderFailure(error);
          attempts.push({ attemptId: candidate.attemptId, providerId: candidate.providerId, ...(failureClass ? { failureClass } : {}) });
          if (candidate.attemptId === 'fallback' || !failureClass) {
            throw new ContentFreeFallbackError(attempts.map((attempt) => ({
              attemptId: attempt.attemptId, ...(attempt.failureClass ? { failureClass: attempt.failureClass } : {}),
            })));
          }
        }
      }
    },
  };
}
