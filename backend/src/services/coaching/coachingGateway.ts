import type { CoachingRequest, CoachingResponse } from '@taisa/shared';
import { ZodError } from 'zod';
import { buildSeniorSelfPrompt } from '../../prompts/system/seniorSelf';
import { CoachingResponsePayloadSchema } from '../../schemas/coaching';
import { getConfiguredProvider } from './provider';
import type { CoachingProvider } from './provider';

export class RecoverableCoachingError extends Error {
  readonly code = 'INVALID_COACHING_OUTPUT';
  readonly recoverable = true;

  constructor() {
    super('The coaching provider returned an invalid structured response');
    this.name = 'RecoverableCoachingError';
  }
}

export async function requestCoaching(
  request: CoachingRequest,
  provider: CoachingProvider = getConfiguredProvider(),
): Promise<CoachingResponse> {
  const prompt = buildSeniorSelfPrompt(request);

  try {
    const result = await provider.respond(prompt);
    const payload = CoachingResponsePayloadSchema.parse(result.payload) as Pick<
      CoachingResponse,
      'reply' | 'stance' | 'proposals'
    >;
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
