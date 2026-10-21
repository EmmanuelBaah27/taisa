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
import {
  contentFreeProviderDiagnostic,
  normalizeOpenAISdkFailure,
} from './providerSdkFailure';
import { extractReplyPrefix } from './streamingCoaching';

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

function normalizeOpenAIResponseEnvelope(value: unknown): unknown {
  if (!value || typeof value !== 'object') return value;
  const envelope = value as Record<string, unknown>;
  const response = envelope.response;
  if (!response || typeof response !== 'object') return value;
  const responseRecord = response as Record<string, unknown>;
  const explanation = responseRecord.explanation;
  if (!explanation || typeof explanation !== 'object') return value;
  const explanationRecord = explanation as Record<string, unknown>;
  const approach = explanationRecord.approach;
  if (typeof approach !== 'string' || approach.trim().length > 0) return value;

  return {
    ...envelope,
    response: {
      ...responseRecord,
      explanation: {
        ...explanationRecord,
        approach: 'Used the available context to respond.',
      },
    },
  };
}

function parseCompletedOpenAIResponse(
  parsed: unknown,
  content: string,
): { response: ReturnType<typeof CoachingResponsePayloadSchema.parse> } {
  const envelope = OpenAICoachingResponseEnvelopeSchema.safeParse(parsed);
  if (envelope.success) return { response: envelope.data.response! };

  // The streaming SDK can return the schema nested in `message.parsed` or
  // unwrap the single `response` property. Keep both shapes behind the same
  // strict runtime contract rather than treating a valid payload as missing.
  const unwrapped = CoachingResponsePayloadSchema.safeParse(parsed);
  if (unwrapped.success) return { response: unwrapped.data };

  const reparsed = OpenAICoachingResponseEnvelopeSchema.parse(
    normalizeOpenAIResponseEnvelope(JSON.parse(content)),
  );
  return { response: reparsed.response! };
}

function openAIResponseFormat() {
  const format = zodResponseFormat(
    OpenAICoachingResponseEnvelopeSchema,
    'coaching_response',
  );
  return {
    ...format,
    $parseRaw: (content: string) => OpenAICoachingResponseEnvelopeSchema.parse(
      normalizeOpenAIResponseEnvelope(JSON.parse(content)),
    ),
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
        const normalized = normalizeOpenAISdkFailure(error);
        console.warn(
          '[Taisa diagnostic] OPENAI_COACHING_PROVIDER_FAILURE',
          JSON.stringify(contentFreeProviderDiagnostic(normalized)),
        );
        throw normalized;
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
    async *streamRespond(input: ProviderCoachingInput) {
      const responseFormat = openAIResponseFormat();
      const stream = client.beta.chat.completions.stream({
        model: config.model,
        messages: [{ role: 'system', content: input.systemPrompt }, { role: 'user', content: input.userPrompt }],
        response_format: responseFormat,
        max_completion_tokens: config.maxOutputTokens,
      }, { maxRetries: 0 });
      let raw = '';
      let emitted = '';
      try {
        for await (const chunk of stream) {
          raw += chunk.choices[0]?.delta?.content ?? '';
          const reply = extractReplyPrefix(raw);
          if (reply.length > emitted.length) {
            yield { kind: 'delta', delta: reply.slice(emitted.length) } as const;
            emitted = reply;
          }
        }
        const completion = await stream.finalChatCompletion();
        const message = completion.choices[0]?.message;
        const completedContent = message?.content;
        const contentToParse = typeof completedContent === 'string'
          && completedContent.trim().length > 0
          ? completedContent
          : raw;
        const parsedEnvelope = parseCompletedOpenAIResponse(
          message?.parsed,
          contentToParse,
        );
        const payload = parsedEnvelope.response;
        const inputTokens = completion.usage?.prompt_tokens ?? 0;
        const outputTokens = completion.usage?.completion_tokens ?? 0;
        yield { kind: 'completed', result: { payload, usage: {
          provider: 'openai', model: config.model, inputTokens, outputTokens,
          estimatedCostUsd: estimateCostUsd(inputTokens, outputTokens, config),
        } } } as const;
      } catch (error) {
        const normalized = normalizeOpenAISdkFailure(error);
        console.warn(
          '[Taisa diagnostic] OPENAI_COACHING_PROVIDER_FAILURE',
          JSON.stringify(contentFreeProviderDiagnostic(normalized)),
        );
        throw normalized;
      }
    },
  };
}
