import OpenAI from 'openai';
import Anthropic from '@anthropic-ai/sdk';
import {
  ContentFilterFinishReasonError,
  LengthFinishReasonError,
} from 'openai/error';

type FailureRecord = Readonly<Record<string, unknown>>;

const DENIED_TYPES = new Set([
  'invalid_request_error',
  'safety_error',
  'content_policy_error',
  'policy_error',
]);

const OPERATIONAL_TYPES = new Set([
  'rate_limit_error',
  'overloaded_error',
  'authentication_error',
  'permission_error',
  'billing_error',
]);

function asRecord(value: unknown): FailureRecord | null {
  return value !== null && typeof value === 'object'
    ? value as FailureRecord
    : null;
}

function stringField(value: FailureRecord | null, field: string): string | null {
  const candidate = value?.[field];
  return typeof candidate === 'string' ? candidate : null;
}

function knownType(type: string | null): FailureRecord | null {
  if (!type) return null;
  if (DENIED_TYPES.has(type)) return Object.freeze({ type });
  if (OPERATIONAL_TYPES.has(type)) return Object.freeze({ type });
  return null;
}

function statusOnly(status: unknown): FailureRecord {
  return typeof status === 'number' && Number.isInteger(status)
    ? Object.freeze({ status })
    : Object.freeze({});
}

const CONTENT_FREE_TOKEN = /^[a-z][a-z0-9_.\[\]-]{0,119}$/;
const SAFE_PROVIDER_PARAMS = new Set([
  'model',
  'messages',
  'max_completion_tokens',
  'response_format',
  'tools',
  'tool_choice',
]);
const SAFE_ERROR_NAMES = new Set([
  'APIConnectionError',
  'APIConnectionTimeoutError',
  'BadRequestError',
  'ContentFilterFinishReasonError',
  'LengthFinishReasonError',
  'ZodError',
]);

function contentFreeToken(value: unknown): string | null {
  return typeof value === 'string' && CONTENT_FREE_TOKEN.test(value) ? value : null;
}

function contentFreeParam(value: unknown): string | null {
  const token = contentFreeToken(value);
  if (!token) return null;
  const root = token.split(/[.\[]/, 1)[0];
  return SAFE_PROVIDER_PARAMS.has(root) ? token : null;
}

export function contentFreeProviderDiagnostic(error: unknown): FailureRecord {
  const value = asRecord(error);
  if (!value) return Object.freeze({});
  const diagnostic: Record<string, unknown> = {};
  const name = typeof value.name === 'string' ? value.name : null;
  if (name && SAFE_ERROR_NAMES.has(name)) diagnostic.name = name;
  if (typeof value.status === 'number' && Number.isInteger(value.status)) {
    diagnostic.status = value.status;
  }
  for (const field of ['type', 'code'] as const) {
    const token = contentFreeToken(value[field]);
    if (token) diagnostic[field] = token;
  }
  const param = contentFreeParam(value.param);
  if (param) diagnostic.param = param;
  const cause = asRecord(value.cause);
  if (cause) {
    const nested = contentFreeProviderDiagnostic(cause);
    if (Object.keys(nested).length > 0) diagnostic.cause = nested;
  }
  return Object.freeze(diagnostic);
}

function openAIType(error: { type?: unknown }): string | null {
  return typeof error.type === 'string' ? error.type : null;
}

function anthropicType(error: { error?: unknown }): string | null {
  const response = asRecord(error.error);
  const nestedError = asRecord(response?.error);
  return stringField(nestedError, 'type');
}

export function normalizeOpenAISdkFailure(error: unknown): unknown {
  if (error instanceof ContentFilterFinishReasonError) {
    return Object.freeze({ type: 'content_policy_error' });
  }
  if (error instanceof LengthFinishReasonError) {
    return Object.freeze({ type: 'length_finish_reason_error' });
  }
  if (!(error instanceof OpenAI.APIError)) return error;

  const normalizedType = knownType(openAIType(error));
  if (normalizedType) return normalizedType;
  if (error instanceof OpenAI.APIConnectionTimeoutError) {
    return Object.freeze({ name: 'APIConnectionTimeoutError' });
  }
  if (error instanceof OpenAI.APIConnectionError) {
    return Object.freeze({ name: 'APIConnectionError' });
  }
  if (error instanceof OpenAI.BadRequestError) {
    return Object.freeze({ type: 'invalid_request_error' });
  }
  if (error instanceof OpenAI.AuthenticationError) {
    return Object.freeze({ type: 'authentication_error' });
  }
  if (error instanceof OpenAI.PermissionDeniedError) {
    return Object.freeze({ type: 'permission_error' });
  }
  if (error instanceof OpenAI.RateLimitError) {
    return Object.freeze({ type: 'rate_limit_error' });
  }
  return statusOnly(error.status);
}

export function normalizeAnthropicSdkFailure(error: unknown): unknown {
  if (!(error instanceof Anthropic.APIError)) return error;

  const normalizedType = knownType(anthropicType(error));
  if (normalizedType) return normalizedType;
  if (error instanceof Anthropic.APIConnectionTimeoutError) {
    return Object.freeze({ name: 'APIConnectionTimeoutError' });
  }
  if (error instanceof Anthropic.APIConnectionError) {
    return Object.freeze({ name: 'APIConnectionError' });
  }
  if (error instanceof Anthropic.BadRequestError) {
    return Object.freeze({ type: 'invalid_request_error' });
  }
  if (error instanceof Anthropic.AuthenticationError) {
    return Object.freeze({ type: 'authentication_error' });
  }
  if (error instanceof Anthropic.PermissionDeniedError) {
    return Object.freeze({ type: 'permission_error' });
  }
  if (error instanceof Anthropic.RateLimitError) {
    return Object.freeze({ type: 'rate_limit_error' });
  }
  return statusOnly(error.status);
}
