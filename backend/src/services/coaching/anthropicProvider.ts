import type Anthropic from '@anthropic-ai/sdk';
import { COACHING_GATEWAY_LIMITS } from '@taisa/shared';
import anthropicClient from '../claude/client';
import { CoachingResponsePayloadSchema } from '../../schemas/coaching';
import type {
  CoachingProvider,
  CoachingProviderConfig,
  ProviderCoachingInput,
} from './provider';
import { estimateCostUsd, estimateMaximumCoachingUsage } from './provider';
import {
  contentFreeProviderDiagnostic,
  normalizeAnthropicSdkFailure,
} from './providerSdkFailure';
import { extractReplyPrefix } from './streamingCoaching';

type AnthropicClient = Pick<Anthropic, 'messages'>;

const TextJsonSchema = {
  type: 'string' as const,
  minLength: 1,
  maxLength: COACHING_GATEWAY_LIMITS.maxTextLength,
  pattern: '\\S',
};
const IdJsonSchema = {
  type: 'string' as const,
  minLength: 1,
  maxLength: COACHING_GATEWAY_LIMITS.maxIdLength,
  pattern: '\\S',
};
const TitleSuggestionJsonSchema = {
  type: 'string' as const, minLength: 1,
  maxLength: COACHING_GATEWAY_LIMITS.maxTitleSuggestionLength, pattern: '\\S',
};
const TimestampJsonSchema = {
  type: 'string' as const,
  maxLength: COACHING_GATEWAY_LIMITS.maxTimestampLength,
  format: 'date-time',
};
const IdListJsonSchema = {
  type: 'array' as const,
  items: IdJsonSchema,
  maxItems: COACHING_GATEWAY_LIMITS.maxIdListLength,
};
const nullable = (schema: object) => ({ anyOf: [schema, { type: 'null' as const }] });

const ExplanationJsonSchema = {
  type: 'object' as const,
  additionalProperties: false,
  required: ['mode', 'evidence', 'inference', 'confidence', 'approach'],
  properties: {
    mode: nullable({ type: 'string', enum: ['mirror', 'nudge', 'challenge', 'direct'] }),
    evidence: {
      type: 'array', maxItems: COACHING_GATEWAY_LIMITS.maxEvidenceItems,
      items: {
        type: 'object', additionalProperties: false,
        required: ['sourceId', 'sourceType', 'excerpt'],
        properties: {
          sourceId: IdJsonSchema,
          sourceType: { type: 'string', enum: ['message', 'goal', 'action', 'evidence', 'memory', 'insight'] },
          excerpt: nullable(TextJsonSchema),
        },
      },
    },
    inference: TextJsonSchema,
    confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
    approach: TextJsonSchema,
  },
};

const MemoryDeltaJsonSchema = {
  oneOf: [
    {
      type: 'object', additionalProperties: false,
      required: ['operation', 'candidate', 'reason', 'requiresConfirmation'],
      properties: {
        operation: { const: 'propose' }, reason: TextJsonSchema, requiresConfirmation: { type: 'boolean' },
        candidate: {
          type: 'object', additionalProperties: false,
          required: ['type', 'statement', 'provenance', 'lifecycle', 'confidence', 'sourceMessageIds', 'supersedesId'],
          properties: {
            type: { type: 'string', enum: ['goal', 'commitment', 'decision', 'preference', 'career_context', 'development_area', 'evidence', 'pattern'] },
            statement: TextJsonSchema,
            provenance: { type: 'string', enum: ['user-stated', 'user-confirmed', 'ai-inferred', 'system-observed'] },
            lifecycle: { type: 'string', enum: ['proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived'] },
            confidence: { type: 'string', enum: ['tentative', 'supported', 'established'] },
            sourceMessageIds: IdListJsonSchema,
            supersedesId: nullable(IdJsonSchema),
          },
        },
      },
    },
    {
      type: 'object', additionalProperties: false,
      required: ['operation', 'targetId', 'to', 'reason', 'requiresConfirmation'],
      properties: {
        operation: { const: 'transition' }, targetId: IdJsonSchema,
        to: { type: 'string', enum: ['proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived'] },
        reason: TextJsonSchema, requiresConfirmation: { type: 'boolean' },
      },
    },
    {
      type: 'object', additionalProperties: false,
      required: ['operation', 'targetId', 'sourceMessageId', 'reason', 'requiresConfirmation'],
      properties: {
        operation: { const: 'support' }, targetId: IdJsonSchema, sourceMessageId: IdJsonSchema,
        reason: TextJsonSchema, requiresConfirmation: { const: false },
      },
    },
  ],
};

const ProposalJsonSchema = {
  oneOf: [
    { type: 'object', additionalProperties: false, required: ['kind', 'title', 'description', 'priority', 'targetDate'], properties: {
      kind: { const: 'goal' }, title: TextJsonSchema, description: nullable(TextJsonSchema),
      priority: nullable({ type: 'string', enum: ['low', 'medium', 'high'] }), targetDate: nullable(TimestampJsonSchema),
    } },
    { type: 'object', additionalProperties: false, required: ['kind', 'title', 'description', 'priority', 'dueAt', 'goalId'], properties: {
      kind: { const: 'action' }, title: TextJsonSchema, description: nullable(TextJsonSchema),
      priority: nullable({ type: 'string', enum: ['low', 'medium', 'high'] }), dueAt: nullable(TimestampJsonSchema), goalId: nullable(IdJsonSchema),
    } },
    { type: 'object', additionalProperties: false, required: ['kind', 'actionId', 'weekStart', 'plannedDay'], properties: {
      kind: { const: 'weekly_work' }, actionId: IdJsonSchema, weekStart: TimestampJsonSchema, plannedDay: nullable(TimestampJsonSchema),
    } },
    { type: 'object', additionalProperties: false, required: ['kind', 'statement', 'occurredAt', 'goalId', 'actionId'], properties: {
      kind: { const: 'evidence' }, statement: TextJsonSchema, occurredAt: TimestampJsonSchema, goalId: nullable(IdJsonSchema), actionId: nullable(IdJsonSchema),
    } },
    { type: 'object', additionalProperties: false, required: ['kind', 'memory'], properties: { kind: { const: 'memory' }, memory: MemoryDeltaJsonSchema } },
    { type: 'object', additionalProperties: false, required: ['kind', 'body', 'isTimeSensitive', 'homeEligibleUntil'], properties: {
      kind: { const: 'insight' }, body: TextJsonSchema, isTimeSensitive: { type: 'boolean' }, homeEligibleUntil: nullable(TimestampJsonSchema),
    } },
  ],
};

const COACHING_RESPONSE_INPUT_SCHEMA = {
  type: 'object' as const,
  oneOf: [
    {
      type: 'object',
      additionalProperties: false,
      required: ['mode', 'relevance', 'contextSufficiency', 'reply', 'stance', 'explanation', 'proposal'],
      properties: {
        mode: { const: 'coach' },
        relevance: { type: 'string', enum: ['career-relevant', 'adjacent'] },
        contextSufficiency: { type: 'string', enum: ['sufficient', 'partial'] },
        reply: TextJsonSchema,
        stance: { type: 'string', enum: ['mirror', 'nudge', 'challenge', 'direct'] },
        explanation: ExplanationJsonSchema,
        proposal: nullable(ProposalJsonSchema),
        titleSuggestion: TitleSuggestionJsonSchema,
      },
    },
    {
      type: 'object',
      additionalProperties: false,
      required: ['mode', 'relevance', 'contextSufficiency', 'reply', 'stance', 'explanation', 'proposal'],
      properties: {
        mode: { const: 'clarify' },
        relevance: { type: 'string', enum: ['career-relevant', 'adjacent', 'outside-scope'] },
        contextSufficiency: { const: 'insufficient' },
        reply: TextJsonSchema,
        stance: { type: 'null' },
        explanation: ExplanationJsonSchema,
        proposal: { type: 'null' },
        titleSuggestion: TitleSuggestionJsonSchema,
      },
    },
    {
      type: 'object',
      additionalProperties: false,
      required: ['mode', 'relevance', 'contextSufficiency', 'reply', 'stance', 'explanation', 'proposal'],
      properties: {
        mode: { const: 'redirect' },
        relevance: { const: 'outside-scope' },
        contextSufficiency: { type: 'string', enum: ['sufficient', 'partial'] },
        reply: TextJsonSchema,
        stance: { type: 'null' },
        explanation: ExplanationJsonSchema,
        proposal: { type: 'null' },
        titleSuggestion: TitleSuggestionJsonSchema,
      },
    },
  ],
};

export function createAnthropicProvider(
  config: CoachingProviderConfig,
  client: AnthropicClient = anthropicClient,
): CoachingProvider {
  return {
    id: 'anthropic',
    estimateMaximumUsage: (input) => estimateMaximumCoachingUsage('anthropic', input, config),
    async respond(input: ProviderCoachingInput) {
      let message;
      try {
        message = await client.messages.create(
          {
            model: config.model,
            max_tokens: config.maxOutputTokens,
            system: input.systemPrompt,
            messages: [{ role: 'user', content: input.userPrompt }],
            tools: [
              {
                name: 'submit_coaching_response',
                description: 'Return the structured coaching response for this submitted turn.',
                input_schema: COACHING_RESPONSE_INPUT_SCHEMA,
              },
            ],
            tool_choice: {
              type: 'tool',
              name: 'submit_coaching_response',
              disable_parallel_tool_use: true,
            },
          },
          { maxRetries: 0 },
        );
      } catch (error) {
        throw normalizeAnthropicSdkFailure(error);
      }

      const toolUse = message.content.find(
        (block) => block.type === 'tool_use' && block.name === 'submit_coaching_response',
      );
      const payload = CoachingResponsePayloadSchema.parse(toolUse?.type === 'tool_use' ? toolUse.input : undefined);
      const inputTokens = message.usage.input_tokens;
      const outputTokens = message.usage.output_tokens;

      return {
        payload,
        usage: {
          provider: 'anthropic',
          model: config.model,
          inputTokens,
          outputTokens,
          estimatedCostUsd: estimateCostUsd(inputTokens, outputTokens, config),
        },
      };
    },
    async *streamRespond(input: ProviderCoachingInput) {
      try {
        const stream = client.messages.stream({
          model: config.model, max_tokens: config.maxOutputTokens, system: input.systemPrompt,
          messages: [{ role: 'user', content: input.userPrompt }],
          tools: [{ name: 'submit_coaching_response', description: 'Return the structured coaching response for this submitted turn.', input_schema: COACHING_RESPONSE_INPUT_SCHEMA }],
          tool_choice: { type: 'tool', name: 'submit_coaching_response', disable_parallel_tool_use: true },
        }, { maxRetries: 0 });
        let raw = '';
        let emitted = '';
        for await (const event of stream) {
          if (event.type !== 'content_block_delta' || event.delta.type !== 'input_json_delta') continue;
          raw += event.delta.partial_json;
          const reply = extractReplyPrefix(raw);
          if (reply.length > emitted.length) {
            yield { kind: 'delta', delta: reply.slice(emitted.length) } as const;
            emitted = reply;
          }
        }
        const message = await stream.finalMessage();
        const toolUse = message.content.find((block) => block.type === 'tool_use' && block.name === 'submit_coaching_response');
        const payload = CoachingResponsePayloadSchema.parse(toolUse?.type === 'tool_use' ? toolUse.input : undefined);
        const inputTokens = message.usage.input_tokens;
        const outputTokens = message.usage.output_tokens;
        yield { kind: 'completed', result: { payload, usage: {
          provider: 'anthropic', model: config.model, inputTokens, outputTokens,
          estimatedCostUsd: estimateCostUsd(inputTokens, outputTokens, config),
        } } } as const;
      } catch (error) {
        console.warn(
          '[Taisa diagnostic] ANTHROPIC_COACHING_PROVIDER_FAILURE',
          contentFreeProviderDiagnostic(error),
        );
        throw normalizeAnthropicSdkFailure(error);
      }
    },
  };
}
