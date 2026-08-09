import OpenAI from 'openai';
import { zodResponseFormat } from 'openai/helpers/zod';
import { CoachingResponsePayloadSchema } from '../../schemas/coaching';
import type {
  CoachingProvider,
  CoachingProviderConfig,
  ProviderCoachingInput,
} from './provider';
import { estimateCostUsd } from './provider';

type OpenAIClient = Pick<OpenAI, 'beta'>;

export function createOpenAIProvider(
  config: CoachingProviderConfig,
  client: OpenAIClient = new OpenAI({ apiKey: process.env.OPENAI_API_KEY }),
): CoachingProvider {
  return {
    id: 'openai',
    async respond(input: ProviderCoachingInput) {
      const completion = await client.beta.chat.completions.parse({
        model: config.model,
        messages: [
          { role: 'system', content: input.systemPrompt },
          { role: 'user', content: input.userPrompt },
        ],
        response_format: zodResponseFormat(CoachingResponsePayloadSchema, 'coaching_response'),
      });

      const payload = CoachingResponsePayloadSchema.parse(completion.choices[0]?.message.parsed);
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
