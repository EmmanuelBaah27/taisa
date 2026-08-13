import type Anthropic from '@anthropic-ai/sdk';
import { COACHING_GATEWAY_LIMITS } from '@taisa/shared';
import anthropicClient from '../claude/client';
import { CoachingResponsePayloadSchema } from '../../schemas/coaching';
import type {
  CoachingProvider,
  CoachingProviderConfig,
  ProviderCoachingInput,
} from './provider';
import { estimateCostUsd } from './provider';

type AnthropicClient = Pick<Anthropic, 'messages'>;

const COACHING_RESPONSE_INPUT_SCHEMA = {
  type: 'object' as const,
  oneOf: [
    {
      type: 'object',
      additionalProperties: false,
      required: ['mode', 'relevance', 'contextSufficiency', 'reply', 'stance', 'proposals'],
      properties: {
        mode: { const: 'coach' },
        relevance: { type: 'string', enum: ['career-relevant', 'adjacent'] },
        contextSufficiency: { type: 'string', enum: ['sufficient', 'partial'] },
        reply: { type: 'string', minLength: 1, maxLength: 4000 },
        stance: { type: 'string', enum: ['mirror', 'nudge', 'challenge', 'direct'] },
        proposals: {
          type: 'array',
          maxItems: COACHING_GATEWAY_LIMITS.maxProposals,
          items: {
            oneOf: [
          {
            type: 'object',
            additionalProperties: false,
            required: ['operation', 'candidate', 'reason', 'requiresConfirmation'],
            properties: {
              operation: { const: 'propose' },
              candidate: {
                type: 'object',
                additionalProperties: false,
                required: [
                  'type',
                  'statement',
                  'provenance',
                  'lifecycle',
                  'confidence',
                  'sourceMessageIds',
                ],
                properties: {
                  type: {
                    type: 'string',
                    enum: [
                      'goal',
                      'commitment',
                      'decision',
                      'preference',
                      'career_context',
                      'development_area',
                      'evidence',
                      'pattern',
                    ],
                  },
                  statement: { type: 'string' },
                  provenance: {
                    type: 'string',
                    enum: ['user-stated', 'user-confirmed', 'ai-inferred', 'system-observed'],
                  },
                  lifecycle: {
                    type: 'string',
                    enum: ['proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived'],
                  },
                  confidence: { type: 'string', enum: ['tentative', 'supported', 'established'] },
                  sourceMessageIds: { type: 'array', items: { type: 'string' } },
                  supersedesId: { type: ['string', 'null'] },
                },
              },
              reason: { type: 'string' },
              requiresConfirmation: { type: 'boolean' },
            },
          },
          {
            type: 'object',
            additionalProperties: false,
            required: ['operation', 'targetId', 'to', 'reason', 'requiresConfirmation'],
            properties: {
              operation: { const: 'transition' },
              targetId: { type: 'string' },
              to: {
                type: 'string',
                enum: ['proposed', 'active', 'paused', 'superseded', 'completed', 'rejected', 'archived'],
              },
              reason: { type: 'string' },
              requiresConfirmation: { type: 'boolean' },
            },
          },
          {
            type: 'object',
            additionalProperties: false,
            required: [
              'operation',
              'targetId',
              'sourceMessageId',
              'reason',
              'requiresConfirmation',
            ],
            properties: {
              operation: { const: 'support' },
              targetId: { type: 'string' },
              sourceMessageId: { type: 'string' },
              reason: { type: 'string' },
              requiresConfirmation: { const: false },
            },
          },
          {
            type: 'object',
            additionalProperties: false,
            required: ['operation', 'candidate', 'reason', 'requiresConfirmation'],
            properties: {
              operation: { const: 'propose-outcome' },
              candidate: {
                oneOf: [
                  {
                    type: 'object',
                    additionalProperties: false,
                    required: ['kind', 'title', 'description', 'priority', 'targetDate', 'supersedesId'],
                    properties: {
                      kind: { const: 'goal' },
                      title: { type: 'string' },
                      description: { type: ['string', 'null'] },
                      priority: { type: ['string', 'null'], enum: ['low', 'medium', 'high', null] },
                      targetDate: { type: ['string', 'null'] },
                      supersedesId: { type: ['string', 'null'] },
                    },
                  },
                  {
                    type: 'object',
                    additionalProperties: false,
                    required: ['kind', 'title', 'description', 'priority', 'dueAt', 'goalId', 'supersedesId'],
                    properties: {
                      kind: { const: 'action' },
                      title: { type: 'string' },
                      description: { type: ['string', 'null'] },
                      priority: { type: ['string', 'null'], enum: ['low', 'medium', 'high', null] },
                      dueAt: { type: ['string', 'null'] },
                      goalId: { type: ['string', 'null'] },
                      supersedesId: { type: ['string', 'null'] },
                    },
                  },
                  {
                    type: 'object',
                    additionalProperties: false,
                    required: ['kind', 'statement', 'occurredAt', 'goalIds', 'actionIds'],
                    properties: {
                      kind: { const: 'evidence' },
                      statement: { type: 'string' },
                      occurredAt: { type: 'string' },
                      goalIds: { type: 'array', items: { type: 'string' } },
                      actionIds: { type: 'array', items: { type: 'string' } },
                    },
                  },
                ],
              },
              reason: { type: 'string' },
              requiresConfirmation: { const: true },
            },
          },
        ],
          },
        },
      },
    },
    {
      type: 'object',
      additionalProperties: false,
      required: ['mode', 'relevance', 'contextSufficiency', 'reply', 'stance', 'proposals'],
      properties: {
        mode: { const: 'clarify' },
        relevance: { type: 'string', enum: ['career-relevant', 'adjacent', 'outside-scope'] },
        contextSufficiency: { const: 'insufficient' },
        reply: { type: 'string', minLength: 1, maxLength: 4000 },
        stance: { type: 'null' },
        proposals: { type: 'array', minItems: 0, maxItems: 0 },
      },
    },
    {
      type: 'object',
      additionalProperties: false,
      required: ['mode', 'relevance', 'contextSufficiency', 'reply', 'stance', 'proposals'],
      properties: {
        mode: { const: 'redirect' },
        relevance: { const: 'outside-scope' },
        contextSufficiency: { type: 'string', enum: ['sufficient', 'partial'] },
        reply: { type: 'string', minLength: 1, maxLength: 4000 },
        stance: { type: 'null' },
        proposals: { type: 'array', minItems: 0, maxItems: 0 },
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
    async respond(input: ProviderCoachingInput) {
      const message = await client.messages.create(
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
  };
}
