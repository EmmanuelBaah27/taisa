import * as Crypto from 'expo-crypto';

export const MUTATION_FINGERPRINT_VERSION = 1;

function canonicalize(value: unknown): string {
  if (value === null || value === undefined) {
    return 'null';
  }
  if (typeof value === 'string' || typeof value === 'boolean') {
    return JSON.stringify(value);
  }
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) {
      throw new TypeError('Mutation payload numbers must be finite');
    }
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(canonicalize).join(',')}]`;
  }
  if (typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalize((value as Record<string, unknown>)[key])}`)
      .join(',')}}`;
  }
  throw new TypeError(`Unsupported mutation payload value: ${typeof value}`);
}

export async function fingerprintMutationPayload(payload: unknown): Promise<string> {
  const digest = await Crypto.digestStringAsync(
    Crypto.CryptoDigestAlgorithm.SHA256,
    canonicalize(payload),
  );
  if (!/^[0-9a-f]{64}$/i.test(digest)) {
    throw new Error('Mutation fingerprint provider returned an invalid SHA-256 digest');
  }
  return digest.toLowerCase();
}
