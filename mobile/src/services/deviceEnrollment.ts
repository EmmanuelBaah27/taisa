import * as SecureStore from 'expo-secure-store';

const DEVICE_CREDENTIAL_KEY = 'taisa.device-credential.v1';

interface EnrollmentHttpClient {
  post(path: string, body: unknown): Promise<{ data?: unknown }>;
}

interface EnrollmentResponse {
  success: true;
  data: { credentialId: string; token: string };
}

function parseEnrollmentResponse(value: unknown): EnrollmentResponse | null {
  if (typeof value !== 'object' || value === null) return null;
  const response = value as Partial<EnrollmentResponse>;
  const data = response.data;
  if (
    response.success !== true
    || typeof data !== 'object'
    || data === null
    || typeof data.credentialId !== 'string'
    || data.credentialId.length === 0
    || typeof data.token !== 'string'
    || data.token.length < 32
  ) return null;
  return response as EnrollmentResponse;
}

export async function getDeviceCredential(): Promise<string | null> {
  const token = await SecureStore.getItemAsync(DEVICE_CREDENTIAL_KEY);
  return token && token.length >= 32 ? token : null;
}

export async function clearDeviceCredential(): Promise<void> {
  await SecureStore.deleteItemAsync(DEVICE_CREDENTIAL_KEY);
}

export function createDeviceEnrollmentClient(http: EnrollmentHttpClient) {
  return {
    async enroll(code: string): Promise<{ credentialId: string }> {
      if (!code.trim()) throw new Error('Device enrollment failed');
      const response = await http.post('/device-enrollments', { code });
      const parsed = parseEnrollmentResponse(response.data);
      if (parsed === null) throw new Error('Device enrollment failed');
      await SecureStore.setItemAsync(DEVICE_CREDENTIAL_KEY, parsed.data.token, {
        keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
      });
      return { credentialId: parsed.data.credentialId };
    },
  };
}
