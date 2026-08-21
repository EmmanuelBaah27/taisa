export type OperationalFailureClass =
  | 'timeout'
  | 'network'
  | 'rate_limit'
  | 'overloaded'
  | 'authentication'
  | 'permission'
  | 'billing'
  | 'unavailable';

type FailureRecord = Record<string, unknown>;

const DENIED_TYPES = new Set([
  'invalid_request_error',
  'safety_error',
  'content_policy_error',
  'policy_error',
]);

const TYPE_CLASSES: Record<string, OperationalFailureClass> = {
  rate_limit_error: 'rate_limit',
  overloaded_error: 'overloaded',
  authentication_error: 'authentication',
  permission_error: 'permission',
  billing_error: 'billing',
};

const NAME_CLASSES: Record<string, OperationalFailureClass> = {
  APIConnectionTimeoutError: 'timeout',
  APIConnectionError: 'network',
  RateLimitError: 'rate_limit',
  OverloadedError: 'overloaded',
  AuthenticationError: 'authentication',
  PermissionDeniedError: 'permission',
  BillingError: 'billing',
  InternalServerError: 'unavailable',
  ServiceUnavailableError: 'unavailable',
};

const NETWORK_CODES: Record<string, OperationalFailureClass> = {
  ETIMEDOUT: 'timeout',
  ECONNRESET: 'network',
  ECONNREFUSED: 'network',
  ENOTFOUND: 'network',
  EAI_AGAIN: 'network',
  EHOSTUNREACH: 'network',
  ENETUNREACH: 'network',
};

function asRecord(error: unknown): FailureRecord | null {
  return error !== null && typeof error === 'object'
    ? error as FailureRecord
    : null;
}

function stringField(value: FailureRecord, field: string): string | null {
  const candidate = value[field];
  return typeof candidate === 'string' ? candidate : null;
}

function integerField(value: FailureRecord, field: string): number | null {
  const candidate = value[field];
  return typeof candidate === 'number' && Number.isInteger(candidate) ? candidate : null;
}

function classifyKnownTypeOrNetworkCode(
  value: FailureRecord,
): OperationalFailureClass | null {
  const type = stringField(value, 'type');
  if (type && TYPE_CLASSES[type]) return TYPE_CLASSES[type];

  const name = stringField(value, 'name');
  if (name && NAME_CLASSES[name]) return NAME_CLASSES[name];

  const code = stringField(value, 'code');
  if (code && NETWORK_CODES[code]) return NETWORK_CODES[code];

  return null;
}

export function classifyOperationalProviderFailure(
  error: unknown,
): OperationalFailureClass | null {
  const value = asRecord(error);
  if (!value) return null;

  const type = stringField(value, 'type');
  if (type && DENIED_TYPES.has(type)) return null;

  const status = integerField(value, 'status');
  if (status === 408) return 'timeout';
  if (status === 409) return 'unavailable';
  if (status === 429) return 'rate_limit';
  if (status !== null && status >= 500 && status <= 599) return 'unavailable';

  return classifyKnownTypeOrNetworkCode(value);
}
