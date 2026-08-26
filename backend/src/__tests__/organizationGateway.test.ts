import type { OrganizationRequest } from '@taisa/shared';

import { createOrganizationAnalyzer } from '../services/organization/organizationGateway';
import type { CoachingProvider } from '../services/coaching/provider';
import { createOpenAIProvider } from '../services/coaching/openaiProvider';
import { createAnthropicProvider } from '../services/coaching/anthropicProvider';
import { OrganizationResponseSchema } from '../schemas/organization';

const request = {
  requestId: '11111111-1111-4111-8111-111111111111',
  submittedAt: '2026-08-26T08:00:00Z',
  scope: 'week',
  records: [{
    id: 'task-1', kind: 'task', title: 'Send proposal', status: 'open',
    revision: 1, projectId: null,
  }],
  conversations: [{ id: 'conversation-1', summary: 'Planned the proposal', revision: 2 }],
} satisfies OrganizationRequest;

test('organization analyzer makes one schema-driven provider call', async () => {
  const provider: CoachingProvider = {
    id: 'openai',
    respond: jest.fn(),
    respondJson: jest.fn().mockResolvedValue({
      payload: { requestId: request.requestId, proposals: [] },
      usage: { provider: 'openai', model: 'mock', estimatedCostUsd: 0.01 },
    }),
  };
  const analyzer = createOrganizationAnalyzer(provider);

  await expect(analyzer.analyze(request)).resolves.toEqual({
    requestId: request.requestId,
    proposals: [],
  });
  expect(provider.respondJson).toHaveBeenCalledTimes(1);
  expect(provider.respond).not.toHaveBeenCalled();
});

test('organization analyzer rejects a provider that changes request correlation', async () => {
  const provider: CoachingProvider = {
    id: 'anthropic',
    respond: jest.fn(),
    respondJson: jest.fn().mockResolvedValue({
      payload: { requestId: '22222222-2222-4222-8222-222222222222', proposals: [] },
      usage: { provider: 'anthropic', model: 'mock', estimatedCostUsd: 0.01 },
    }),
  };

  await expect(createOrganizationAnalyzer(provider).analyze(request))
    .rejects.toMatchObject({ code: 'INVALID_ORGANIZATION_OUTPUT' });
});

const config = {
  model: 'test-model', inputPriceUsdPerMillionTokens: 1,
  outputPriceUsdPerMillionTokens: 1, maxOutputTokens: 500,
  structuredOutputInputTokenOverhead: 10,
};

test('OpenAI adapter parses schema-driven JSON independently of coaching', async () => {
  const parse = jest.fn().mockResolvedValue({
    choices: [{ message: { parsed: { response: { requestId: request.requestId, proposals: [] } } } }],
    usage: { prompt_tokens: 10, completion_tokens: 5 },
  });
  const provider = createOpenAIProvider(config, {
    beta: { chat: { completions: { parse } } },
  } as never);

  await expect(provider.respondJson?.(
    { systemPrompt: 'system', userPrompt: 'user' },
    OrganizationResponseSchema,
    'organization_response',
  )).resolves.toMatchObject({ payload: { requestId: request.requestId, proposals: [] } });
  expect(parse).toHaveBeenCalledTimes(1);
});

test('Anthropic adapter parses JSON text through the supplied schema', async () => {
  const create = jest.fn().mockResolvedValue({
    content: [{ type: 'text', text: JSON.stringify({ requestId: request.requestId, proposals: [] }) }],
    usage: { input_tokens: 10, output_tokens: 5 },
  });
  const provider = createAnthropicProvider(config, { messages: { create } } as never);

  await expect(provider.respondJson?.(
    { systemPrompt: 'system', userPrompt: 'user' },
    OrganizationResponseSchema,
    'organization_response',
  )).resolves.toMatchObject({ payload: { requestId: request.requestId, proposals: [] } });
  expect(create).toHaveBeenCalledTimes(1);
});
