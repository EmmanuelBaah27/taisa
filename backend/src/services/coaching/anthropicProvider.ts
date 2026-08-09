import type Anthropic from '@anthropic-ai/sdk';
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
  additionalProperties: false,
  required: ['reply', 'stance', 'proposals'],
  properties: {
    reply: { type: 'string', minLength: 1, maxLength: 4000 },
    stance: { type: 'string', enum: ['mirror', 'nudge', 'challenge', 'direct'] },
    proposals: {
      type: 'array',
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
        ],
      },
    },
  },
};

export function createAnthropicProvider(
  config: CoachingProviderConfig,
  client: AnthropicClient = anthropicClient,
): CoachingProvider {
  return {
    id: 'anthropic',
    async respond(input: ProviderCoachingInput) {
      const message = await client.messages.create({
        model: config.model,
        max_tokens: 2048,
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
      });

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
