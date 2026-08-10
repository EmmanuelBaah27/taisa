import {
  firstCoachingResponseContractViolation,
  type CoachingRequest,
  type CoachingResponse,
} from '@taisa/shared';

import api from './api';

interface HttpClient {
  post(path: string, body: unknown, config?: unknown): Promise<{ data: unknown }>;
}

export class CoachingClientError extends Error {
  constructor(readonly code: 'COACHING_REQUEST_FAILED' | 'INVALID_COACHING_RESPONSE') {
    super(code === 'INVALID_COACHING_RESPONSE'
      ? 'Taisa received an invalid coaching response.'
      : 'Taisa could not complete the coaching request.');
    this.name = 'CoachingClientError';
  }
}

function object(value: unknown): Record<string, unknown> | null {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function validatedResponse(value: unknown, requestId: string): CoachingResponse | null {
  const envelope = object(value);
  const data = envelope?.success === true ? object(envelope.data) : null;
  if (data === null || firstCoachingResponseContractViolation(data, requestId) !== null) return null;
  return data as unknown as CoachingResponse;
}

export function createCoachingClient(http: HttpClient) {
  return async function requestCoaching(request: CoachingRequest): Promise<CoachingResponse> {
    try {
      const response = await http.post('/coaching/respond', request, {
        headers: { 'x-request-id': request.requestId },
      });
      const validated = validatedResponse(response.data, request.requestId);
      if (validated === null) throw new CoachingClientError('INVALID_COACHING_RESPONSE');
      return validated;
    } catch (error) {
      if (error instanceof CoachingClientError) throw error;
      throw new CoachingClientError('COACHING_REQUEST_FAILED');
    }
  };
}

export const requestCoaching = createCoachingClient(api);
