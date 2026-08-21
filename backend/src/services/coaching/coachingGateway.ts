import type { CoachingRequest, CoachingResponse, UsageReceipt } from '@taisa/shared';
import { ZodError } from 'zod';
import { buildSeniorSelfPrompt } from '../../prompts/system/seniorSelf';
import { CoachingResponsePayloadSchema } from '../../schemas/coaching';
import {
  estimateMaximumCoachingUsage,
  getConfiguredProvider,
  getConfiguredProviderSettings,
  type CoachingEnvironment,
} from './provider';
import type { CoachingProvider } from './provider';

export class RecoverableCoachingError extends Error {
  readonly code = 'INVALID_COACHING_OUTPUT';
  readonly recoverable = true;

  constructor() {
    super('The coaching provider returned an invalid structured response');
    this.name = 'RecoverableCoachingError';
  }
}

export function estimateConfiguredCoachingUsage(
  request: CoachingRequest,
  environment: CoachingEnvironment = process.env,
): UsageReceipt {
  const { providerId, config } = getConfiguredProviderSettings(environment);
  const prompt = buildSeniorSelfPrompt(request);
  return estimateMaximumCoachingUsage(providerId, prompt, config);
}

export async function requestCoaching(
  request: CoachingRequest,
  provider: CoachingProvider = getConfiguredProvider(),
): Promise<CoachingResponse> {
  const prompt = buildSeniorSelfPrompt(request);

  try {
    const result = await provider.respond(prompt);
    const payload = CoachingResponsePayloadSchema.parse(result.payload);
    return {
      requestId: request.requestId,
      ...payload,
      usage: result.usage,
    };
  } catch (error) {
    if (error instanceof ZodError) throw new RecoverableCoachingError();
    throw error;
  }
}
