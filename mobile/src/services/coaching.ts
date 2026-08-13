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

function transportDiagnostic(error: unknown): string {
  const record = object(error);
  const response = object(record?.response);
  const responseData = object(response?.data);
  const responseError = object(responseData?.error);
  const rawCode = typeof record?.code === 'string' ? record.code : 'UNKNOWN';
  const code = rawCode.replace(/[^a-zA-Z0-9]+/g, '_').toUpperCase().slice(0, 48) || 'UNKNOWN';
  const status = typeof response?.status === 'number' && Number.isInteger(response.status)
    ? `_HTTP_${response.status}`
    : '';
  const rawServerCode = typeof responseError?.code === 'string' ? responseError.code : '';
  const serverCode = rawServerCode.replace(/[^a-zA-Z0-9]+/g, '_').toUpperCase().slice(0, 80);
  return `COACHING_TRANSPORT_${code}${status}${serverCode ? `_SERVER_${serverCode}` : ''}`;
}

function validatedResponse(value: unknown, requestId: string): {
  response: CoachingResponse | null;
  violation: string | null;
} {
  const envelope = object(value);
  const data = envelope?.success === true ? object(envelope.data) : null;
  if (data === null) return { response: null, violation: 'envelope' };
  const violation = firstCoachingResponseContractViolation(data, requestId);
  return violation === null
    ? { response: data as unknown as CoachingResponse, violation: null }
    : { response: null, violation };
}

export function createCoachingClient(
  http: HttpClient,
  reportDiagnostic?: (code: string) => void,
) {
  return async function requestCoaching(request: CoachingRequest): Promise<CoachingResponse> {
    try {
      const response = await http.post('/coaching/respond', request, {
        headers: { 'x-request-id': request.requestId },
      });
      const validated = validatedResponse(response.data, request.requestId);
      if (validated.response === null) {
        const field = validated.violation?.replace(/[^a-zA-Z0-9]+/g, '_').toUpperCase() ?? 'UNKNOWN';
        reportDiagnostic?.(`COACHING_RESPONSE_INVALID_${field}`);
        throw new CoachingClientError('INVALID_COACHING_RESPONSE');
      }
      return validated.response;
    } catch (error) {
      if (error instanceof CoachingClientError) throw error;
      reportDiagnostic?.(transportDiagnostic(error));
      throw new CoachingClientError('COACHING_REQUEST_FAILED');
    }
  };
}

export const requestCoaching = createCoachingClient(
  api,
  (code) => console.warn(`[Taisa diagnostic] ${code}`),
);
