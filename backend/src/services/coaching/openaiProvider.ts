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
import { normalizeOpenAISdkFailure } from './providerSdkFailure';

type OpenAIClient = Pick<OpenAI, 'beta'>;

function pruneUnreachableDefinitions<T extends Record<string, any>>(schema: T): T {
  const definitions = schema.definitions as Record<string, unknown> | undefined;
  if (!definitions) return schema;

  const reachable = new Set<string>();
  const visit = (value: unknown) => {
    if (Array.isArray(value)) {
      value.forEach(visit);
      return;
    }
    if (!value || typeof value !== 'object') return;
    const record = value as Record<string, unknown>;
    const reference = record.$ref;
    if (typeof reference === 'string' && reference.startsWith('#/definitions/')) {
      const name = reference.slice('#/definitions/'.length);
      if (!reachable.has(name) && definitions[name]) {
        reachable.add(name);
        visit(definitions[name]);
      }
    }
    Object.entries(record).forEach(([key, child]) => {
      if (key !== 'definitions') visit(child);
    });
  };

  visit(schema);
  return {
    ...schema,
    definitions: Object.fromEntries(
      Object.entries(definitions).filter(([name]) => reachable.has(name)),
    ),
  };
}

function stripUnsupportedStringLengthKeywords<T>(value: T): T {
  if (Array.isArray(value)) {
    return value.map(stripUnsupportedStringLengthKeywords) as T;
  }
  if (!value || typeof value !== 'object') return value;
  const entries = Object.entries(value as Record<string, unknown>)
    .filter(([key]) => key !== 'minLength' && key !== 'maxLength')
    .map(([key, child]) => [key, stripUnsupportedStringLengthKeywords(child)]);
  const normalized = Object.fromEntries(entries) as Record<string, unknown>;
  if (
    normalized.type === 'array'
    && Array.isArray(normalized.items)
    && normalized.items.length === 0
    && normalized.maxItems === 0
  ) {
    normalized.items = { type: 'string' };
  }
  return normalized as T;
}

function openAIResponseFormat() {
  const format = zodResponseFormat(
    OpenAICoachingResponseEnvelopeSchema,
    'coaching_response',
  );
  return {
    ...format,
    json_schema: {
      ...format.json_schema,
      schema: stripUnsupportedStringLengthKeywords(
        pruneUnreachableDefinitions(format.json_schema.schema as Record<string, any>),
      ),
    },
  };
}

export function createOpenAIProvider(
  config: CoachingProviderConfig,
  client: OpenAIClient = new OpenAI({ apiKey: process.env.OPENAI_API_KEY }),
): CoachingProvider {
  return {
    id: 'openai',
    estimateMaximumUsage: (input) => estimateMaximumCoachingUsage('openai', input, config),
    async respond(input: ProviderCoachingInput) {
      let completion;
      try {
        completion = await client.beta.chat.completions.parse(
          {
            model: config.model,
            messages: [
              { role: 'system', content: input.systemPrompt },
              { role: 'user', content: input.userPrompt },
            ],
            response_format: openAIResponseFormat(),
            max_completion_tokens: config.maxOutputTokens,
          },
          { maxRetries: 0 },
        );
      } catch (error) {
        throw normalizeOpenAISdkFailure(error);
      }

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
