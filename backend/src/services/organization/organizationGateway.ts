import type { OrganizationRequest, OrganizationResponse } from '@taisa/shared';

import { OrganizationResponseSchema } from '../../schemas/organization';
import type { OrganizationAnalyzer } from '../../routes/organization';
import { getConfiguredProvider, type CoachingProvider } from '../coaching/provider';

export class InvalidOrganizationOutputError extends Error {
  readonly code = 'INVALID_ORGANIZATION_OUTPUT';

  constructor() {
    super('The organization provider returned invalid output');
    this.name = 'InvalidOrganizationOutputError';
  }
}

function prompt(request: OrganizationRequest) {
  return {
    systemPrompt: [
      'You organize only the bounded work scope supplied by the user.',
      'Return proposal envelopes only. Never claim to mutate records.',
      'Every proposal must cite supplied source and evidence IDs.',
      'Use ambiguity=strong only for explicit language; otherwise use ambiguous.',
    ].join(' '),
    userPrompt: JSON.stringify(request),
  };
}

export function createOrganizationAnalyzer(provider: CoachingProvider): OrganizationAnalyzer {
  return {
    async analyze(request): Promise<OrganizationResponse> {
      if (!provider.respondJson) throw new Error('Provider does not support structured JSON');
      const result = await provider.respondJson(
        prompt(request),
        OrganizationResponseSchema,
        'organization_response',
      );
      if (result.payload.requestId !== request.requestId) {
        throw new InvalidOrganizationOutputError();
      }
      return result.payload;
    },
  };
}

export function getConfiguredOrganizationAnalyzer(): OrganizationAnalyzer {
  return createOrganizationAnalyzer(getConfiguredProvider());
}
