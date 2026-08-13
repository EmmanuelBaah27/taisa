import OpenAI from 'openai';
import { zodResponseFormat } from 'openai/helpers/zod';
import {
  CoachingResponsePayloadSchema,
  OpenAICoachingResponseEnvelopeSchema,
} from '../../schemas/coaching';
import type {
  CoachingProvider,
  CoachingProviderConfig,
  ProviderCoachingInput,
} from './provider';
import { estimateCostUsd, estimateMaximumCoachingUsage } from './provider';

type OpenAIClient = Pick<OpenAI, 'beta'>;

export function createOpenAIProvider(
  config: CoachingProviderConfig,
  client: OpenAIClient = new OpenAI({ apiKey: process.env.OPENAI_API_KEY }),
): CoachingProvider {
  return {
    id: 'openai',
    estimateMaximumUsage: (input) => estimateMaximumCoachingUsage('openai', input, config),
    async respond(input: ProviderCoachingInput) {
      const completion = await client.beta.chat.completions.parse(
        {
          model: config.model,
          messages: [
            { role: 'system', content: input.systemPrompt },
            { role: 'user', content: input.userPrompt },
          ],
          response_format: zodResponseFormat(
            OpenAICoachingResponseEnvelopeSchema,
            'coaching_response',
          ),
          max_completion_tokens: config.maxOutputTokens,
        },
        { maxRetries: 0 },
      );

      const payload = CoachingResponsePayloadSchema.parse(
        completion.choices[0]?.message.parsed?.response,
      );
      const inputTokens = completion.usage?.prompt_tokens ?? 0;
      const outputTokens = completion.usage?.completion_tokens ?? 0;

      return {
        payload,
        usage: {
          provider: 'openai',
          model: config.model,
          inputTokens,
          outputTokens,
          estimatedCostUsd: estimateCostUsd(inputTokens, outputTokens, config),
        },
      };
    },
  };
}
