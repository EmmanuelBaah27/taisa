import { ZodError } from 'zod';
import type {
  AttemptEstimate,
  AttemptSettlement,
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
  type ProviderRegistry,
} from './provider';

export interface ProviderAttemptOutcome {
  attemptId: 'primary' | 'fallback';
  providerId: CoachingProviderId;
  result?: ProviderCoachingResult;
  failureClass?: OperationalFailureClass;
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

export interface ContentFreeFailedAttempt {
  attemptId: AttemptEstimate['attemptId'];
  failureClass?: OperationalFailureClass;
}

export class ContentFreeFallbackError extends Error {
  constructor(readonly attempts: readonly ContentFreeFailedAttempt[]) {
    super('Both coaching provider attempts failed');
    this.name = 'ContentFreeFallbackError';
  }
}

type EstimatingCoachingProvider = CoachingProvider & {
  estimateMaximumUsage(input: ProviderCoachingInput): ProviderCoachingResult['usage'];
};

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
  observer.settleAttempt({ attemptId, receipt: result.usage });
  return { succeeded: true, result };
}

export function getConfiguredFallbackProvider(
  environment: CoachingEnvironment = process.env,
  providers?: ProviderRegistry,
): FallbackCoachingProvider {
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
      if (fallbackAttempt.error instanceof ZodError) throw fallbackAttempt.error;
      const fallbackFailureClass = classifyOperationalProviderFailure(fallbackAttempt.error);
      throw new ContentFreeFallbackError([
        { attemptId: 'primary', failureClass: primaryFailureClass },
        {
          attemptId: 'fallback',
          ...(fallbackFailureClass ? { failureClass: fallbackFailureClass } : {}),
        },
      ]);
    },
  };
}
